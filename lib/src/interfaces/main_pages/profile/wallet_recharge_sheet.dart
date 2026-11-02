import 'package:DriveForme/src/data/apis/wallet_api.dart';
import 'package:DriveForme/src/data/constants/colour_constants.dart';
import 'package:DriveForme/src/data/constants/style_constants.dart';
import 'package:DriveForme/src/data/models/wallet_model.dart';
import 'package:DriveForme/src/data/providers/loading_provider.dart';
import 'package:DriveForme/src/data/providers/user_provider.dart';
import 'package:DriveForme/src/data/providers/wallet_provider.dart';
import 'package:DriveForme/src/data/services/razorpay_checkout_service.dart';
import 'package:DriveForme/src/interfaces/components/primaryButton.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

enum _RechargeStep { amount, processing, success, failed }

class WalletRechargeSheet extends ConsumerStatefulWidget {
  const WalletRechargeSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const WalletRechargeSheet(),
    );
  }

  @override
  ConsumerState<WalletRechargeSheet> createState() =>
      _WalletRechargeSheetState();
}

class _WalletRechargeSheetState extends ConsumerState<WalletRechargeSheet> {
  static const _presetAmounts = [100.0, 500.0, 1000.0, 2000.0];

  final _amountController = TextEditingController();
  final _razorpayCheckout = RazorpayCheckoutService();
  double? _selectedAmount;

  _RechargeStep _step = _RechargeStep.amount;
  String _processingLabel = 'Processing Payment';
  double _confirmedAmount = 0;
  String _failureMessage = 'Something went wrong with your payment.';

  @override
  void dispose() {
    _amountController.dispose();
    _razorpayCheckout.dispose();
    super.dispose();
  }

  double? get _rechargeAmount {
    if (_selectedAmount != null) return _selectedAmount;
    return double.tryParse(_amountController.text.trim());
  }

  bool get _usesRazorpay => _razorpayCheckout.isConfigured;

  Future<void> _submitRecharge() async {
    final amount = _rechargeAmount;
    if (amount == null || amount <= 0) {
      _showMessage('Enter a valid recharge amount.');
      return;
    }

    setState(() {
      _confirmedAmount = amount;
      _processingLabel = 'Processing Payment';
      _step = _RechargeStep.processing;
    });
    ref.read(loadingProvider.notifier).startLoading();

    if (_usesRazorpay) {
      await _payWithRazorpay(amount);
    } else {
      await _payWithDemoRecharge(amount);
    }

    ref.read(loadingProvider.notifier).stopLoading();
  }

  Future<void> _payWithDemoRecharge(double amount) async {
    final response = await ref
        .read(walletApiProvider)
        .rechargeWallet(amount: amount, description: 'Wallet recharge');

    if (!mounted) return;

    if (!response.success) {
      _goToFailed(response.message ?? 'Recharge failed.');
      return;
    }

    ref.invalidate(walletProvider);
    ref.invalidate(userProvider);
    setState(() => _step = _RechargeStep.success);
  }

  Future<void> _payWithRazorpay(double amount) async {
    final orderResponse = await ref
        .read(walletApiProvider)
        .createRazorpayOrder(amount: amount);

    if (!mounted) return;

    if (!orderResponse.success || orderResponse.data == null) {
      _goToFailed(orderResponse.message ?? 'Failed to start payment.');
      return;
    }

    final order = orderResponse.data!;
    final user = await ref.read(userProvider.future);
    final contact = user?.phoneNumber ?? '';
    final name = user?.profile.fullName.trim().isNotEmpty == true
        ? user!.profile.fullName.trim()
        : 'User';
    final email = user?.profile.email.trim();

    try {
      _razorpayCheckout.open(
        orderId: order.orderId,
        amount: order.amount,
        name: name,
        contact: contact,
        email: email,
        onSuccess: (response) => _handleRazorpaySuccess(
          response: response,
          transactionId: order.transactionId,
        ),
        onFailure: _handleRazorpayFailure,
      );
    } catch (error) {
      _goToFailed(error.toString());
    }
  }

