import 'package:DriveForme/src/data/services/notification_token_service.dart';
import 'package:DriveForme/src/data/constants/colour_constants.dart';
import 'package:DriveForme/src/data/constants/style_constants.dart';
import 'package:DriveForme/src/data/providers/live_driver_location_provider.dart';
import 'package:DriveForme/src/data/providers/nav_provider.dart';
import 'package:DriveForme/src/data/services/active_trip_service.dart';
import 'package:DriveForme/src/data/services/haptic_helper.dart';
import 'package:DriveForme/src/data/services/navigation_services.dart';
import 'package:DriveForme/src/interfaces/main_pages/home_page.dart';
import 'package:DriveForme/src/interfaces/main_pages/profile_page.dart';
import 'package:DriveForme/src/interfaces/main_pages/trip_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

class _NavItem {
  final String label;
  final String inactiveIcon;
  final String activeGif;

  const _NavItem({
    required this.label,
    required this.inactiveIcon,
    required this.activeGif,
  });
}

const _navItems = [
  _NavItem(
    label: 'Home',
    inactiveIcon: 'assets/svg/inactive_home.svg',
    activeGif: 'assets/gifs/home_icon.gif',
  ),
  _NavItem(
    label: 'Trips',
    inactiveIcon: 'assets/svg/inactive_trip.svg',
    activeGif: 'assets/gifs/trips.gif',
  ),
  _NavItem(
    label: 'Profile',
    inactiveIcon: 'assets/svg/inactive_profile.svg',
    activeGif: 'assets/gifs/profile.gif',
  ),
];

class NavBar extends ConsumerStatefulWidget {
  const NavBar({super.key});

  @override
  ConsumerState<NavBar> createState() => _NavBarState();
}

class _NavBarState extends ConsumerState<NavBar> {
  final List<Widget> _pages = const [HomePage(), TripsPage(), ProfilePage()];
  bool _checkedActiveTrip = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final push = ref.read(pushNotificationServiceProvider);
      try {
        await ref
            .read(notificationTokenServiceProvider)
            .registerTokenIfAvailable();
        if (mounted) await push.openPendingSupportChat();
      } catch (_) {
        // Support remains available in-app if push services are unavailable.
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(liveTripTrackingProvider);
      _resumeActiveTrip();
    });
  }

  Future<void> _resumeActiveTrip() async {
    if (_checkedActiveTrip) return;
    _checkedActiveTrip = true;

    final target = await ref
        .read(activeTripServiceProvider)
        .resolveResumableTrip();
    if (!mounted || target == null) return;

    NavigationService().pushNamed(target.route, arguments: target.arguments);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(liveTripTrackingProvider);
    final selectedIndex = ref.watch(selectedIndexProvider);

    return PopScope(
      canPop: selectedIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && selectedIndex != 0) {
          ref.read(selectedIndexProvider.notifier).updateIndex(0);
        }
      },
      child: Scaffold(
        backgroundColor: kScreenBg,
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: KeyedSubtree(
            key: ValueKey(selectedIndex),
            child: _pages[selectedIndex],
          ),
        ),
        bottomNavigationBar: _FloatingNavBar(
          selectedIndex: selectedIndex,
          onTap: (i) {
            if (i != selectedIndex) {
              HapticHelper.impact(HapticImpact.light);
              ref.read(selectedIndexProvider.notifier).updateIndex(i);
            }
          },
        ),
      ),
    );
  }
}

class _FloatingNavBar extends StatelessWidget {
  final int selectedIndex;
  final void Function(int) onTap;

