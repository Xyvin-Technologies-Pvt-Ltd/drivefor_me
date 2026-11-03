import 'package:DriveForme/src/data/apis/wallet_api.dart';
import 'package:DriveForme/src/data/constants/colour_constants.dart';
import 'package:DriveForme/src/data/constants/style_constants.dart';
import 'package:DriveForme/src/data/models/wallet_model.dart';
import 'package:DriveForme/src/data/providers/wallet_provider.dart';
import 'package:DriveForme/src/interfaces/components/primaryButton.dart';
import 'package:DriveForme/src/data/services/snackbar_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ReferEarnPage extends ConsumerStatefulWidget {
  const ReferEarnPage({super.key});

  @override
  ConsumerState<ReferEarnPage> createState() => _ReferEarnPageState();
}

class _ReferEarnPageState extends ConsumerState<ReferEarnPage> {
  final _referralController = TextEditingController();
  bool _isApplyingReferral = false;

  @override
  void dispose() {
    _referralController.dispose();
    super.dispose();
  }

  Future<void> _applyReferral() async {
    final code = _referralController.text.trim();
    if (code.isEmpty) return;

    setState(() => _isApplyingReferral = true);
    final response = await ref.read(walletApiProvider).applyReferral(code);
    if (!mounted) return;
    setState(() => _isApplyingReferral = false);

    if (!response.success) {
      showAppSnackBar(context, response.message ?? 'Failed to apply code.');
      return;
    }

    ref.invalidate(walletProvider);
    _referralController.clear();
    if (mounted) Navigator.of(context).maybePop();
    showAppSnackBar(context, 'Referral code applied successfully.');
  }

  void _copyReferralCode(String code) {
    if (code.isEmpty) return;
    Clipboard.setData(ClipboardData(text: code));
    showAppSnackBar(context, 'Referral code copied.');
  }

  void _shareReferralCode(String code) {
    if (code.isEmpty) return;
    final message =
        'Join DriveFORme! Use my referral code $code and earn ₹100 for every successful vehicle owner referral.';
    Clipboard.setData(ClipboardData(text: message));
    showAppSnackBar(context, 'Invite message copied. Share with friends!');
  }

  void _showReferralHelp() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            kReferEarnPaddingH,
            20,
            kReferEarnPaddingH,
            MediaQuery.paddingOf(context).bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('How it works', style: kReferEarnAppBarSB),
              const SizedBox(height: 10),
              Text(
                'Earn ₹100 for every successful vehicle owner referral. '
                'Share your referral code with friends. When they sign up and '
                'complete their first trip, you earn the reward.',
                style: kReferBannerSubtitleR,
              ),
              const SizedBox(height: 20),
              Text('Have a referral code?', style: kReferCodeLabelR),
              const SizedBox(height: 8),
              TextField(
                controller: _referralController,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: 'Enter referral code',
                  hintStyle: kCaption13R,
                  filled: true,
                  fillColor: kReferCodeFieldBg,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: kReferBannerBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: kReferBannerBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: kBrandBlue, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              primaryButton(
                label: _isApplyingReferral ? 'Applying...' : 'Apply Code',
                onPressed: _isApplyingReferral ? null : _applyReferral,
                buttonColor: kBrandBlue,
                buttonHeight: 48,
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatReferralCode(String code) {
    if (code.isEmpty) return '—';
    return code.toUpperCase().split('').join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final walletAsync = ref.watch(walletProvider);

    return Scaffold(
      backgroundColor: kWhite,
      appBar: _ReferEarnAppBar(onHelp: _showReferralHelp),
      body: walletAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => ref.invalidate(walletProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (wallet) => _ReferEarnBody(
          wallet: wallet,
          formattedCode: _formatReferralCode(wallet.referralCode),
          onRefresh: () async => ref.invalidate(walletProvider),
          onCopy: () => _copyReferralCode(wallet.referralCode),
          onShare: () => _shareReferralCode(wallet.referralCode),
          onInvite: () => _shareReferralCode(wallet.referralCode),
        ),
      ),
    );
  }
}

class _ReferEarnAppBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback onHelp;

  const _ReferEarnAppBar({required this.onHelp});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: kWhite,
      surfaceTintColor: kWhite,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: 4,
      leadingWidth: 60,
      leading: Padding(
        padding: const EdgeInsets.only(left: kReferEarnPaddingH - 8),
        child: Center(
          child: _RoundIconButton(
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
      ),
      title: Text('Refer & Earn', style: kReferEarnAppBarSB),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: kReferEarnPaddingH),
          child: Center(child: _HelpOutlineButton(onTap: onHelp)),
        ),
      ],
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _RoundIconButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kReferBackBtnBg,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: const SizedBox(
          width: 40,
          height: 40,
          child: Icon(Icons.chevron_left_rounded, size: 26, color: kTextColor),
        ),
      ),
    );
  }
}

