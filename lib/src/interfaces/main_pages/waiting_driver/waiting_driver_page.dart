import 'dart:async';

import 'package:DriveForme/src/data/constants/colour_constants.dart';
import 'package:DriveForme/src/data/constants/style_constants.dart';
import 'package:DriveForme/src/data/models/trip_location_model.dart';
import 'package:DriveForme/src/data/models/trip_model.dart';
import 'package:DriveForme/src/data/providers/active_trip_provider.dart';
import 'package:DriveForme/src/data/services/navigation_services.dart';
import 'package:DriveForme/src/data/services/trip_socket_service.dart';
import 'package:DriveForme/src/data/utils/trip_lifecycle.dart';
import 'package:DriveForme/src/data/utils/trip_screen_helpers.dart';
import 'package:DriveForme/src/interfaces/components/trip_map_view.dart';
import 'package:DriveForme/src/interfaces/components/primaryButton.dart';
import 'package:DriveForme/src/interfaces/components/trip_route_summary_card.dart';
import 'package:DriveForme/src/data/services/snackbar_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum WaitingDriverStage {
  matchingNearby,
  expandingSearch,
  bestDriverMatch,
}

extension WaitingDriverStageX on WaitingDriverStage {
  double get progress {
    switch (this) {
      case WaitingDriverStage.matchingNearby:
        return 1 / 3;
      case WaitingDriverStage.expandingSearch:
        return 2 / 3;
      case WaitingDriverStage.bestDriverMatch:
        return 1.0;
    }
  }

  WaitingDriverStage get next {
    switch (this) {
      case WaitingDriverStage.matchingNearby:
        return WaitingDriverStage.expandingSearch;
      case WaitingDriverStage.expandingSearch:
        return WaitingDriverStage.bestDriverMatch;
      case WaitingDriverStage.bestDriverMatch:
        return WaitingDriverStage.matchingNearby;
    }
  }
}

class WaitingDriverPage extends ConsumerStatefulWidget {
  final String tripMongoId;

  const WaitingDriverPage({
    super.key,
    this.tripMongoId = '',
  });

  @override
  ConsumerState<WaitingDriverPage> createState() => _WaitingDriverPageState();
}

