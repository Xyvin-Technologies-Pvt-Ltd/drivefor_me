import 'package:intl/intl.dart';

final _apiDateTimePattern = RegExp(r'^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}');
final _apiZoneSuffix = RegExp(r'(Z|[+-]\d{2}:?\d{2})$', caseSensitive: false);

/// API timestamps are UTC instants. Returns the same moment in the phone's zone.
DateTime? parseApiDateTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value.toLocal();
  if (value is num) {
    final raw = value.toInt();
    final millis = raw.abs() < 100000000000 ? raw * 1000 : raw;
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true).toLocal();
  }
  if (value is Map) {
    final nested = value[r'$date'] ?? value['date'] ?? value['iso'];
    if (nested != null) return parseApiDateTime(nested);
  }

  var raw = value.toString().trim();
  if (raw.isEmpty) return null;
  // A zone-less datetime is a UTC instant. Date-only values stay calendar dates.
  if (_apiDateTimePattern.hasMatch(raw) && !_apiZoneSuffix.hasMatch(raw)) {
    raw = '${raw}Z';
  }
  return DateTime.tryParse(raw)?.toLocal();
}

String formatLocalDateTime(DateTime value, String pattern) {
  return DateFormat(pattern).format(value.toLocal());
}

String dobUiToApi(String ddMmYyyy) {
  final parts = ddMmYyyy.split('/');
  if (parts.length != 3) {
    throw FormatException('Date must be in DD/MM/YYYY format');
  }

  final day = parts[0].padLeft(2, '0');
  final month = parts[1].padLeft(2, '0');
  final year = parts[2];

  return '$year-$month-$day';
}

String genderUiToApi(String gender) => gender.toLowerCase();
