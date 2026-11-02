import 'package:intl/intl.dart';

double? _walletToDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

DateTime? _walletParseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value.toLocal();
  return DateTime.tryParse(value.toString())?.toLocal();
}

class WalletTransaction {
  final String id;
  final String type;
  final String category;
  final String description;
  final double amount;
  final double balanceAfter;
  final DateTime? createdAt;

  const WalletTransaction({
    required this.id,
    required this.type,
    required this.category,
    required this.description,
    required this.amount,
    required this.balanceAfter,
    this.createdAt,
  });

  bool get isCredit => type.toLowerCase() == 'credit';

  factory WalletTransaction.fromJson(Map<String, dynamic> json) {
    return WalletTransaction(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      amount: _walletToDouble(json['amount']) ?? 0,
      balanceAfter: _walletToDouble(json['balanceAfter']) ?? 0,
      createdAt: _walletParseDate(json['createdAt'] ?? json['date']),
    );
  }

  String get displayAmount {
    final prefix = isCredit ? '+' : '-';
    return '$prefix₹ ${amount.abs().toStringAsFixed(0)}';
  }

  String get displayDate {
    if (createdAt == null) return '—';
    return DateFormat('d MMM yyyy, hh:mm a').format(createdAt!);
  }

  String get walletListDate {
    if (createdAt == null) return '—';
    return DateFormat('EEE d, MMM h.mm a').format(createdAt!);
  }

  String get walletCreditAmount => '+ ₹${amount.abs().toStringAsFixed(0)}';

  String get walletDebitAmount => '- ₹${amount.abs().toStringAsFixed(0)}';

  bool get isReferralTransaction {
    final value = '${category.toLowerCase()} ${description.toLowerCase()}';
    return value.contains('referral') || value.contains('refer');
  }

  bool get isRideTransaction {
    final value = '${category.toLowerCase()} ${description.toLowerCase()}';
    return value.contains('ride') ||
        value.contains('trip') ||
        value.contains('drive');
  }

  String get displayTitle =>
      description.isEmpty ? category : description;
}

class WalletSummary {
  final double totalCredits;
  final double totalDebits;

  const WalletSummary({
    this.totalCredits = 0,
    this.totalDebits = 0,
  });

  factory WalletSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const WalletSummary();
    return WalletSummary(
      totalCredits: _walletToDouble(json['totalCredits']) ?? 0,
      totalDebits: _walletToDouble(json['totalDebits']) ?? 0,
    );
  }
}

class WalletModel {
  final double walletBalance;
  final String referralCode;
  final List<WalletTransaction> transactions;
  final WalletSummary summary;

  const WalletModel({
    required this.walletBalance,
    this.referralCode = '',
    this.transactions = const [],
    this.summary = const WalletSummary(),
  });

  factory WalletModel.fromJson(Map<String, dynamic> json) {
    final txList = json['transactions'];
    return WalletModel(
      walletBalance: _walletToDouble(json['walletBalance']) ?? 0,
      referralCode: json['referralCode']?.toString() ?? '',
      transactions: txList is List
          ? txList
              .whereType<Map>()
              .map((e) => WalletTransaction.fromJson(
                    Map<String, dynamic>.from(e),
                  ))
              .toList()
          : const [],
      summary: WalletSummary.fromJson(
        json['summary'] is Map
            ? Map<String, dynamic>.from(json['summary'] as Map)
            : null,
      ),
    );
  }

  String get displayBalance => '₹ ${walletBalance.toStringAsFixed(0)}';

  String get displayBalanceDetailed => '₹${walletBalance.toStringAsFixed(3)}';
}

class RazorpayOrderModel {
  const RazorpayOrderModel({
    required this.orderId,
    required this.amount,
    required this.currency,
    required this.transactionId,
  });

  final String orderId;
  final double amount;
  final String currency;
  final String transactionId;

  factory RazorpayOrderModel.fromJson(Map<String, dynamic> json) {
    final order = json['order'] as Map<String, dynamic>? ?? {};
    final rawAmount = order['amount'];
    final amountInPaise = rawAmount is num ? rawAmount.toDouble() : 0;
    return RazorpayOrderModel(
      orderId: order['id']?.toString() ?? '',
      amount: amountInPaise / 100,
      currency: order['currency']?.toString() ?? 'INR',
      transactionId: json['transactionId']?.toString() ?? '',
    );
  }
}

class WalletActionResult {
  const WalletActionResult({required this.walletBalance});

  final double walletBalance;

  factory WalletActionResult.fromJson(Map<String, dynamic> json) {
    return WalletActionResult(
      walletBalance: _walletToDouble(json['walletBalance']) ?? 0,
    );
  }
}

String formatRupee(double amount) {
  if (amount == amount.truncateToDouble()) {
    return '₹ ${amount.toInt()}';
  }
  return '₹ ${amount.toStringAsFixed(2)}';
}
