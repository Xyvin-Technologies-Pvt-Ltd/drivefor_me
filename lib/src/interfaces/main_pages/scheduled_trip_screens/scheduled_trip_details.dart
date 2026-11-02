import 'dart:async';

import 'package:DriveForme/src/data/constants/colour_constants.dart';
import 'package:DriveForme/src/data/constants/style_constants.dart';
import 'package:DriveForme/src/data/services/navigation_services.dart';
import 'package:DriveForme/src/data/utils/trip_lifecycle.dart';
import 'package:DriveForme/src/data/utils/trip_screen_helpers.dart';
import 'package:DriveForme/src/interfaces/components/primaryButton.dart';
import 'package:DriveForme/src/interfaces/main_pages/trip_pages/trip_completed.dart';
import 'package:DriveForme/src/interfaces/main_pages/waiting_driver/driver_found.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class ScheduledTripDetailsPage extends ConsumerStatefulWidget {
  final String tripTitle;
  final String tripId;
  final String? tripMongoId;
  final DateTime scheduledAt;
  final String pickup;
  final String dropoff;
  final String distance;
  final String duration;
  final String vehicleType;
  final String tripFare;
  final String paymentTypeLabel;
  final bool hasDriver;
  final String? driverName;
  final double driverRating;
  final int driverTrips;
  final String? driverPhotoUrl;
  final String vehicleTypes;
  final bool isLongTrip;
  final TripCompletedPaymentType paymentType;
  final bool forcePickupTime;

  const ScheduledTripDetailsPage({
    super.key,
    required this.tripTitle,
    required this.tripId,
    this.tripMongoId,
    required this.scheduledAt,
    required this.pickup,
    required this.dropoff,
    required this.distance,
    required this.duration,
    required this.vehicleType,
    required this.tripFare,
    required this.paymentTypeLabel,
    this.hasDriver = false,
    this.driverName,
    this.driverRating = 5.0,
    this.driverTrips = 0,
    this.driverPhotoUrl,
    required this.vehicleTypes,
    this.isLongTrip = false,
    required this.paymentType,
    this.forcePickupTime = false,
  });

  @override
  ConsumerState<ScheduledTripDetailsPage> createState() =>
      _ScheduledTripDetailsPageState();
}

class _ScheduledTripDetailsPageState extends ConsumerState<ScheduledTripDetailsPage> {
  static final _dateFormat = DateFormat('MMMM d, hh:mm a');

  static const _driverPollInterval = Duration(seconds: 5);

  Timer? _countdownTimer;
  Timer? _driverPollTimer;
  Duration _timeUntilPickup = Duration.zero;

  late bool _hasDriver;
  late String? _driverName;
  late double _driverRating;
  late int _driverTrips;
  late String? _driverPhotoUrl;
  late String _vehicleTypes;

  /// True once local time reaches the scheduled pickup minute (or later).
  bool get _isPickupTime {
    if (widget.forcePickupTime) return true;
    final now = _truncateToMinute(DateTime.now());
    final scheduled = _truncateToMinute(widget.scheduledAt.toLocal());
    return !now.isBefore(scheduled);
  }

  static DateTime _truncateToMinute(DateTime value) {
    return DateTime(
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
    );
  }

