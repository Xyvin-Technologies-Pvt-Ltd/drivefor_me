import 'dart:async';

import 'package:DriveForme/src/data/apis/trip_api.dart';
import 'package:DriveForme/src/data/constants/colour_constants.dart';
import 'package:DriveForme/src/data/constants/style_constants.dart';
import 'package:DriveForme/src/data/models/trip_model.dart';
import 'package:DriveForme/src/data/services/navigation_services.dart';
import 'package:DriveForme/src/data/services/trip_socket_service.dart';
import 'package:DriveForme/src/interfaces/components/primaryButton.dart';
import 'package:DriveForme/src/data/services/snackbar_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum TripCompletedPaymentType { online, offline }

TripCompletedPaymentType parseTripCompletedPaymentType(dynamic value) {
  if (value is TripCompletedPaymentType) return value;
  if (value is bool) {
    return value
        ? TripCompletedPaymentType.online
        : TripCompletedPaymentType.offline;
  }
  if (value is int) {
    return value == 1
        ? TripCompletedPaymentType.online
        : TripCompletedPaymentType.offline;
  }

  final normalized = value?.toString().toLowerCase().trim() ?? '';
  if (normalized == 'online' ||
      normalized == 'pay_online' ||
      normalized == 'prepaid' ||
      normalized == '1') {
    return TripCompletedPaymentType.online;
  }

  return TripCompletedPaymentType.offline;
}

Map<String, dynamic> tripPaymentArguments(TripCompletedPaymentType paymentType) {
  return {
    'paymentType':
        paymentType == TripCompletedPaymentType.online ? 'online' : 'offline',
  };
}

class TripCompletedPage extends ConsumerStatefulWidget {
  final String tripMongoId;
  final TripCompletedPaymentType paymentType;
  final String paymentMethod;
  final bool isRated;
  final String tripTypeLabel;
  final String destinationName;
  final String destinationAddress;
  final String totalFare;
  final String prepaidAmount;
  final String prepaidDuration;
  final String tripFare;
  final String tripDuration;
  final String extraTimeAmount;
  final String extraTimeDuration;
  final String remainingDue;
  final String remainingDuration;
  final String totalAmount;
  final String driverId;
  final String driverName;
  final double driverRating;
  final int driverTrips;
  final String? driverPhotoUrl;
  final String vehicleTypes;

  const TripCompletedPage({
    super.key,
    this.tripMongoId = '',
    this.paymentType = TripCompletedPaymentType.offline,
    this.paymentMethod = 'cash',
    this.isRated = false,
    this.tripTypeLabel = 'Long Trip',
    this.destinationName = '—',
    this.destinationAddress = '—',
    this.totalFare = '—',
    this.prepaidAmount = '—',
    this.prepaidDuration = '—',
    this.tripFare = '—',
    this.tripDuration = '—',
    this.extraTimeAmount = '—',
    this.extraTimeDuration = '—',
    this.remainingDue = '—',
    this.remainingDuration = '—',
    this.totalAmount = '—',
    this.driverId = '',
    this.driverName = TripModel.noNameFound,
    this.driverRating = 0,
    this.driverTrips = 0,
    this.driverPhotoUrl,
    this.vehicleTypes = '',
  });

  @override
  ConsumerState<TripCompletedPage> createState() => _TripCompletedPageState();
}

class _TripCompletedPageState extends ConsumerState<TripCompletedPage> {
  static const _pollInterval = Duration(seconds: 3);

  bool _waitingForCashCollection = false;
  bool _navigatedAway = false;
  Timer? _pollTimer;
  TripSocketService? _tripSocket;

  bool get _isOnline =>
      widget.paymentType == TripCompletedPaymentType.online;

  bool get _isWallet => widget.paymentMethod == 'wallet';

  bool get _isCash =>
      !_isOnline &&
      !_isWallet &&
      (widget.paymentMethod == 'cash' ||
          widget.paymentMethod == 'offline' ||
          widget.paymentMethod.isEmpty);