  const _FloatingNavBar({required this.selectedIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const double barHeight = 64;
    const double circleDiameter = 64;
    const double circleRadius = circleDiameter / 2;
    const double circleLift = 32;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return SizedBox(
      height: barHeight + circleLift + bottomInset,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: CustomPaint(
              painter: _NotchBarPainter(
                selectedIndex: selectedIndex,
                itemCount: _navItems.length,
                notchRadius: circleRadius + 8,
                bottomPadding: bottomInset,
              ),
              child: SizedBox(height: barHeight + bottomInset),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomInset,
            height: barHeight,
            child: Row(
              children: List.generate(_navItems.length, (i) {
                final item = _navItems[i];
                final isSelected = i == selectedIndex;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => onTap(i),
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (!isSelected) ...[
                          const SizedBox(height: 10),
                          SvgPicture.asset(
                            item.inactiveIcon,
                            width: 22,
                            height: 22,
                          ),
                          const SizedBox(height: 4),
                          Text(item.label, style: kNavLabelR),
                        ] else
                          Text(item.label, style: kNavLabelM),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.fastOutSlowIn,
            bottom: bottomInset + barHeight - circleRadius - 4,
            left: _circleLeft(context, selectedIndex, circleRadius),
            child: GestureDetector(
              onTap: () => onTap(selectedIndex),
              child: _ActiveCircle(
                diameter: circleDiameter,
                gif: _navItems[selectedIndex].activeGif,
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _circleLeft(BuildContext context, int index, double radius) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final itemWidth = screenWidth / _navItems.length;
    return itemWidth * index + itemWidth / 2 - radius;
  }
}

class _NavGifIcon extends StatelessWidget {
  final String asset;
  final double size;

  const _NavGifIcon({required this.asset, required this.size});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
    );
  }
}

class _ActiveCircle extends StatelessWidget {
  final double diameter;
  final String gif;

  const _ActiveCircle({required this.diameter, required this.gif});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: kBrandBlue,
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowLight,
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: _NavGifIcon(asset: gif, size: 28),
    );
  }
}

class _NotchBarPainter extends CustomPainter {
  final int selectedIndex;
  final int itemCount;
  final double notchRadius;
  final double bottomPadding;

  const _NotchBarPainter({
    required this.selectedIndex,
    required this.itemCount,
    required this.notchRadius,
    required this.bottomPadding,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = kWhite
      ..style = PaintingStyle.fill;

    final path = Path();

    final itemWidth = size.width / itemCount;
    final centerX = itemWidth * selectedIndex + itemWidth / 2;

    const cornerRadius = 28.0;
    final notchWidth = notchRadius * 1.75;
    const notchDepth = 42.0;

    final notchStart = (centerX - notchWidth < cornerRadius)
        ? cornerRadius
        : centerX - notchWidth;
    final notchEnd = (centerX + notchWidth > size.width - cornerRadius)
        ? size.width - cornerRadius
        : centerX + notchWidth;

    path.moveTo(0, cornerRadius);
    path.quadraticBezierTo(0, 0, cornerRadius, 0);

    // LEFT SIDE BEFORE NOTCH
    if (notchStart > cornerRadius) {
      path.lineTo(notchStart, 0);
    }

    // LEFT CURVE DOWN
    path.cubicTo(
      notchStart + (centerX - notchStart) * 0.4,
      0,
      notchStart + (centerX - notchStart) * 0.6,
      notchDepth,
      centerX,
      notchDepth,
    );

    // RIGHT CURVE UP
    path.cubicTo(
      notchEnd - (notchEnd - centerX) * 0.6,
      notchDepth,
      notchEnd - (notchEnd - centerX) * 0.4,
      0,
      notchEnd,
      0,
    );

    // TOP RIGHT
    if (notchEnd < size.width - cornerRadius) {
      path.lineTo(size.width - cornerRadius, 0);
    }

    path.quadraticBezierTo(size.width, 0, size.width, cornerRadius);

    // RIGHT SIDE
    path.lineTo(size.width, size.height);

    // BOTTOM
    path.lineTo(0, size.height);

    path.close();

    canvas.drawShadow(path, AppColors.shadowMedium, 12, false);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _NotchBarPainter oldDelegate) {
    return oldDelegate.selectedIndex != selectedIndex;
  }
}