  @override
  void initState() {
    super.initState();
    _hasDriver = widget.hasDriver;
    _driverName = widget.driverName;
    _driverRating = widget.driverRating;
    _driverTrips = widget.driverTrips;
    _driverPhotoUrl = widget.driverPhotoUrl;
    _vehicleTypes = widget.vehicleTypes;
    _refreshCountdown();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _refreshCountdown();
    });
    _loadTripDriverDetails();
    _driverPollTimer = Timer.periodic(_driverPollInterval, (_) {
      _loadTripDriverDetails();
    });
  }

  Future<void> _loadTripDriverDetails() async {
    final tripMongoId = widget.tripMongoId;
    if (tripMongoId == null || tripMongoId.isEmpty) return;

    final trip = await fetchAndCacheTrip(ref, tripMongoId);
    if (!mounted || trip == null) return;

    if (!trip.hasAssignedDriver && !trip.hasDriver) return;

    setState(() {
      _hasDriver = true;
      _driverName = trip.driverName ?? _driverName;
      _driverRating = trip.driverRating ?? _driverRating;
      _driverTrips = trip.driverTrips ?? _driverTrips;
      final photoUrl = trip.driverPhotoUrl?.trim();
      if (photoUrl != null && photoUrl.isNotEmpty) {
        _driverPhotoUrl = photoUrl;
      }
      if (trip.vehicleTypesLabel.isNotEmpty) {
        _vehicleTypes = trip.vehicleTypesLabel;
      }
    });
  }

  void _refreshCountdown() {
    final remaining = widget.scheduledAt.difference(DateTime.now());
    setState(() {
      _timeUntilPickup = remaining.isNegative ? Duration.zero : remaining;
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _driverPollTimer?.cancel();
    super.dispose();
  }

  String get _countdownLabel {
    if (_timeUntilPickup.inSeconds <= 0) return '';
    final hours = _timeUntilPickup.inHours;
    final minutes = _timeUntilPickup.inMinutes.remainder(60);
    if (hours > 0) {
      return 'Starts in $hours hrs $minutes min';
    }
    return 'Starts in $minutes min';
  }

  String get _dateLabel =>
      'Date : ${_dateFormat.format(widget.scheduledAt.toLocal())}';

  void _onImAtPickup() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => DriverFoundPage()));
  }

  Future<void> _handleCancel() async {
    if (widget.tripMongoId == null || widget.tripMongoId!.isEmpty) {
      Navigator.of(context).maybePop();
      return;
    }
    final trip = await cancelTripWithDialog(
      context: context,
      ref: ref,
      tripMongoId: widget.tripMongoId!,
    );
    if (!mounted || trip == null) return;
    await navigateAfterTripCancelled(trip.toCancelledDetailsArguments());
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final showCountdown = !_isPickupTime && _countdownLabel.isNotEmpty;

    return Scaffold(
      backgroundColor: kScreenBg,
      body: Column(
        children: [
          _ScheduledTripHeader(
            tripTitle: widget.tripTitle,
            tripId: widget.tripId,
            onBack: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: kWhite,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: kBlack.withValues(alpha: 0.05),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        _ScheduledBadge(),
                        const SizedBox(width: 8),
                        _TripTypeBadge(isLongTrip: widget.isLongTrip),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_month_outlined,
                          size: 18,
                          color: kTripBodyMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_dateLabel, style: kScheduledTripDateR),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _TripStatsRow(
                      distance: widget.distance,
                      duration: widget.duration,
                      vehicleType: widget.vehicleType,
                    ),
                    const SizedBox(height: 18),
                    _ScheduledRouteSection(
                      pickup: widget.pickup,
                      dropoff: widget.dropoff,
                    ),
                    const SizedBox(height: 16),
                    if (_hasDriver && _driverName != null)
                      _ScheduledDriverCard(
                        driverName: _driverName!,
                        driverRating: _driverRating,
                        driverTrips: _driverTrips,
                        driverPhotoUrl: _driverPhotoUrl,
                        vehicleTypes: _vehicleTypes,
                      )
                    else
                      _DriverPendingCard(vehicleTypes: _vehicleTypes),
                    if (showCountdown) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Icon(
                            Icons.schedule_rounded,
                            size: 20,
                            color: kActiveGreen,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _countdownLabel,
                            style: kScheduledTripCountdownSB,
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    _PaymentDetailsCard(
                      tripFare: widget.tripFare,
                      paymentType: widget.paymentTypeLabel,
                      isPrepaid: widget.paymentType ==
                          TripCompletedPaymentType.online,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: kWhite,
              boxShadow: [
                BoxShadow(
                  color: kBlack.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            padding: EdgeInsets.fromLTRB(20, 14, 20, bottomInset + 16),
            child: !_isPickupTime
                ? Row(
                    children: [
                      Expanded(
                        child: primaryButton(
                          label: 'Cancel Trip',
                          onPressed: _handleCancel,
                          buttonColor: kWhite,
                          sideColor: kRed,
                          labelColor: kRed,
                          fontSize: 15,
                          buttonHeight: 52,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: primaryButton(
                          label: "I'm at Pickup",
                          onPressed: _onImAtPickup,
                          buttonColor: kTripCtaBlue,
                          fontSize: 15,
                          buttonHeight: 52,
                        ),
                      ),
                    ],
                  )
                : primaryButton(
                    label: 'Cancel Ride',
                    onPressed: _handleCancel,
                    buttonColor: kWhite,
                    sideColor: kRed,
                    labelColor: kRed,
                    fontSize: 16,
                    buttonHeight: 54,
                  ),
          ),
        ],
      ),
    );
  }
}

class _ScheduledTripHeader extends StatelessWidget {
  final String tripTitle;
  final String tripId;
  final VoidCallback onBack;

  const _ScheduledTripHeader({
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

class _ScheduledBadge extends StatelessWidget {
  static const _scheduledBg = AppColors.scheduledBackground;
  static const _scheduledBorder = AppColors.warningOrange;
  static const _scheduledText = AppColors.scheduledTextOrange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _scheduledBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _scheduledBorder, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: _scheduledText,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'SCHEDULED',
            style: kStyle(
              kSemiBold,
              kSize11,
              color: _scheduledText,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _TripTypeBadge extends StatelessWidget {
  final bool isLongTrip;

  const _TripTypeBadge({required this.isLongTrip});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: kChipGreyBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isLongTrip ? Icons.calendar_month_outlined : Icons.arrow_forward_rounded,
            size: 14,
            color: kBlack.withValues(alpha: 0.65),
          ),
          const SizedBox(width: 4),
          Text(
            isLongTrip ? 'LONG TRIP' : 'SHORT TRIP',
            style: kStyle(
              kSemiBold,
              kSize11,
              color: kTextColor,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _TripStatsRow extends StatelessWidget {
  final String distance;
  final String duration;
  final String vehicleType;

  const _TripStatsRow({
    required this.distance,
    required this.duration,
    required this.vehicleType,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kTripBorder),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: _StatCell(label: 'Distance', value: distance),
            ),
            const VerticalDivider(width: 1, thickness: 1, color: kTripBorder),
            Expanded(
              child: _StatCell(label: 'Duration', value: duration),
            ),
            const VerticalDivider(width: 1, thickness: 1, color: kTripBorder),
            Expanded(
              child: _StatCell(label: 'Vehicle Type', value: vehicleType),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String label;
  final String value;

  const _StatCell({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Column(
        children: [
          Text(label, style: kScheduledTripStatLabelR),
          const SizedBox(height: 6),
          Text(
            value,
            textAlign: TextAlign.center,
            style: kScheduledTripStatValueSB,
          ),
        ],
      ),
    );
  }
}

class _ScheduledRouteSection extends StatelessWidget {
  final String pickup;
  final String dropoff;

  const _ScheduledRouteSection({required this.pickup, required this.dropoff});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RouteStop(
          icon: Icons.location_on_rounded,
          iconColor: kActiveGreen,
          title: pickup,
          subtitle: 'Pickup Location',
        ),
        Padding(
          padding: const EdgeInsets.only(left: 11),
          child: SizedBox(
            height: 28,
            width: 1.5,
            child: CustomPaint(
              painter: _DashedLinePainter(color: kLineGrey, vertical: true),
            ),
          ),
        ),
        _RouteStop(
          icon: Icons.location_on_rounded,
          iconColor: kDropBlue,
          title: dropoff,
          subtitle: 'Drop Location',
        ),
      ],
    );
  }
}

class _RouteStop extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  const _RouteStop({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: iconColor, size: 24),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: kScheduledTripRouteTitleSB),
              const SizedBox(height: 2),
              Text(subtitle, style: kScheduledTripRouteSubtitleR),
            ],
          ),
        ),
      ],
    );
  }
}

class _DriverPendingCard extends StatelessWidget {
  final String vehicleTypes;

  const _DriverPendingCard({required this.vehicleTypes});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kTripCreamBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kCardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: kChipGreyBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.person_outline, color: kMutedText, size: 32),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Driver pending', style: kDriverFoundNameSB),
                const SizedBox(height: 4),
                Text(
                  'A driver will be assigned before your pickup time.',
                  style: kDriverFoundMetaR,
                ),
                if (vehicleTypes.isNotEmpty && vehicleTypes != '—') ...[
                  const SizedBox(height: 2),
                  Text(vehicleTypes, style: kDriverFoundMetaR),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduledDriverCard extends StatelessWidget {
  final String driverName;
  final double driverRating;
  final int driverTrips;
  final String? driverPhotoUrl;
  final String vehicleTypes;

  const _ScheduledDriverCard({
    required this.driverName,
    required this.driverRating,
    required this.driverTrips,
    this.driverPhotoUrl,
    required this.vehicleTypes,
  });

  @override
  Widget build(BuildContext context) {
    final photoUrl = driverPhotoUrl?.trim();
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;

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
            child: hasPhoto
                ? Image.network(
                    photoUrl,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        _driverPlaceholder(),
                  )
                : _driverPlaceholder(),
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
            onTap: () {
              NavigationService().pushNamed(
                'chat_screen',
                arguments: {'participantName': driverName},
              );
            },
          ),
          const SizedBox(width: 8),
          _DriverActionButton(
            color: kBlue,
            icon: Icons.phone_in_talk_rounded,
            onTap: () {},
          ),
        ],
      ),
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

  Widget _driverPlaceholder() {
    return Container(
      width: 56,
      height: 56,
      color: kChipGreyBg,
      child: const Icon(Icons.person, color: kMutedText, size: 32),
    );
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

class _PaymentDetailsCard extends StatelessWidget {
  final String tripFare;
  final String paymentType;
  final bool isPrepaid;

  const _PaymentDetailsCard({
    required this.tripFare,
    required this.paymentType,
    this.isPrepaid = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: kWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: kActiveGreenBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 18,
                  color: kActiveGreen,
                ),
              ),
              const SizedBox(width: 10),
              Text('Payment details', style: kScheduledTripSectionSB),
            ],
          ),
          const SizedBox(height: 14),
          _PaymentRow(label: 'Trip Fare', value: tripFare),
          const SizedBox(height: 10),
          _PaymentRow(label: 'Payment Type', value: paymentType),
          if (isPrepaid) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Text('Payment Status', style: kScheduledTripPaymentLabelR),
                const Spacer(),
                Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                    color: kActiveGreen,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, size: 12, color: kWhite),
                ),
                const SizedBox(width: 6),
                Text('Paid', style: kScheduledTripPaidSB),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  final String label;
  final String value;

  const _PaymentRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: kScheduledTripPaymentLabelR),
        const Spacer(),
        Text(value, style: kScheduledTripPaymentValueSB),
      ],
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  final Color color;
  final bool vertical;

  _DashedLinePainter({required this.color, this.vertical = false});

  @override
  void paint(Canvas canvas, Size size) {
    const dashLength = 4.0;
    const dashSpace = 3.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    if (vertical) {
      var y = 0.0;
      while (y < size.height) {
        canvas.drawLine(Offset(0, y), Offset(0, y + dashLength), paint);
        y += dashLength + dashSpace;
      }
    } else {
      var x = 0.0;
      while (x < size.width) {
        canvas.drawLine(Offset(x, 0), Offset(x + dashLength, 0), paint);
        x += dashLength + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.vertical != vertical;
}