  String get _paidAmount {
    if (_isOnline) {
      return widget.remainingDue.replaceAll(' ', '');
    }
    return widget.totalAmount.replaceAll(' ', '');
  }

  Map<String, dynamic> get _ratingArgs => {
        'tripMongoId': widget.tripMongoId,
        'driverId': widget.driverId,
        'driverName': widget.driverName,
        'driverRating': widget.driverRating,
        'driverTrips': widget.driverTrips,
        'driverPhotoUrl': widget.driverPhotoUrl ?? '',
        'vehicleTypes': widget.vehicleTypes,
      };

  @override
  void initState() {
    super.initState();
    if (_isCash && widget.tripMongoId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _startCashCollectionWatch();
      });
    }
  }

  @override
  void dispose() {
    _stopCashCollectionWatch();
    super.dispose();
  }

  void _startCashCollectionWatch() {
    if (_waitingForCashCollection || widget.tripMongoId.isEmpty) return;

    setState(() => _waitingForCashCollection = true);

    _tripSocket = ref.read(tripSocketServiceProvider);
    _tripSocket!
      ..ensureConnected()
      ..joinTripRoom(widget.tripMongoId)
      ..listenForTripUpdated(_onTripUpdated);

    _pollCashCollectionStatus();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      _pollCashCollectionStatus();
    });
  }

  void _stopCashCollectionWatch() {
    _pollTimer?.cancel();
    _pollTimer = null;
    final tripId = widget.tripMongoId;
    final socket = _tripSocket;
    if (socket != null) {
      socket.removeTripUpdatedListener(_onTripUpdated);
      if (tripId.isNotEmpty) {
        socket.leaveTripRoom(tripId);
      }
    }
    _tripSocket = null;
  }

  void _onTripUpdated(Map<String, dynamic> payload) {
    final tripId = payload['_id']?.toString() ??
        payload['id']?.toString() ??
        payload['tripId']?.toString() ??
        '';
    if (tripId.isNotEmpty && tripId != widget.tripMongoId) return;

    final paymentStatus = payload['paymentStatus']?.toString() ?? '';
    final cashCollectedAt = payload['cashCollectedAt'];
    final collected = paymentStatus == 'paid' ||
        paymentStatus == 'completed' ||
        cashCollectedAt != null;

    if (collected) {
      _goToPaymentCompleted();
      return;
    }

    // Socket payload may be partial — refresh from API.
    _pollCashCollectionStatus();
  }

  Future<void> _pollCashCollectionStatus() async {
    if (_navigatedAway || !mounted || widget.tripMongoId.isEmpty) return;

    final response =
        await ref.read(tripApiProvider).getTripById(widget.tripMongoId);
    if (!mounted || _navigatedAway) return;
    if (!response.success || response.data == null) return;

    if (response.data!.isPaymentCollected) {
      _goToPaymentCompleted();
    }
  }

  void _goToPaymentCompleted() {
    if (_navigatedAway || !mounted) return;
    _navigatedAway = true;
    _stopCashCollectionWatch();

    if (widget.isRated) {
      NavigationService().pushNamedAndRemoveUntil('thank_you');
      return;
    }

    NavigationService().pushNamedReplacement(
      'payment_completed',
      arguments: {
        'paidAmount': _paidAmount,
        ..._ratingArgs,
      },
    );
  }

  Future<void> _onContinue() async {
    if (_navigatedAway) return;

    if (widget.isRated) {
      NavigationService().pushNamedAndRemoveUntil('thank_you');
      return;
    }

    if (_isWallet) {
      NavigationService().pushNamedReplacement(
        'driver_rating',
        arguments: _ratingArgs,
      );
      return;
    }

    // Cash: Payment Completed only after the driver marks cash as collected.
    if (_isCash) {
      if (widget.tripMongoId.isEmpty) {
        showAppSnackBar(context, 'Trip id missing. Please reopen the trip.');
        return;
      }

      final response =
          await ref.read(tripApiProvider).getTripById(widget.tripMongoId);
      if (!mounted || _navigatedAway) return;

      if (response.success &&
          response.data != null &&
          response.data!.isPaymentCollected) {
        _goToPaymentCompleted();
        return;
      }

      if (!_waitingForCashCollection) {
        _startCashCollectionWatch();
      }

      showAppSnackBar(
        context,
        'Waiting for the driver to confirm cash collection.',
      );
      return;
    }

    // Online / other: keep existing post-trip acknowledgement flow.
    NavigationService().pushNamedReplacement(
      'payment_completed',
      arguments: {
        'paidAmount': _paidAmount,
        ..._ratingArgs,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final continueLabel = _isWallet
        ? 'Continue'
        : (_isOnline
            ? 'Pay ${widget.remainingDue}'
            : (_waitingForCashCollection
                ? 'Waiting for driver…'
                : 'Continue'));

    return Scaffold(
      backgroundColor: kScreenBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            children: [
              Image.asset(
                'assets/pngs/tripcompleted.png',
                height: 220,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 28),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: kBookingConfirmedTitleSB,
                  children: [
                    const TextSpan(text: 'Trip '),
                    TextSpan(
                      text: 'Completed!',
                      style: kBookingConfirmedAccentSB,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Thank you for completing the trip. Hope you had a smooth ride.',
                textAlign: TextAlign.center,
                style: kBookingConfirmedSubtitleR,
              ),
              if (_isCash) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _waitingForCashCollection
                        ? const Color(0xFFFFF3E8)
                        : kActiveGreenBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _waitingForCashCollection
                        ? 'Please pay the driver in cash. Waiting for the driver to mark payment as collected…'
                        : 'Please pay the driver in cash. Payment Completed will appear after the driver confirms collection.',
                    textAlign: TextAlign.center,
                    style: kStyle(
                      kSemiBold,
                      kSize14,
                      color: _waitingForCashCollection
                          ? const Color(0xFFC6934B)
                          : kActiveGreen,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              _TripTypePill(label: widget.tripTypeLabel),
              const SizedBox(height: 18),
              _DestinationBlock(
                name: widget.destinationName,
                address: widget.destinationAddress,
              ),
              const SizedBox(height: 22),
              _FareBreakdownCard(
                isOnline: _isOnline,
                totalFare: widget.totalFare,
                prepaidAmount: widget.prepaidAmount,
                prepaidDuration: widget.prepaidDuration,
                tripFare: widget.tripFare,
                tripDuration: widget.tripDuration,
                extraTimeAmount: widget.extraTimeAmount,
                extraTimeDuration: widget.extraTimeDuration,
                remainingDue: widget.remainingDue,
                remainingDuration: widget.remainingDuration,
                totalAmount: widget.totalAmount,
              ),
              if (_isWallet) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: kActiveGreenBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Paid from wallet: ${widget.totalAmount}',
                    textAlign: TextAlign.center,
                    style: kStyle(kSemiBold, kSize15, color: kActiveGreen),
                  ),
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: primaryButton(
          label: continueLabel,
          onPressed: _onContinue,
          buttonColor: kTripCtaBlue,
          buttonHeight: 58,
          fontSize: 18,
        ),
      ),
    );
  }
}

class _TripTypePill extends StatelessWidget {
  final String label;

  const _TripTypePill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: kTripCreamBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.tripSummaryBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.arrow_forward, size: 16, color: kTextColor),
          const SizedBox(width: 6),
          Text(label, style: kTripChipDurationSB),
        ],
      ),
    );
  }
}

