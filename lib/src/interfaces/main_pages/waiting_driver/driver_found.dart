import 'dart:async';

import 'package:DriveForme/src/data/apis/trip_api.dart';
import 'package:DriveForme/src/data/constants/colour_constants.dart';
import 'package:DriveForme/src/data/constants/style_constants.dart';
import 'package:DriveForme/src/data/models/trip_location_model.dart';
import 'package:DriveForme/src/data/models/trip_model.dart';
import 'package:DriveForme/src/data/providers/live_driver_location_provider.dart';
import 'package:DriveForme/src/data/services/trip_socket_service.dart';
import 'package:DriveForme/src/data/utils/date_utils.dart';
import 'package:DriveForme/src/data/utils/phone_launcher.dart';
import 'package:DriveForme/src/data/utils/trip_lifecycle.dart';
import 'package:DriveForme/src/data/utils/trip_screen_helpers.dart';
import 'package:DriveForme/src/interfaces/components/trip_map_view.dart';
import 'package:DriveForme/src/interfaces/components/primaryButton.dart';
import 'package:DriveForme/src/interfaces/components/trip_route_summary_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

class DriverFoundPage extends ConsumerStatefulWidget {
  final String tripMongoId;

  const DriverFoundPage({super.key, this.tripMongoId = ''});

  @override
  ConsumerState<DriverFoundPage> createState() => _DriverFoundPageState();
}

class _DriverFoundPageState extends ConsumerState<DriverFoundPage> {
  static const _otpBorderColor = AppColors.selectedChipGold;
  static const _policyTimerBlue = kBrandBlue;
  static const _pollInterval = Duration(seconds: 3);

  TripModel? _trip;
  String? _otp;
  bool _isLoadingOtp = true;
  String? _otpError;
  Timer? _cancelTimer;
  Timer? _pollTimer;
  Duration _cancelRemaining = const Duration(minutes: 10);
  bool _navigatedToProgress = false;
  /// Cached for dispose — ref is unsafe after the widget unmounts.
  late final TripSocketService _tripSocket;
  void Function(Map<String, dynamic>)? _onTripReassigned;
  void Function(Map<String, dynamic>)? _onTripUpdated;

  String get _tripTitle => _trip?.tripTitle ?? 'One Way Trip';

  String get _tripId => _trip?.displayTripId ?? '# —';

  String get _pickup =>
      _trip?.pickupAddress.isNotEmpty == true ? _trip!.pickupAddress : '—';

  String get _dropoff => _trip?.dropoffAddress?.isNotEmpty == true
      ? _trip!.dropoffAddress!
      : _pickup;

  String get _price => _trip?.displayPrice ?? '—';

  String get _distance => _trip != null && _trip!.distanceLabel.isNotEmpty
      ? _trip!.distanceLabel
      : '—';

  String get _duration => _trip?.durationLabel ?? '—';

  String get _driverName =>
      TripModel.resolveDriverName(_trip?.driverName);

  String get _driverId => _trip?.driverId ?? '';

  double get _driverRating => _trip?.driverRating ?? 5.0;

  int get _driverTrips => _trip?.driverTrips ?? 0;

  String get _vehicleTypes => _trip?.vehicleTypesLabel ?? '—';

  String? get _driverPhone => _trip?.driverPhone;

  String? get _driverPhotoUrl => _trip?.driverPhotoUrl;

  String get _subtitle =>
      _trip?.driverFoundSubtitle ??
      'Share the OTP below with your driver to start the trip';

  TripLocation? get _pickupLocation => _trip?.pickupLocation;

  TripLocation? get _dropoffLocation {
    final dropoff = _trip?.dropoffLocation;
    if (dropoff != null && (dropoff.hasAddress || dropoff.hasCoordinates)) {
      return dropoff;
    }
    return _pickupLocation;
  }

  TripLocation? get _driverLocation {
    final live = ref.watch(liveDriverLocationProvider);
    if (live != null && live.tripId == widget.tripMongoId) {
      return live.location;
    }
    return _trip?.driverLocation;
  }

