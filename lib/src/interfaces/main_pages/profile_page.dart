import 'package:DriveForme/src/data/constants/colour_constants.dart';
import 'package:DriveForme/src/data/constants/style_constants.dart';
import 'package:DriveForme/src/data/providers/notification_provider.dart';
import 'package:DriveForme/src/data/providers/user_provider.dart';
import 'package:DriveForme/src/data/services/auth_logout_service.dart';
import 'package:DriveForme/src/data/services/navigation_services.dart';
import 'package:DriveForme/src/data/services/snackbar_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';

/// Matches floating nav bar: bar (64) + circle lift (32) + safe inset.
double _navBarClearance(BuildContext context) =>
    64 + 32 + MediaQuery.paddingOf(context).bottom + 8;

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: kProfileScreenBg,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: _navBarClearance(context)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _ProfileHeaderSection(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: kScreenPaddingH),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: const [
                    SizedBox(height: 12),
                    _QuickActionsRow(),
                    SizedBox(height: 12),
                    _MainMenuCard(),
                    SizedBox(height: 12),
                    _PartnerMenuCard(),
                    SizedBox(height: 12),
                    _AccountMenuCard(),
                    SizedBox(height: 16),
                  ],
                ),
              ),
              Center(child: Text('v4.625.100005', style: kVersionR)),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileHeaderSection extends ConsumerWidget {
  const _ProfileHeaderSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(kScreenPaddingH, 12, kScreenPaddingH, 16),
      decoration: const BoxDecoration(
        color: kWhite,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(kCardRadiusLg),
          bottomRight: Radius.circular(kCardRadiusLg),
        ),
      ),
      child: const _ProfileHeaderCard(),
    );
  }
}

BoxDecoration _profileCardDecoration({double radius = kCardRadiusMd}) {
  return BoxDecoration(
    color: kWhite,
    borderRadius: BorderRadius.circular(radius),
    boxShadow: [
      BoxShadow(
        color: kBlack.withValues(alpha: 0.05),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ],
  );
}

BoxDecoration _profileQuickActionDecoration() =>
    _profileCardDecoration(radius: kCardRadiusSm);

class _ProfileHeaderCard extends ConsumerWidget {
  const _ProfileHeaderCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userProvider);

    return userAsync.when(
      loading: () =>
          _buildCard(displayName: 'Loading...', phone: '—', isLoading: true),
      error: (_, _) => _buildCard(
        displayName: 'Vehicle Owner',
        phone: '—',
        onRetry: () => ref.invalidate(userProvider),
      ),
      data: (user) {
        final name = user?.profile.fullName.trim();
        final displayName = name != null && name.isNotEmpty
            ? name
            : 'Vehicle Owner';
        final phone = user?.phoneNumber ?? '';
        return _buildCard(displayName: displayName, phone: phone);
      },
    );
  }

  Widget _buildCard({
    required String displayName,
    required String phone,
    bool isLoading = false,
    VoidCallback? onRetry,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 30,
            backgroundColor: kTertiary,
            backgroundImage: AssetImage('assets/pngs/profile.png'),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: isLoading
                ? Shimmer.fromColors(
                    baseColor: kShimmerBaseColor,
                    highlightColor: kWhite,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 18,
                          width: 140,
                          decoration: BoxDecoration(
                            color: kShimmerBaseColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 14,
                          width: 100,
                          decoration: BoxDecoration(
                            color: kShimmerBaseColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(displayName, style: kProfileNameB),
                      const SizedBox(height: 2),
                      Text(
                        phone.isNotEmpty ? phone : '—',
                        style: kProfilePhoneR,
                      ),
                      if (onRetry != null) ...[
                        const SizedBox(height: 6),
                        TextButton(
                          onPressed: onRetry,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            'Retry',
                            style: kEditProfileM.copyWith(fontSize: kSize12),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
          const SizedBox(width: 8),
          const _EditProfileButton(),
        ],
      ),
    );
  }
}

class _EditProfileButton extends StatelessWidget {
  const _EditProfileButton();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => NavigationService().pushNamed('personal_details'),
        borderRadius: BorderRadius.circular(50),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(50),
            border: Border.all(color: kBrandBlue, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Edit Profile', style: kEditProfileM),
              const SizedBox(width: 2),
              const Icon(Icons.chevron_right, size: 18, color: kBrandBlue),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickActionTile(
            label: 'Wallet',
            imagePath: 'assets/pngs/wallet_image.png',
            onTap: () => NavigationService().pushNamed('wallet'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickActionTile(
            label: 'Refer & Earn',
            imagePath: 'assets/pngs/refferandearn_image.png',
            onTap: () => NavigationService().pushNamed('refer_earn'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickActionTile(
            label: 'Help',
            imagePath: 'assets/pngs/Help_image.png',
            onTap: _openHelp,
          ),
        ),
      ],
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  final String label;
  final String imagePath;
  final VoidCallback? onTap;

  const _QuickActionTile({
    required this.label,
    required this.imagePath,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(kCardRadiusSm),
        child: Ink(
          decoration: _profileQuickActionDecoration(),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  imagePath,
                  width: 48,
                  height: 48,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: kQuickActionM,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void _openHelp() {
  NavigationService().pushNamed('support_call');
}

class _MainMenuCard extends ConsumerWidget {
  const _MainMenuCard();

  static const _items = [
    'Personal Details',
    'My Vehicles',
    'Notifications',
    'FAQ',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationCountProvider);

    return Container(
      decoration: _profileCardDecoration(),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < _items.length; i++)
            _MenuRow(
              title: _items[i],
              badgeCount: _items[i] == 'Notifications' ? unread : 0,
              onTap: switch (_items[i]) {
                'Personal Details' => () => NavigationService().pushNamed(
                  'personal_details',
                ),
                'My Vehicles' => () => NavigationService().pushNamed(
                  'my_vehicles',
                ),
                'Notifications' => () => NavigationService().pushNamed(
                  'notifications',
                ),
                _ => null,
              },
            ),
        ],
      ),
    );
  }
}

class _PartnerMenuCard extends StatelessWidget {
  const _PartnerMenuCard();

  static const _items = ['Join as Driver partner', 'B2B Enquiries'];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _profileCardDecoration(),
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('For Partners', style: kSectionLabelR),
          ),
          const SizedBox(height: 4),
          for (final title in _items) _MenuRow(title: title),
        ],
      ),
    );
  }
}

