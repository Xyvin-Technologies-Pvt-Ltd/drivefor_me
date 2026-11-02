import 'package:DriveForme/src/data/apis/trip_api.dart';
import 'package:DriveForme/src/data/constants/app_colors.dart';
import 'package:DriveForme/src/data/constants/colour_constants.dart';
import 'package:DriveForme/src/data/constants/style_constants.dart';
import 'package:DriveForme/src/data/models/trip_model.dart';
import 'package:DriveForme/src/data/services/navigation_services.dart';
import 'package:DriveForme/src/data/utils/trip_lifecycle.dart';
import 'package:DriveForme/src/data/utils/trip_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TripsPage extends ConsumerStatefulWidget {
  const TripsPage({super.key});

  @override
  ConsumerState<TripsPage> createState() => _TripsPageState();
}

class _TripsPageState extends ConsumerState<TripsPage> {
  static const _tabs = ['Ongoing', 'Upcoming', 'Completed', 'Cancelled'];
  int _selectedTab = 0;
  List<TripModel> _trips = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

  Future<void> _loadTrips() async {
    final requestedTab = _selectedTab;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final api = ref.read(tripApiProvider);
    final response = switch (requestedTab) {
      0 => await api.listOngoingTrips(),
      1 => await api.listUpcomingTrips(),
      2 => await api.listCompletedTrips(),
      3 => await api.listCancelledTrips(),
      _ => await api.listOngoingTrips(),
    };

    if (!mounted) return;
    // Ignore stale responses after the user switched tabs.
    if (requestedTab != _selectedTab) return;

    setState(() {
      _isLoading = false;
      if (!response.success || response.data == null) {
        _trips = [];
        _errorMessage = response.message ?? 'Failed to load trips.';
        return;
      }
      final trips = response.data!;
      // Defense-in-depth: never mix cancelled trips into Upcoming/Ongoing.
      _trips = switch (requestedTab) {
        0 => trips.where((t) => t.isActiveBooking).toList(),
        1 => trips
            .where((t) => !t.isCancelled && !t.isCompleted && !t.isInProgress)
            .toList(),
        2 => trips.where((t) => t.isCompleted).toList(),
        3 => trips.where((t) => t.isCancelled).toList(),
        _ => trips,
      };
    });
  }

  void _onTabSelected(int index) {
    if (_selectedTab == index) return;
    setState(() => _selectedTab = index);
    _loadTrips();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: kTripsScreenBg,
      body: Column(
        children: [
          ColoredBox(
            color: kBrandBlue,
            child: SizedBox(height: topInset),
          ),
          _TripsTabBar(
            tabs: _tabs,
            selectedIndex: _selectedTab,
            onSelected: _onTabSelected,
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadTrips,
              color: kBrandBlue,
              child: _buildTabBody(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBody(BuildContext context) {
    if (_isLoading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator(color: kBrandBlue)),
        ],
      );
    }

    if (_errorMessage != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: kScreenPaddingH),
        children: [
          const SizedBox(height: 80),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: kEmptyStateM,
          ),
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: _loadTrips,
              child: const Text('Retry'),
            ),
          ),
        ],
      );
    }

    if (_trips.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [_EmptyTripsMessage(tab: _tabs[_selectedTab])],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        kScreenPaddingH,
        16,
        kScreenPaddingH,
        _navBarClearance(context),
      ),
      itemCount: _trips.length,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final trip = _trips[index];
        return switch (_selectedTab) {
          0 => _OngoingTripCard(trip: trip),
          1 => _UpcomingTripCard(trip: trip),
          2 => _CompletedTripCard(
            trip: trip,
            onViewDetails: () {
              NavigationService().pushNamed(
                'completed_trip_details',
                arguments: trip.toCompletedDetailsArguments(),
              );
            },
          ),
          3 => _CancelledTripCard(
            trip: trip,
            onViewDetails: () {
              NavigationService().pushNamed(
                'cancelled_trip_details',
                arguments: trip.toCancelledDetailsArguments(),
              );
            },
            onBookAgain: () {
              navigateToCreateTripIfAllowed(
                context: context,
                ref: ref,
              );
            },
          ),
          _ => const SizedBox.shrink(),
        };
      },
    );
  }

  double _navBarClearance(BuildContext context) =>
      68 + 26 + MediaQuery.paddingOf(context).bottom + 16;
}