  Future<void> _handleRazorpaySuccess({
    required PaymentSuccessResponse response,
    required String transactionId,
  }) async {
    if (!mounted) return;
    setState(() => _processingLabel = 'Verifying Payment');
    ref.read(loadingProvider.notifier).startLoading();

    final verifyResponse = await ref
        .read(walletApiProvider)
        .verifyRazorpayPayment(
          razorpayOrderId: response.orderId ?? '',
          razorpayPaymentId: response.paymentId ?? '',
          razorpaySignature: response.signature ?? '',
          transactionId: transactionId,
        );

    ref.read(loadingProvider.notifier).stopLoading();
    if (!mounted) return;

    if (!verifyResponse.success) {
      _goToFailed(verifyResponse.message ?? 'Payment verification failed.');
      return;
    }

    ref.invalidate(walletProvider);
    ref.invalidate(userProvider);
    setState(() => _step = _RechargeStep.success);
  }

  void _handleRazorpayFailure(PaymentFailureResponse response) {
    if (!mounted) return;
    final message = response.message?.trim();
    _goToFailed(
      message == null || message.isEmpty
          ? 'Payment cancelled or failed.'
          : message,
    );
  }

  void _goToFailed(String message) {
    if (!mounted) return;
    setState(() {
      _failureMessage = message;
      _step = _RechargeStep.failed;
    });
  }