class _AccountMenuCard extends ConsumerWidget {
  const _AccountMenuCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: _profileCardDecoration(),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MenuRow(
            title: 'Logout',
            isDanger: true,
            onTap: () => _confirmLogout(context, ref),
          ),
          _MenuRow(
            title: 'Delete Account',
            isDanger: true,
            onTap: () => _showDeleteAccountDialog(context),
          ),
        ],
      ),
    );
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to sign in again to use the app.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _performLogout(context, ref);
            },
            child: const Text('Log out'),
          ),
        ],
      ),
    );
  }

  Future<void> _performLogout(BuildContext context, WidgetRef ref) async {
    final logoutService = ref.read(authLogoutServiceProvider);

    try {
      await logoutService.performLogout(ref);

      if (context.mounted) {
        NavigationService().pushNamedAndRemoveUntil('Phone');
      }
    } catch (e) {
      try {
        await logoutService.clearAllData(ref);
      } catch (_) {}

      if (context.mounted) {
        showAppSnackBar(context, 'Logout failed: $e');
        NavigationService().pushNamedAndRemoveUntil('Phone');
      }
    }
  }

  void _showDeleteAccountDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account'),
        content: const Text(
          'Account deletion is not available in the app yet. Please contact support for assistance.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final String title;
  final bool isDanger;
  final VoidCallback? onTap;
  final int badgeCount;

  const _MenuRow({
    required this.title,
    this.isDanger = false,
    this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: isDanger ? kMenuItemDangerM : kMenuItemM,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (badgeCount > 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: const BoxDecoration(
                    color: kRed,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    badgeCount > 9 ? '9+' : '$badgeCount',
                    style: kStyle(kSemiBold, kSize10, color: kWhite),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              const Icon(
                Icons.chevron_right_rounded,
                color: kChevronGrey,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