class _WaitingDriverPageState extends ConsumerState<WaitingDriverPage>
    with SingleTickerProviderStateMixin {
  static const _stageDuration = Duration(seconds: 5);
  static const _pollInterval = Duration(seconds: 3);

  late WaitingDriverStage _stage;
  late AnimationController _progressController;
  Timer? _stageTimer;
  Timer? _pollTimer;
  bool _navigatedToDriverFound = false;
  TripModel? _trip;

  String get _tripTitle => _trip?.tripTitle ?? 'One Way Trip';

  String get _tripId => _trip?.displayTripId ?? '# —';

  String get _pickup => _trip?.pickupAddress.isNotEmpty == true
      ? _trip!.pickupAddress
      : '—';

  String get _dropoff => _trip?.dropoffAddress?.isNotEmpty == true
      ? _trip!.dropoffAddress!
      : _pickup;

  String get _price => _trip?.displayPrice ?? '—';

  String get _distance =>
      _trip != null && _trip!.distanceLabel.isNotEmpty ? _trip!.distanceLabel : '—';

  String get _duration => _trip?.durationLabel ?? '—';

  TripLocation? get _pickupLocation => _trip?.pickupLocation;

  TripLocation? get _dropoffLocation {
    final dropoff = _trip?.dropoffLocation;
    if (dropoff != null &&
        (dropoff.hasAddress || dropoff.hasCoordinates)) {
      return dropoff;
    }
    return _pickupLocation;
  }

  bool get _showRoute {
    final dropoff = _trip?.dropoffLocation;
    if (dropoff == null) return false;
    return dropoff.hasAddress || dropoff.hasCoordinates;
  }

  @override
  void initState() {
    super.initState();
    _stage = WaitingDriverStage.matchingNearby;
    _progressController = AnimationController(
      vsync: this,
      duration: _stageDuration,
      value: 0,
    );
    _runStage(_stage);
    _loadTrip();
    _startPolling();
    _listenForReassignment();
  }

  void Function(Map<String, dynamic>)? _onTripReassigned;
  TripSocketService? _tripSocket;

  void _listenForReassignment() {
    if (widget.tripMongoId.isEmpty) return;
    final socket = ref.read(tripSocketServiceProvider);
    _tripSocket = socket;
    socket.ensureConnected();
    _onTripReassigned = (payload) {
      final tripId = payload['tripId']?.toString() ??
          payload['_id']?.toString() ??
          payload['id']?.toString() ??
          '';
      if (tripId.isNotEmpty && tripId != widget.tripMongoId) return;
      if (!mounted || _navigatedToDriverFound) return;
      showAppSnackBar(
        context,
        'Previous driver cancelled. Still finding you another driver...',
      );
    };
    socket.listenForTripReassigned(_onTripReassigned!);
  }

  Future<void> _loadTrip() async {
    final trip = await fetchAndCacheTrip(ref, widget.tripMongoId);
    if (!mounted || trip == null) return;
    setState(() => _trip = trip);
  }

  void _startPolling() {
    if (widget.tripMongoId.isEmpty) return;

    _pollTripStatus();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _pollTripStatus());
  }

  Future<void> _pollTripStatus() async {
    if (_navigatedToDriverFound || !mounted || widget.tripMongoId.isEmpty) {
      return;
    }

    final trip = await fetchAndCacheTrip(ref, widget.tripMongoId);

    if (!mounted || _navigatedToDriverFound) return;
    if (trip == null) return;

    setState(() => _trip = trip);

    if (trip.isCancelled) {
      _pollTimer?.cancel();
      _stageTimer?.cancel();
      await ref.read(activeTripProvider.notifier).clear();
      if (!mounted) return;
      showAppSnackBar(context, 'This trip was cancelled.');
      await navigateAfterTripCancelled(trip.toCancelledDetailsArguments());
      return;
    }

    if (trip.hasAssignedDriver) {
      if (trip.isFutureScheduled) {
        _goToScheduledDetails(trip.toScheduledDetailsArguments());
      } else {
        _goToDriverFound(trip.toDriverFoundArguments());
      }
    }
  }

  void _runStage(WaitingDriverStage stage) {
    _stageTimer?.cancel();
    setState(() => _stage = stage);

    _progressController.duration = _stageDuration;
    _progressController.animateTo(stage.progress, curve: Curves.easeOutCubic);

    _stageTimer = Timer(_stageDuration, () {
      if (!mounted || _navigatedToDriverFound) return;
      _runStage(stage.next);
    });
  }

  void _goToDriverFound(Map<String, dynamic> arguments) {
    if (_navigatedToDriverFound || !mounted) return;
    _navigatedToDriverFound = true;
    _stageTimer?.cancel();
    _pollTimer?.cancel();
    _progressController.stop();
    NavigationService().pushNamedReplacement(
      'driver_found',
      arguments: arguments,
    );
  }

  void _goToScheduledDetails(Map<String, dynamic> arguments) {
    if (_navigatedToDriverFound || !mounted) return;
    _navigatedToDriverFound = true;
    _stageTimer?.cancel();
    _pollTimer?.cancel();
    _progressController.stop();
    NavigationService().pushNamedReplacement(
      'scheduled_trip_details',
      arguments: arguments,
    );
  }

  Future<void> _handleCancel() async {
    final trip = await cancelTripWithDialog(
      context: context,
      ref: ref,
      tripMongoId: widget.tripMongoId,
    );
    if (!mounted || trip == null) return;
    await navigateAfterTripCancelled(trip.toCancelledDetailsArguments());
  }

  @override
  void dispose() {
    _stageTimer?.cancel();
    _pollTimer?.cancel();
    if (_onTripReassigned != null) {
      _tripSocket?.removeTripReassignedListener(_onTripReassigned!);
    }
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kScreenBg,
      body: Column(
        children: [
          _WaitingDriverHeader(
            tripTitle: _tripTitle,
            tripId: _tripId,
            onBack: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                TripMapView(
                  pickup: _pickupLocation,
                  dropoff: _dropoffLocation,
                  showRoute: _showRoute,
                  mode: TripMapMode.fullRoute,
                ),
                Positioned(
                  right: 20,
                  bottom: 16,
                  child: _HelpButton(
                    onTap: () => openTripHelp(
                      tripLabel: _tripId,
                      tripMongoId: widget.tripMongoId,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _WaitingDriverSheet(
            stage: _stage,
            progress: _progressController,
            pickup: _pickup,
            dropoff: _dropoff,
            price: _price,
            distance: _distance,
            duration: _duration,
            onCancel: _handleCancel,
          ),
        ],
      ),
    );
  }
}

class _WaitingDriverHeader extends StatelessWidget {
  final String tripTitle;
  final String tripId;
  final VoidCallback onBack;

  const _WaitingDriverHeader({
    required this.tripTitle,
    required this.tripId,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;

    return ColoredBox(
      color: kWhite,
      child: Padding(
        padding: EdgeInsets.fromLTRB(8, topInset + 4, 12, 12),
        child: Row(
          children: [
            IconButton(
              onPressed: onBack,
              icon: const Icon(
                Icons.arrow_back_ios_new,
                size: 22,
                color: kTextColor,
              ),
              padding: const EdgeInsets.all(12),
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    tripTitle,
                    textAlign: TextAlign.center,
                    style: kWaitingDriverTripTitleSB,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tripId,
                    textAlign: TextAlign.center,
                    style: kWaitingDriverTripIdR,
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () {},
              icon: const Icon(
                Icons.ios_share_outlined,
                size: 24,
                color: kTextColor,
              ),
              padding: const EdgeInsets.all(12),
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
          ],
        ),
      ),
    );
  }
}

class _HelpButton extends StatelessWidget {
  final VoidCallback onTap;

  const _HelpButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kWhite,
      elevation: 4,
      shadowColor: kBlack.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SvgPicture.asset(
                'assets/svg/Help_image.svg',
                width: 22,
                height: 22,
              ),
              const SizedBox(width: 8),
              Text('Help', style: kWaitingDriverHelpM),
            ],
          ),
        ),
      ),
    );
  }
}

