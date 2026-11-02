import 'package:DriveForme/src/data/models/api_response.dart';
import 'package:DriveForme/src/data/models/wallet_model.dart';
import 'package:DriveForme/src/data/providers/api_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WalletApi {
  final ApiProvider _api;

  WalletApi(this._api);

  Future<ApiResponse<WalletModel>> getWallet() async {
    final response = await _api.get('/wallet', requireAuth: true);

    if (!response.success) {
      return ApiResponse.error(
        response.message ?? 'Failed to load wallet.',
        response.statusCode,
      );
    }

    final data = nestedData(response.data);
    if (data == null) {
      return ApiResponse.error('Invalid wallet response');
    }

    return ApiResponse.success(
      WalletModel.fromJson(data),
      response.statusCode,
    );
  }

  Future<ApiResponse<void>> applyReferral(String referralCode) async {
    final response = await _api.post(
      '/wallet/apply-referral',
      {'referralCode': referralCode.trim()},
      requireAuth: true,
    );

    if (!response.success) {
      return ApiResponse.error(
        response.message ?? 'Failed to apply referral code.',
        response.statusCode,
      );
    }

    return ApiResponse.success(null, response.statusCode);
  }

  Future<ApiResponse<WalletModel>> rechargeWallet({
    required double amount,
    String? description,
  }) async {
    final response = await _api.post(
      '/wallet/recharge',
      {
        'amount': amount,
        if (description != null && description.isNotEmpty)
          'description': description,
      },
      requireAuth: true,
    );

    if (!response.success) {
      return ApiResponse.error(
        response.message ?? 'Failed to recharge wallet.',
        response.statusCode,
      );
    }

    return getWallet();
  }

  Future<ApiResponse<RazorpayOrderModel>> createRazorpayOrder({
    required double amount,
  }) async {
    final response = await _api.post(
      '/wallet/recharge/razorpay-order',
      {'amount': amount},
      requireAuth: true,
    );

    if (!response.success) {
      return ApiResponse.error(
        response.message ?? 'Failed to create payment order.',
        response.statusCode,
      );
    }

    final data = nestedData(response.data);
    if (data == null) {
      return ApiResponse.error('Invalid Razorpay order response');
    }

    return ApiResponse.success(
      RazorpayOrderModel.fromJson(data),
      response.statusCode,
    );
  }

  Future<ApiResponse<WalletActionResult>> verifyRazorpayPayment({
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
    String? transactionId,
  }) async {
    final response = await _api.post(
      '/wallet/recharge/razorpay-verify',
      {
        'razorpay_order_id': razorpayOrderId,
        'razorpay_payment_id': razorpayPaymentId,
        'razorpay_signature': razorpaySignature,
        if (transactionId != null && transactionId.isNotEmpty)
          'transactionId': transactionId,
      },
      requireAuth: true,
    );

    if (!response.success) {
      return ApiResponse.error(
        response.message ?? 'Payment verification failed.',
        response.statusCode,
      );
    }

    final data = nestedData(response.data);
    if (data == null) {
      return ApiResponse.error('Invalid payment verification response');
    }

    return ApiResponse.success(
      WalletActionResult.fromJson(data),
      response.statusCode,
    );
  }
}

final walletApiProvider = Provider<WalletApi>((ref) {
  return WalletApi(ref.watch(apiProviderProvider));
});