  void _retry() {
    setState(() => _step = _RechargeStep.amount);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        decoration: const BoxDecoration(
          color: kWhite,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: kCardBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: switch (_step) {
                _RechargeStep.amount => _AmountStep(
                  key: const ValueKey('amount'),
                  usesRazorpay: _usesRazorpay,
                  amountController: _amountController,
                  selectedAmount: _selectedAmount,
                  presetAmounts: _presetAmounts,
                  onPresetSelected: (amount) {
                    setState(() {
                      _selectedAmount = amount;
                      _amountController.text = amount.toStringAsFixed(0);
                    });
                  },
                  onAmountChanged: (_) =>
                      setState(() => _selectedAmount = null),
                  onSubmit: _submitRecharge,
                ),
                _RechargeStep.processing => _ProcessingStep(
                  key: const ValueKey('processing'),
                  label: _processingLabel,
                ),
                _RechargeStep.success => _ResultStep(
                  key: const ValueKey('success'),
                  isSuccess: true,
                  title: '${formatRupee(_confirmedAmount)} Added!',
                  message: 'Your wallet balance has been updated.',
                  primaryLabel: 'Done',
                  onPrimary: () => Navigator.of(context).pop(),
                ),
                _RechargeStep.failed => _ResultStep(
                  key: const ValueKey('failed'),
                  isSuccess: false,
                  title: 'Payment Failed',
                  message: _failureMessage,
                  primaryLabel: 'Try Again',
                  onPrimary: _retry,
                  onCancel: () => Navigator.of(context).pop(),
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AmountStep extends StatelessWidget {
  const _AmountStep({
    super.key,
    required this.usesRazorpay,
    required this.amountController,
    required this.selectedAmount,
    required this.presetAmounts,
    required this.onPresetSelected,
    required this.onAmountChanged,
    required this.onSubmit,
  });

  final bool usesRazorpay;
  final TextEditingController amountController;
  final double? selectedAmount;
  final List<double> presetAmounts;
  final ValueChanged<double> onPresetSelected;
  final ValueChanged<String> onAmountChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Add Balance', style: kStyle(kSemiBold, kSize20, color: kTextColor)),
        const SizedBox(height: 6),
        Text(
          usesRazorpay
              ? 'Add money securely via UPI, cards, netbanking & more.'
              : 'Razorpay is not configured. This recharge credits your wallet instantly.',
          style: kCaption13R.copyWith(color: kMutedText, height: 1.35),
        ),
        const SizedBox(height: 20),
        Text('Enter Amount', style: kWalletSectionTitleSB),
        const SizedBox(height: 10),
        _AmountField(controller: amountController, onChanged: onAmountChanged),
        const SizedBox(height: 12),
        _PresetAmountChips(
          amounts: presetAmounts,
          selectedAmount: selectedAmount,
          onSelected: onPresetSelected,
        ),
        const SizedBox(height: 18),
        if (usesRazorpay) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: kChipGreyBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  height: 28,
                  width: 28,
                  decoration: const BoxDecoration(
                    color: kActiveGreenBg,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.verified_rounded,
                    size: 14,
                    color: kActiveGreen,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Secured by Razorpay — UPI, cards, netbanking & more',
                    style: kCaption12R.copyWith(
                      color: kSecondaryTextColor,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
        ],
        primaryButton(
          label: usesRazorpay ? 'Add Money' : 'Recharge Wallet',
          buttonColor: kBrandBlue,
          icon: const Icon(
            Icons.account_balance_wallet_outlined,
            color: kWhite,
            size: 18,
          ),
          onPressed: onSubmit,
        ),
      ],
    );
  }
}

class _AmountField extends StatelessWidget {
  const _AmountField({required this.controller, this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kWhite,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: kCardBorder.withValues(alpha: 0.45)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(
            '₹',
            style: kStyle(kSemiBold, kSize18, color: kBrandBlue, height: 1),
          ),
          Container(
            height: 22,
            width: 1,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            color: kCardBorder,
          ),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: kStyle(kMedium, kSize16, color: kTextColor, height: 1.2),
              decoration: InputDecoration(
                hintText: 'Enter Amount',
                hintStyle: kCaption14R.copyWith(color: kMutedText),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetAmountChips extends StatelessWidget {
  const _PresetAmountChips({
    required this.amounts,
    required this.selectedAmount,
    required this.onSelected,
  });

  final List<double> amounts;
  final double? selectedAmount;
  final ValueChanged<double> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: amounts.map((amount) {
        final isSelected = selectedAmount == amount;
        return GestureDetector(
          onTap: () => onSelected(amount),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: kWhite,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isSelected ? kBrandBlue : kCardBorder),
            ),
            child: Text(
              formatRupee(amount),
              style: kStyle(
                isSelected ? kSemiBold : kMedium,
                kSize13,
                color: kTextColor,
                height: 1.1,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ProcessingStep extends StatelessWidget {
  const _ProcessingStep({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            height: 72,
            width: 72,
            child: CircularProgressIndicator(
              strokeWidth: 6,
              backgroundColor: kChipGreyBg,
              color: kBrandBlue,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            label,
            style: kStyle(kSemiBold, kSize18, color: kTextColor, height: 1.2),
          ),
          const SizedBox(height: 6),
          Text(
            'Please wait, do not close this screen',
            style: kCaption13R.copyWith(color: kMutedText),
          ),
        ],
      ),
    );
  }
}

class _ResultStep extends StatelessWidget {
  const _ResultStep({
    super.key,
    required this.isSuccess,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    this.onCancel,
  });

  final bool isSuccess;
  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Center(
          child: Container(
            height: 88,
            width: 88,
            decoration: BoxDecoration(
              color: isSuccess ? kActiveGreen : kSosRed,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isSuccess ? Icons.check_rounded : Icons.close_rounded,
              color: kWhite,
              size: 48,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          title,
          textAlign: TextAlign.center,
          style: kStyle(kSemiBold, kSize20, color: kTextColor, height: 1.25),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: kCaption14R.copyWith(color: kSecondaryTextColor, height: 1.4),
        ),
        const SizedBox(height: 22),
        primaryButton(
          label: primaryLabel,
          buttonColor: isSuccess ? kActiveGreen : kBrandBlue,
          onPressed: onPrimary,
        ),
        if (onCancel != null) ...[
          const SizedBox(height: 4),
          TextButton(
            onPressed: onCancel,
            child: Text(
              'Cancel',
              style: kStyle(kMedium, kSize15, color: kMutedText),
            ),
          ),
        ],
      ],
    );
  }
}