class _DestinationBlock extends StatelessWidget {
  final String name;
  final String address;

  const _DestinationBlock({required this.name, required this.address});

  static const _locationBrown = AppColors.locationBrown;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_on, size: 18, color: _locationBrown),
            const SizedBox(width: 4),
            Text(
              name,
              style: kStyle(kSemiBold, kSize16, color: _locationBrown),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          address,
          textAlign: TextAlign.center,
          style: kStyle(kRegular, kSize12, color: kTripMutedLabel, height: 1.45),
        ),
      ],
    );
  }
}

class _FareBreakdownCard extends StatelessWidget {
  final bool isOnline;
  final String totalFare;
  final String prepaidAmount;
  final String prepaidDuration;
  final String tripFare;
  final String tripDuration;
  final String extraTimeAmount;
  final String extraTimeDuration;
  final String remainingDue;
  final String remainingDuration;
  final String totalAmount;

  const _FareBreakdownCard({
    required this.isOnline,
    required this.totalFare,
    required this.prepaidAmount,
    required this.prepaidDuration,
    required this.tripFare,
    required this.tripDuration,
    required this.extraTimeAmount,
    required this.extraTimeDuration,
    required this.remainingDue,
    required this.remainingDuration,
    required this.totalAmount,
  });

  static const _cardBg = AppColors.tripSummaryCardBackground;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Fare Breakdown', style: kTripSectionTitleSB),
          const SizedBox(height: 14),
          if (isOnline) ...[
            _FareRow(
              label: 'Total Fare',
              amount: totalFare,
            ),
            const SizedBox(height: 12),
            const _DashedDivider(),
            const SizedBox(height: 12),
            _FareRow(
              label: 'Prepaid Amount',
              amount: prepaidAmount,
              trailingNote: '($prepaidDuration)',
            ),
            const SizedBox(height: 12),
            const _DashedDivider(),
            const SizedBox(height: 12),
            _FareRow(
              label: 'Remaining Due',
              amount: remainingDue,
              trailingNote: '($remainingDuration)',
              highlight: true,
            ),
          ] else ...[
            _FareRow(
              label: 'Trip Fare',
              amount: tripFare,
              trailingNote: '($tripDuration)',
            ),
            const SizedBox(height: 12),
            const _DashedDivider(),
            const SizedBox(height: 12),
            _FareRow(
              label: 'Extra Time',
              amount: extraTimeAmount,
              trailingNote: '($extraTimeDuration)',
              labelBold: true,
            ),
            const SizedBox(height: 12),
            const _DashedDivider(),
            const SizedBox(height: 12),
            _FareRow(
              label: 'Total Amount',
              amount: totalAmount,
              highlightBlue: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _FareRow extends StatelessWidget {
  final String label;
  final String amount;
  final String? trailingNote;
  final bool highlight;
  final bool highlightBlue;
  final bool labelBold;

  const _FareRow({
    required this.label,
    required this.amount,
    this.trailingNote,
    this.highlight = false,
    this.highlightBlue = false,
    this.labelBold = false,
  });

  static const _dueBrown = AppColors.locationBrown;

  @override
  Widget build(BuildContext context) {
    final labelStyle = highlightBlue
        ? kStyle(kSemiBold, kSize15, color: kTripCtaBlue)
        : highlight
            ? kStyle(kSemiBold, kSize15, color: _dueBrown)
            : labelBold
                ? kStyle(kSemiBold, kSize14, color: kTextColor)
                : kStyle(kRegular, kSize14, color: kTextColor);

    final noteStyle = kStyle(kRegular, kSize14, color: kTripMutedLabel);
    final amountStyle = highlightBlue
        ? kStyle(kSemiBold, kSize16, color: kTripCtaBlue)
        : highlight
            ? kStyle(kSemiBold, kSize16, color: _dueBrown)
            : kStyle(kSemiBold, kSize16, color: kTextColor);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: RichText(
            text: TextSpan(
              style: labelStyle,
              children: [
                TextSpan(text: label),
                if (trailingNote != null)
                  TextSpan(text: ' $trailingNote', style: noteStyle),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(amount, style: amountStyle),
      ],
    );
  }
}

class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const dashWidth = 5.0;
        const dashSpace = 4.0;
        final dashCount =
            (constraints.maxWidth / (dashWidth + dashSpace)).floor().clamp(1, 200);

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(dashCount, (_) {
            return Container(
              width: dashWidth,
              height: 1,
              color: AppColors.tripSummaryMutedBorder,
            );
          }),
        );
      },
    );
  }
}