  @override
  void initState() {
    super.initState();
    _tripSocket = ref.read(tripSocketServiceProvider);
    _loadTrip();
    _loadStartOtp();
    _startTripStatusPolling();
    _listenForReassignment();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(liveTripTrackingProvider.notifier).trackTrip(widget.tripMongoId);
    });
  }

  void _listenForReassignment() {
    if (widget.tripMongoId.isEmpty) return;

    Future<void> handlePayload(Map<String, dynamic> payload) async {
      // trip_reassigned sends {tripId,status}; trip_updated may send the full trip.
      final tripId = payload['tripId']?.toString() ??
          payload['_id']?.toString() ??
          payload['id']?.toString() ??
          '';
      final status = payload['status']?.toString() ?? '';
      if (tripId.isNotEmpty && tripId != widget.tripMongoId) return;
      if (_navigatedToProgress || !mounted) return;

      if (status.isNotEmpty && status != 'pending_assignment') {
        final trip = await fetchAndCacheTrip(ref, widget.tripMongoId);
        if (!mounted || trip == null || _navigatedToProgress) return;
        if (await navigateIfTripLeftDriverFoundStage(ref: ref, trip: trip)) {
          _navigatedToProgress = true;
          _pollTimer?.cancel();
        }
        return;
      }

      final trip = await fetchAndCacheTrip(ref, widget.tripMongoId);
      if (!mounted || trip == null || _navigatedToProgress) return;
      if (trip.status == 'pending_assignment' || status == 'pending_assignment') {
        _navigatedToProgress = true;
        _pollTimer?.cancel();
        await navigateAfterDriverReassigned(trip: trip);
      }
    }

    _onTripReassigned = (payload) => handlePayload(payload);
    _onTripUpdated = (payload) => handlePayload(payload);
    _tripSocket.listenForTripReassigned(_onTripReassigned!);
    _tripSocket.listenForTripUpdated(_onTripUpdated!);
  }

  Future<void> _loadTrip() async {
    final trip = await fetchAndCacheTrip(ref, widget.tripMongoId);
    if (!mounted || trip == null) return;
    setState(() => _trip = trip);
    _syncLiveLocation(trip);

    if (await navigateIfTripLeftDriverFoundStage(ref: ref, trip: trip)) {
      _navigatedToProgress = true;
      _pollTimer?.cancel();
    }
  }

  Future<void> _loadStartOtp() async {
    if (widget.tripMongoId.isEmpty) {
      setState(() {
        _isLoadingOtp = false;
        _otpError = 'Trip reference is missing.';
      });
      return;
    }

    final response = await ref
        .read(tripApiProvider)
        .generateStartOtp(widget.tripMongoId);

    if (!mounted) return;

    if (!response.success || response.data == null) {
      setState(() {
        _isLoadingOtp = false;
        _otpError = response.message ?? 'Failed to load trip OTP.';
      });
      return;
    }

    final otp = response.data!['otp']?.toString();
    final expiresAtRaw = response.data!['expiresAt'];
    final expiresAt = parseApiDateTime(expiresAtRaw);

    setState(() {
      _isLoadingOtp = false;
      _otp = otp;
      if (otp == null || otp.length != 4) {
        _otpError = 'Invalid OTP received from server.';
      }
    });

    if (expiresAt != null) {
      _startCancelCountdown(expiresAt);
    } else {
      _startCancelCountdown(DateTime.now().add(const Duration(minutes: 10)));
    }
  }

  void _startCancelCountdown(DateTime expiresAt) {
    _cancelTimer?.cancel();
    _cancelRemaining = expiresAt.difference(DateTime.now());
    if (_cancelRemaining.isNegative) {
      _cancelRemaining = Duration.zero;
    }

    _cancelTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final remaining = expiresAt.difference(DateTime.now());
      setState(() {
        _cancelRemaining = remaining.isNegative ? Duration.zero : remaining;
      });
      if (remaining.isNegative) {
        _cancelTimer?.cancel();
      }
    });
  }

  void _startTripStatusPolling() {
    if (widget.tripMongoId.isEmpty) return;

    _pollTripStatus();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _pollTripStatus());
  }

  Future<void> _pollTripStatus() async {
    if (_navigatedToProgress || !mounted || widget.tripMongoId.isEmpty) {
      return;
    }

    final trip = await fetchAndCacheTrip(ref, widget.tripMongoId);

    if (!mounted || _navigatedToProgress) return;
    if (trip == null) return;

    setState(() => _trip = trip);
    _syncLiveLocation(trip);

    if (await navigateIfTripLeftDriverFoundStage(ref: ref, trip: trip)) {
      _navigatedToProgress = true;
      _pollTimer?.cancel();
    }
  }

  void _syncLiveLocation(TripModel trip) {
    final location = trip.driverLocation;
    if (location == null || !location.hasCoordinates) return;
    ref.read(liveDriverLocationProvider.notifier).applyFromTrip(
          tripId: trip.id.isNotEmpty ? trip.id : widget.tripMongoId,
          driverId: trip.driverId ?? '',
          location: location,
          tripStatus: trip.status,
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
    _cancelTimer?.cancel();
    _pollTimer?.cancel();
    if (_onTripReassigned != null) {
      _tripSocket.removeTripReassignedListener(_onTripReassigned!);
    }
    if (_onTripUpdated != null) {
      _tripSocket.removeTripUpdatedListener(_onTripUpdated!);
    }
    if (widget.tripMongoId.isNotEmpty) {
      _tripSocket.leaveTripRoom(widget.tripMongoId);
    }
    super.dispose();
  }

  String get _cancelTimerLabel {
    final minutes = _cancelRemaining.inMinutes
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    final seconds = (_cancelRemaining.inSeconds % 60).toString().padLeft(
      2,
      '0',
    );
    return '$minutes:$seconds remaining';
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(liveTripTrackingProvider);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final mapHeight = screenHeight * 0.34;

    return Scaffold(
      backgroundColor: kScreenBg,
      body: Column(
        children: [
          SizedBox(
            height: mapHeight,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                TripMapView(
                  pickup: _pickupLocation,
                  dropoff: _dropoffLocation,
                  driverLocation: _driverLocation,
                  mode: TripMapMode.toPickup,
                  showDropoff: false,
                  showRoute: true,
                  followMovingMarker: true,
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _DriverFoundHeader(
                    tripTitle: _tripTitle,
                    tripId: _tripId,
                    onBack: () => Navigator.of(context).maybePop(),
                    transparent: true,
                  ),
                ),
                Positioned(
                  right: 20,
                  bottom: 12,
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
          Expanded(
            child: _DriverFoundSheet(
              subtitle: _subtitle,
              otp: _otp,
              isLoadingOtp: _isLoadingOtp,
              otpError: _otpError,
              otpBorderColor: _otpBorderColor,
              policyTimerBlue: _policyTimerBlue,
              cancelTimerLabel: _cancelTimerLabel,
              pickup: _pickup,
              dropoff: _dropoff,
              price: _price,
              distance: _distance,
              duration: _duration,
              driverName: _driverName,
              driverId: _driverId,
              tripMongoId: widget.tripMongoId,
              driverRating: _driverRating,
              driverTrips: _driverTrips,
              vehicleTypes: _vehicleTypes,
              driverPhone: _driverPhone,
              driverPhotoUrl: _driverPhotoUrl,
              onCancel: _handleCancel,
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverFoundHeader extends StatelessWidget {
  final String tripTitle;
  final String tripId;
  final VoidCallback onBack;
  final bool transparent;

  const _DriverFoundHeader({
    required this.tripTitle,
    required this.tripId,
    required this.onBack,
    this.transparent = false,
  });

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;

    return ColoredBox(
      color: transparent ? Colors.transparent : kWhite,
      child: Padding(
        padding: EdgeInsets.fromLTRB(4, topInset + 4, 8, 12),
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

class _DriverFoundSheet extends StatelessWidget {
  final String subtitle;
  final String? otp;
  final bool isLoadingOtp;
  final String? otpError;
  final Color otpBorderColor;
  final Color policyTimerBlue;
  final String cancelTimerLabel;
  final String pickup;
  final String dropoff;
  final String price;
  final String distance;
  final String duration;
  final String driverName;
  final String driverId;
  final String tripMongoId;
  final double driverRating;
  final int driverTrips;
  final String vehicleTypes;
  final String? driverPhone;
  final String? driverPhotoUrl;
  final VoidCallback onCancel;

  const _DriverFoundSheet({
    required this.subtitle,
    required this.otp,
    required this.isLoadingOtp,
    this.otpError,
    required this.otpBorderColor,
    required this.policyTimerBlue,
    required this.cancelTimerLabel,
    required this.pickup,
    required this.dropoff,
    required this.price,
    required this.distance,
    required this.duration,
    required this.driverName,
    required this.driverId,
    required this.tripMongoId,
    required this.driverRating,
    required this.driverTrips,
    required this.vehicleTypes,
    this.driverPhone,
    this.driverPhotoUrl,
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
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 20, 20, bottomInset + 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Driver Found',
              textAlign: TextAlign.center,
              style: kDriverFoundTitleSB,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: kDriverFoundSubtitleR,
            ),
            const SizedBox(height: 18),
            _DriverInfoCard(
              driverName: driverName,
              driverId: driverId,
              tripMongoId: tripMongoId,
              driverRating: driverRating,
              driverTrips: driverTrips,
              vehicleTypes: vehicleTypes,
              driverPhone: driverPhone,
              driverPhotoUrl: driverPhotoUrl,
            ),
            const SizedBox(height: 14),
            _OtpCard(
              otp: otp,
              isLoading: isLoadingOtp,
              errorMessage: otpError,
              borderColor: otpBorderColor,
            ),
            const SizedBox(height: 14),
            TripRouteSummaryCard(
              pickup: pickup,
              dropoff: dropoff,
              price: price,
              distance: distance,
              duration: duration,
            ),
            const SizedBox(height: 18),
            Text('Cancelation Policy', style: kDriverFoundSectionTitleSB),
            const SizedBox(height: 8),
            RichText(
              text: TextSpan(
                style: kDriverFoundPolicyR,
                children: [
                  const TextSpan(
                    text: 'Free cancellation until 60 mins before pickup. ',
                  ),
                  TextSpan(
                    text: cancelTimerLabel,
                    style: kDriverFoundPolicyTimerSB.copyWith(
                      color: policyTimerBlue,
                    ),
                  ),
                  const TextSpan(text: ' Charges may apply after that'),
                ],
              ),
            ),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () {},
              child: Text(
                'Learn More',
                style: kDriverFoundLearnMoreM.copyWith(
                  color: policyTimerBlue,
                  decoration: TextDecoration.underline,
                  decorationColor: policyTimerBlue,
                ),
              ),
            ),
            const SizedBox(height: 20),
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
    );
  }
}

class _DriverInfoCard extends StatelessWidget {
  final String driverName;
  final String driverId;
  final String tripMongoId;
  final double driverRating;
  final int driverTrips;
  final String vehicleTypes;
  final String? driverPhone;
  final String? driverPhotoUrl;

  const _DriverInfoCard({
    required this.driverName,
    required this.driverId,
    required this.tripMongoId,
    required this.driverRating,
    required this.driverTrips,
    required this.vehicleTypes,
    this.driverPhone,
    this.driverPhotoUrl,
  });

  @override
  Widget build(BuildContext context) {
    final photoUrl = driverPhotoUrl;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kCardBorder),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: photoUrl != null && photoUrl.isNotEmpty
                ? Image.network(
                    photoUrl,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (_, error, _) {
                      debugPrint('Driver image load error: $error');
                      debugPrint('Attempted to load URL: $photoUrl');
                      return _driverAvatarFallback();
                    },
                  )
                : _driverAvatarFallback(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(driverName, style: kDriverFoundNameSB),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      driverRating.toStringAsFixed(1),
                      style: kDriverFoundRatingM,
                    ),
                    const SizedBox(width: 4),
                    ..._buildStars(driverRating),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        '• $driverTrips trips',
                        style: kDriverFoundMetaR,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(vehicleTypes, style: kDriverFoundMetaR),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _DriverActionButton(
            color: kActiveGreen,
            icon: Icons.chat_bubble_outline_rounded,
            onTap: () => openChatScreen(
              receiverId: driverId,
              receiverName: driverName,
              tripId: tripMongoId,
            ),
          ),
          const SizedBox(width: 8),
          _DriverActionButton(
            color: kBlue,
            icon: Icons.phone_in_talk_rounded,
            onTap: () {
              final phone = driverPhone;
              if (phone != null && phone.isNotEmpty) {
                launchPhoneCall(phone);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _driverAvatarFallback() {
    return Container(
      width: 56,
      height: 56,
      color: kChipGreyBg,
      child: const Icon(Icons.person, color: kMutedText, size: 32),
    );
  }

  List<Widget> _buildStars(double rating) {
    final fullStars = rating.floor();
    final hasHalf = rating - fullStars >= 0.25;

    return List.generate(5, (index) {
      IconData icon;
      if (index < fullStars) {
        icon = Icons.star_rounded;
      } else if (index == fullStars && hasHalf) {
        icon = Icons.star_half_rounded;
      } else {
        icon = Icons.star_outline_rounded;
      }
      return Icon(icon, size: 14, color: AppColors.ratingGold);
    });
  }
}

class _DriverActionButton extends StatelessWidget {
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  const _DriverActionButton({
    required this.color,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, color: kWhite, size: 20),
        ),
      ),
    );
  }
}

class _OtpCard extends StatelessWidget {
  final String? otp;
  final bool isLoading;
  final String? errorMessage;
  final Color borderColor;

  const _OtpCard({
    required this.otp,
    this.isLoading = false,
    this.errorMessage,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    if (errorMessage != null && errorMessage!.isNotEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: kWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kCardBorder),
        ),
        child: Column(
          children: [
            Text('Start your trip', style: kDriverFoundOtpTitleSB),
            const SizedBox(height: 16),
            Text(
              errorMessage!,
              textAlign: TextAlign.center,
              style: kDriverFoundOtpHintR.copyWith(color: kRed),
            ),
          ],
        ),
      );
    }

    if (isLoading || otp == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
        decoration: BoxDecoration(
          color: kWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kCardBorder),
        ),
        child: Column(
          children: [
            Text('Start your trip', style: kDriverFoundOtpTitleSB),
            const SizedBox(height: 16),
            const SizedBox(
              height: 56,
              child: Center(
                child: CircularProgressIndicator(color: kBrandBlue),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Generating your trip OTP...',
              textAlign: TextAlign.center,
              style: kDriverFoundOtpHintR,
            ),
          ],
        ),
      );
    }

    final digits = otp!.padRight(4, '0').substring(0, 4).split('');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: kWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kCardBorder),
      ),
      child: Column(
        children: [
          Text('Start your trip', style: kDriverFoundOtpTitleSB),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                _OtpDigitBox(digit: digits[i], borderColor: borderColor),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Share this code with your driver to begin',
            textAlign: TextAlign.center,
            style: kDriverFoundOtpHintR,
          ),
        ],
      ),
    );
  }
}

class _OtpDigitBox extends StatelessWidget {
  final String digit;
  final Color borderColor;

  const _OtpDigitBox({required this.digit, required this.borderColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: kWhite,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Text(digit, style: kDriverFoundOtpDigitSB),
    );
  }
}