class _HelpOutlineButton extends StatelessWidget {
  final VoidCallback onTap;

  const _HelpOutlineButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: kBrandBlue, width: 1.5),
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.question_mark_rounded,
            size: 16,
            color: kBrandBlue,
          ),
        ),
      ),
    );
  }
}

class _ReferEarnBody extends StatelessWidget {
  final WalletModel wallet;
  final String formattedCode;
  final Future<void> Function() onRefresh;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onInvite;

  const _ReferEarnBody({
    required this.wallet,
    required this.formattedCode,
    required this.onRefresh,
    required this.onCopy,
    required this.onShare,
    required this.onInvite,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: onRefresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                kReferEarnPaddingH,
                12,
                kReferEarnPaddingH,
                16,
              ),
              children: [
                const _InviteEarnBanner(),
                const SizedBox(height: 16),
                _ReferralCodeCard(
                  formattedCode: formattedCode,
                  hasCode: wallet.referralCode.isNotEmpty,
                  onCopy: onCopy,
                  onShare: onShare,
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            kReferEarnPaddingH,
            0,
            kReferEarnPaddingH,
            bottomInset > 0 ? bottomInset + 12 : 24,
          ),
          child: _InviteButton(
            onPressed: wallet.referralCode.isEmpty ? null : onInvite,
          ),
        ),
      ],
    );
  }
}

class _InviteButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const _InviteButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: Material(
        color: enabled ? kBrandBlue : kBrandBlue.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(kPillRadius),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(kPillRadius),
          child: Center(child: Text('Invite', style: kReferInviteButtonM)),
        ),
      ),
    );
  }
}

class _InviteEarnBanner extends StatelessWidget {
  const _InviteEarnBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kReferBannerBg,
        borderRadius: BorderRadius.circular(kCardRadiusSm),
        border: Border.all(color: kReferBannerBorder, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 4, 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: kReferBannerTitleSB,
                      children: [
                        const TextSpan(text: 'Invite & '),
                        TextSpan(
                          text: 'Earn',
                          style: kReferBannerTitleAccentSB,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Earn ₹100 for every successful vehicle owner referral',
                    style: kReferBannerSubtitleR,
                  ),
                ],
              ),
            ),
            Image.asset(
              'assets/pngs/referandearnimg.png',
              width: 118,
              height: 104,
              fit: BoxFit.contain,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReferralCodeCard extends StatelessWidget {
  final String formattedCode;
  final bool hasCode;
  final VoidCallback onCopy;
  final VoidCallback onShare;

  const _ReferralCodeCard({
    required this.formattedCode,
    required this.hasCode,
    required this.onCopy,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 16),
      decoration: BoxDecoration(
        color: kWhite,
        borderRadius: BorderRadius.circular(kCardRadiusSm),
        boxShadow: [
          BoxShadow(
            color: kBlack.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Referral Code', style: kReferCodeLabelR),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _DashedCodeField(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 13, 10, 13),
                    child: Row(
                      children: [
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              formattedCode,
                              style: kReferCodeValueM,
                              maxLines: 1,
                            ),
                          ),
                        ),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: hasCode ? onCopy : null,
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Icon(
                                Icons.copy_all_rounded,
                                size: 20,
                                color: hasCode
                                    ? kReferDashedBorder
                                    : kReferDashedBorder.withValues(
                                        alpha: 0.35,
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: hasCode ? onShare : null,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.send_rounded,
                      size: 26,
                      color: hasCode
                          ? kBrandBlue
                          : kBrandBlue.withValues(alpha: 0.35),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DashedCodeField extends StatelessWidget {
  final Widget child;

  const _DashedCodeField({required this.child});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _DashedBorderPainter(
        color: kReferDashedBorder,
        radius: kPillRadius,
        strokeWidth: 1.4,
        dashWidth: 6,
        dashGap: 4,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: kReferCodeFieldBg,
          borderRadius: BorderRadius.circular(kPillRadius),
        ),
        child: child,
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double strokeWidth;
  final double dashWidth;
  final double dashGap;

  const _DashedBorderPainter({
    required this.color,
    required this.radius,
    required this.strokeWidth,
    required this.dashWidth,
    required this.dashGap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        strokeWidth / 2,
        strokeWidth / 2,
        size.width - strokeWidth,
        size.height - strokeWidth,
      ),
      Radius.circular(radius),
    );

    final path = Path()..addRRect(rect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        final extractPath = metric.extractPath(
          distance,
          next > metric.length ? metric.length : next,
        );
        canvas.drawPath(extractPath, paint);
        distance += dashWidth + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.radius != radius ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
