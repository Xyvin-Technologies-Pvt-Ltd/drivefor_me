import 'package:DriveForme/src/data/constants/app_colors.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

class RazorpayCheckoutService {
  RazorpayCheckoutService() : _razorpay = Razorpay();

  final Razorpay _razorpay;
  void Function(PaymentSuccessResponse response)? _onSuccess;
  void Function(PaymentFailureResponse response)? _onFailure;

  String get keyId => dotenv.env['RAZORPAY_KEY_ID']?.trim() ?? '';

  bool get isConfigured => keyId.isNotEmpty;

  String _normalizeContact(String contact) {
    final digitsOnly = contact.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.length >= 10) {
      return digitsOnly.substring(digitsOnly.length - 10);
    }
    return digitsOnly;
  }

  void open({
    required String orderId,
    required double amount,
    required String name,
    required String contact,
    String? email,
    required void Function(PaymentSuccessResponse response) onSuccess,
    required void Function(PaymentFailureResponse response) onFailure,
  }) {
    if (!isConfigured) {
      throw StateError('Razorpay key is not configured.');
    }

    disposeListeners();
    _onSuccess = onSuccess;
    _onFailure = onFailure;

    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handleSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handleFailure);

    final normalizedContact = _normalizeContact(contact);
    final normalizedEmail = email?.trim();
    final themeColor =
        '#${AppColors.primaryBlue.toARGB32().toRadixString(16).substring(2)}';

    final options = <String, dynamic>{
      'key': keyId,
      'amount': (amount * 100).round(),
      'name': 'Drive For Me',
      'order_id': orderId,
      'description': 'Wallet recharge',
      'method': <String, bool>{
        'upi': true,
        'card': true,
        'netbanking': true,
        'wallet': true,
        'paylater': true,
        'emi': true,
      },
      'prefill': <String, String>{
        if (normalizedContact.isNotEmpty) 'contact': normalizedContact,
        'name': name,
        if (normalizedEmail != null && normalizedEmail.isNotEmpty)
          'email': normalizedEmail,
      },
      'theme': {'color': themeColor},
    };

    _razorpay.open(options);
  }

  void _handleSuccess(PaymentSuccessResponse response) {
    _onSuccess?.call(response);
    disposeListeners();
  }

  void _handleFailure(PaymentFailureResponse response) {
    _onFailure?.call(response);
    disposeListeners();
  }

  void disposeListeners() {
    _razorpay.clear();
    _onSuccess = null;
    _onFailure = null;
  }

  void dispose() {
    disposeListeners();
  }
}
