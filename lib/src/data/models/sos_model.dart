import 'package:DriveForme/src/data/utils/date_utils.dart';

class SosLocation {
  final String address;
  final double? latitude;
  final double? longitude;

  const SosLocation({required this.address, this.latitude, this.longitude});

  Map<String, dynamic> toJson() => {
    'address': address,
    if (latitude != null) 'latitude': latitude,
    if (longitude != null) 'longitude': longitude,
  };

  factory SosLocation.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const SosLocation(address: '');
    return SosLocation(
      address: json['address']?.toString() ?? '',
      latitude: _toDouble(json['latitude']),
      longitude: _toDouble(json['longitude']),
    );
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}

class SosModel {
  final String id;
  final String sosType;
  final SosLocation location;
  final String? tripId;
  final String status;
  final String referenceNumber;
  final String? supportPhone;
  final DateTime? createdAt;

  const SosModel({
    required this.id,
    required this.sosType,
    required this.location,
    this.tripId,
    this.status = '',
    this.referenceNumber = '',
    this.supportPhone,
    this.createdAt,
  });

  factory SosModel.fromJson(Map<String, dynamic> json) {
    final locationRaw = json['location'];
    return SosModel(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      sosType: json['sosType']?.toString() ?? '',
      location: SosLocation.fromJson(
        locationRaw is Map ? Map<String, dynamic>.from(locationRaw) : null,
      ),
      tripId: json['tripId']?.toString(),
      status: json['status']?.toString() ?? '',
      referenceNumber:
          json['sosId']?.toString() ??
          json['referenceNumber']?.toString() ??
          json['reference']?.toString() ??
          '',
      supportPhone: json['supportPhone']?.toString(),
      createdAt: _parseDate(json['createdAt']),
    );
  }

  static DateTime? _parseDate(dynamic value) => parseApiDateTime(value);
}