class _TripsTabBar extends StatelessWidget {
  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _TripsTabBar({
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: kWhite,
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: List.generate(tabs.length, (i) {
          return Expanded(
            child: _TabItem(
              label: tabs[i],
              selected: i == selectedIndex,
              onTap: () => onSelected(i),
            ),
          );
        }),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 14),
          Text(label, style: selected ? kTabLabelM : kTabLabelR),
          const SizedBox(height: 14),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 2,
            width: selected ? 52 : 0,
            decoration: BoxDecoration(
              color: kTabActiveTan,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ],
      ),
    );
  }
}

class _OngoingTripCard extends StatelessWidget {
  final TripModel trip;

  const _OngoingTripCard({required this.trip});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kWhite,
        borderRadius: BorderRadius.circular(kCardRadiusMd),
        boxShadow: [
          BoxShadow(
            color: kBlack.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StatusChip(
                background: kActiveGreenBg,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: kActiveGreen,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('Active Trip', style: kTripBadgeSB),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusChip(
                background: kChipGreyBg,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      trip.isOneWay
                          ? Icons.arrow_right_alt_rounded
                          : Icons.autorenew_rounded,
                      size: 18,
                      color: kBlack.withValues(alpha: 0.65),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      trip.directionChipLabel,
                      style: kTripChipR.copyWith(
                        color: kBlack.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
              // const Spacer(),
              // Icon(
              //   Icons.more_horiz_rounded,
              //   size: 26,
              //   color: kBlack.withValues(alpha: 0.85),
              // ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _RouteStops(
                  pickup: trip.pickupAddress,
                  dropoff: trip.dropoffAddress ?? trip.pickupAddress,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(trip.displayPrice, style: kLabel22B),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const _DashedDivider(),
          const SizedBox(height: 16),
          if (trip.estimatedDurationLabel != null &&
              trip.estimatedDurationLabel!.isNotEmpty) ...[
            Row(
              children: [
                Icon(
                  Icons.access_time_rounded,
                  size: 18,
                  color: kBlack.withValues(alpha: 0.45),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    trip.estimatedDurationLabel!,
                    style: kCaption13R.copyWith(height: 1.3),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.calendar_month_outlined,
                size: 18,
                color: kBlack.withValues(alpha: 0.45),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  trip.formatScheduleLine(trip.startedAt ?? trip.pickupAt),
                  style: kCaption12R.copyWith(height: 1.35),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: _TrackTripButton(
              label: trip.isInProgress ? 'Track Trip' : 'View trip',
              onPressed: () {
                final target = tripNavigationTarget(trip);
                if (target == null) return;
                NavigationService().pushNamed(
                  target.route,
                  arguments: target.arguments,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CancelledTripCard extends StatelessWidget {
  final TripModel trip;
  final VoidCallback onViewDetails;
  final VoidCallback onBookAgain;

  const _CancelledTripCard({
    required this.trip,
    required this.onViewDetails,
    required this.onBookAgain,
  });

  static const _cancelledBg = AppColors.cancelledBackground;
  static const _cancelledRed = AppColors.errorRedAlt;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kWhite,
        borderRadius: BorderRadius.circular(kCardRadiusMd),
        boxShadow: [
          BoxShadow(
            color: kBlack.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StatusChip(
                background: _cancelledBg,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        color: _cancelledRed,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, size: 11, color: kWhite),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Cancelled',
                      style: kStyle(kSemiBold, kSize13, color: _cancelledRed),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusChip(
                background: kChipGreyBg,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 18,
                      color: kBlack.withValues(alpha: 0.65),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      trip.tripTypeChipLabel,
                      style: kTripChipR.copyWith(
                        color: kBlack.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
              // const Spacer(),
              // Icon(
              //   Icons.more_horiz_rounded,
              //   size: 26,
              //   color: kBlack.withValues(alpha: 0.85),
              // ),
            ],
          ),
          const SizedBox(height: 20),
          _RouteStops(
            pickup: trip.pickupAddress,
            dropoff: trip.dropoffAddress ?? trip.pickupAddress,
          ),
          const SizedBox(height: 18),
          const _DashedDivider(),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(
                Icons.calendar_month_outlined,
                size: 18,
                color: kBlack.withValues(alpha: 0.45),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: kCaption13R.copyWith(height: 1.35),
                    children: [
                      TextSpan(
                        text: trip.formatMetaPrimary(trip.referenceDate),
                        style: kCaption13SB,
                      ),
                      TextSpan(text: trip.metaRest),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _OutlinedTripAction(
                  label: 'View Details',
                  onTap: onViewDetails,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _OutlinedTripAction(
                  label: 'Book again',
                  onTap: onBookAgain,
                  borderColor: kRed,
                  labelColor: kRed,
                  leadingIcon: Icons.refresh_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompletedTripCard extends StatelessWidget {
  final TripModel trip;
  final VoidCallback onViewDetails;

  const _CompletedTripCard({required this.trip, required this.onViewDetails});

  static const _completedBg = AppColors.completedBackground;
  static const _completedBlue = AppColors.primaryBlue;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kWhite,
        borderRadius: BorderRadius.circular(kCardRadiusMd),
        boxShadow: [
          BoxShadow(
            color: kBlack.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StatusChip(
                background: _completedBg,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        color: _completedBlue,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check, size: 11, color: kWhite),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Completed',
                      style: kStyle(kSemiBold, kSize13, color: _completedBlue),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusChip(
                background: kChipGreyBg,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 18,
                      color: kBlack.withValues(alpha: 0.65),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      trip.tripTypeChipLabel,
                      style: kTripChipR.copyWith(
                        color: kBlack.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
              // const Spacer(),
              // Icon(
              //   Icons.more_horiz_rounded,
              //   size: 26,
              //   color: kBlack.withValues(alpha: 0.85),
              // ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _RouteStops(
                  pickup: trip.pickupAddress,
                  dropoff: trip.dropoffAddress ?? trip.pickupAddress,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(trip.displayPrice, style: kLabel22B),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const _DashedDivider(),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(
                Icons.calendar_month_outlined,
                size: 18,
                color: kBlack.withValues(alpha: 0.45),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: kCaption13R.copyWith(height: 1.35),
                    children: [
                      TextSpan(
                        text: trip.formatMetaPrimary(trip.referenceDate),
                        style: kCaption13SB,
                      ),
                      TextSpan(text: trip.metaRest),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _OutlinedTripAction(
                  label: 'View Details',
                  onTap: onViewDetails,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _OutlinedTripAction(
                  label: 'Download Invoice',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Invoice download coming soon.'),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OutlinedTripAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color borderColor;
  final Color labelColor;
  final IconData? leadingIcon;

  const _OutlinedTripAction({
    required this.label,
    required this.onTap,
    this.borderColor = kTripBorder,
    this.labelColor = kTextColor,
    this.leadingIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kWhite,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (leadingIcon != null) ...[
                Icon(leadingIcon, size: 18, color: labelColor),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: kLabel15M.copyWith(
                    color: labelColor.withValues(alpha: 0.9),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpcomingTripCard extends StatelessWidget {
  final TripModel trip;

  const _UpcomingTripCard({required this.trip});

  static const _scheduledBg = AppColors.warningBackground;
  static const _scheduledOrange = AppColors.warningOrange;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kWhite,
        borderRadius: BorderRadius.circular(kCardRadiusMd),
        boxShadow: [
          BoxShadow(
            color: kBlack.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StatusChip(
                background: _scheduledBg,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: _scheduledOrange,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      trip.upcomingStatusLabel(),
                      style: kStyle(
                        kSemiBold,
                        kSize13,
                        color: _scheduledOrange,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusChip(
                background: kChipGreyBg,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      trip.isOneWay
                          ? Icons.arrow_right_alt_rounded
                          : Icons.autorenew_rounded,
                      size: 18,
                      color: kBlack.withValues(alpha: 0.65),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      trip.directionChipLabel,
                      style: kTripChipR.copyWith(
                        color: kBlack.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
              // const Spacer(),
              // Icon(
              //   Icons.more_horiz_rounded,
              //   size: 26,
              //   color: kBlack.withValues(alpha: 0.85),
              // ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _RouteStops(
                  pickup: trip.pickupAddress,
                  dropoff: trip.dropoffAddress ?? trip.pickupAddress,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(trip.displayPrice, style: kLabel22B),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const _DashedDivider(),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(
                Icons.calendar_month_outlined,
                size: 18,
                color: kBlack.withValues(alpha: 0.45),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  trip.formatScheduleLine(trip.pickupAt),
                  style: kCaption13R.copyWith(height: 1.35),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (trip.hasDriver)
                Expanded(
                  child: _DriverProfilePill(
                    driverName: trip.driverName!,
                    driverRating: trip.driverRating ?? 5.0,
                    driverPhotoUrl: trip.driverPhotoUrl,
                  ),
                )
              else
                Expanded(
                  child: Text(
                    'Driver will be assigned soon',
                    style: kCaption13R.copyWith(
                      color: kBlack.withValues(alpha: 0.55),
                    ),
                  ),
                ),
              const SizedBox(width: 10),
              _ViewBookingsButton(
                onPressed: () {
                  NavigationService().pushNamed(
                    'scheduled_trip_details',
                    arguments: trip.toScheduledDetailsArguments(),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DriverProfilePill extends StatelessWidget {
  final String driverName;
  final double driverRating;
  final String? driverPhotoUrl;

  const _DriverProfilePill({
    required this.driverName,
    required this.driverRating,
    this.driverPhotoUrl,
  });

  @override
  Widget build(BuildContext context) {
    final photoUrl = driverPhotoUrl?.trim();
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: kTripCreamBg,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: [
          ClipOval(
            child: hasPhoto
                ? Image.network(
                    photoUrl,
                    width: 32,
                    height: 32,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        _driverAvatarFallback(),
                  )
                : _driverAvatarFallback(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              driverName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: kLabel15M.copyWith(
                color: kTextColor.withValues(alpha: 0.9),
              ),
            ),
          ),
          const Icon(Icons.star_rounded, size: 16, color: kGoldAccent),
          const SizedBox(width: 2),
          Text(driverRating.toStringAsFixed(1), style: kCaption13SB),
          Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: kBlack.withValues(alpha: 0.45),
          ),
        ],
      ),
    );
  }

  Widget _driverAvatarFallback() {
    return Container(
      width: 32,
      height: 32,
      color: kTripDestIconBg,
      child: const Icon(Icons.person, size: 18, color: kTripIconMuted),
    );
  }
}

class _ViewBookingsButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _ViewBookingsButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kBrandBlue,
        borderRadius: BorderRadius.circular(6),
      ),
      child: GestureDetector(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Text('View Bookings', style: kTrackTripSB),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final Color background;
  final Widget child;

  const _StatusChip({required this.background, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(30),
      ),
      child: child,
    );
  }
}

class _RouteStops extends StatelessWidget {
  final String pickup;
  final String dropoff;

  const _RouteStops({required this.pickup, required this.dropoff});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RouteRow(
          icon: Icons.location_on_rounded,
          iconColor: kActiveGreen,
          label: pickup,
        ),
        Padding(
          padding: const EdgeInsets.only(left: 10),
          child: Container(
            width: 1.5,
            height: 22,
            margin: const EdgeInsets.symmetric(vertical: 2),
            color: kLineGrey,
          ),
        ),
        _RouteRow(
          icon: Icons.location_on_rounded,
          iconColor: kDropBlue,
          label: dropoff,
        ),
      ],
    );
  }
}

class _RouteRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;

  const _RouteRow({
    required this.icon,
    required this.iconColor,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: iconColor, size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              label,
              style: kLabel15M.copyWith(
                color: kTextColor.withValues(alpha: 0.9),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(double.infinity, 1),
      painter: _DashedLinePainter(color: kLineGrey),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  final Color color;

  _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const dashWidth = 5.0;
    const dashSpace = 4.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    double startX = 0;
    while (startX < size.width) {
      canvas.drawLine(Offset(startX, 0), Offset(startX + dashWidth, 0), paint);
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _EmptyTripsMessage extends StatelessWidget {
  final String tab;

  const _EmptyTripsMessage({required this.tab});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: Center(child: Text('No $tab trips', style: kEmptyStateM)),
    );
  }
}

class _TrackTripButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _TrackTripButton({this.label = 'Track Trip', required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kBrandBlue,
      borderRadius: BorderRadius.circular(kPillRadius),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(kPillRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text(label, style: kTrackTripSB),
        ),
      ),
    );
  }
}