class _WaitingDriverSheet extends StatelessWidget {
  final WaitingDriverStage stage;
  final Animation<double> progress;
  final String pickup;
  final String dropoff;
  final String price;
  final String distance;
  final String duration;
  final VoidCallback onCancel;

  const _WaitingDriverSheet({
    required this.stage,
    required this.progress,
    required this.pickup,
    required this.dropoff,
    required this.price,
    required this.distance,
    required this.duration,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: kWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowLight,
            blurRadius: 24,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: AnimatedBuilder(
              animation: progress,
              builder: (context, _) {
                return LinearProgressIndicator(
                  value: progress.value,
                  minHeight: 4,
                  backgroundColor: kActiveGreenBg,
                  color: kActiveGreen,
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(24, 20, 24, bottomInset + 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/pngs/finding_driver.png',
                  height: 200,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 20),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.08),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: _StageCopy(key: ValueKey(stage), stage: stage),
                ),
                const SizedBox(height: 20),
                TripRouteSummaryCard(
                  pickup: pickup,
                  dropoff: dropoff,
                  price: price,
                  distance: distance,
                  duration: duration,
                ),
                const SizedBox(height: 28),
                primaryButton(
                  label: 'Cancel Ride',
                  onPressed: onCancel,
                  buttonColor: kWhite,
                  sideColor: kRed,
                  labelColor: kRed,
                  fontSize: 16,
                  buttonHeight: 54,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StageCopy extends StatelessWidget {
  final WaitingDriverStage stage;

  const _StageCopy({super.key, required this.stage});

  static const _description =
      'Your ride is confirmed , now contacting drivers nearby.';

  @override
  Widget build(BuildContext context) {
    return Column(
      key: key,
      mainAxisSize: MainAxisSize.min,
      children: [
        switch (stage) {
          WaitingDriverStage.matchingNearby => _buildMatchingNearbyHeadline(),
          WaitingDriverStage.expandingSearch => _buildExpandingSearchHeadline(),
          WaitingDriverStage.bestDriverMatch => _buildBestDriverMatchHeadline(),
        },
        const SizedBox(height: 12),
        Text(
          _description,
          textAlign: TextAlign.center,
          style: kWaitingDriverDescriptionR,
        ),
      ],
    );
  }

  Widget _buildMatchingNearbyHeadline() {
    return Column(
      children: [
        Text(
          'Finding your driver',
          textAlign: TextAlign.center,
          style: kWaitingDriverStatusBlueSB,
        ),
        const SizedBox(height: 6),
        Text(
          'Matching nearby drivers',
          textAlign: TextAlign.center,
          style: kWaitingDriverStatusBlackSB,
        ),
      ],
    );
  }

  Widget _buildExpandingSearchHeadline() {
    return Column(
      children: [
        Text(
          'Searching nearby drivers...',
          textAlign: TextAlign.center,
          style: kWaitingDriverStatusBlueSB,
        ),
        const SizedBox(height: 6),
        Text(
          'Expanding search area...',
          textAlign: TextAlign.center,
          style: kWaitingDriverStatusBlackSB,
        ),
      ],
    );
  }

  Widget _buildBestDriverMatchHeadline() {
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: kWaitingDriverHeadlineSB,
        children: [
          const TextSpan(text: "We're matching the\n"),
          TextSpan(
            text: 'best driver for you',
            style: kWaitingDriverHeadlineAccentSB,
          ),
        ],
      ),
    );
  }
}
