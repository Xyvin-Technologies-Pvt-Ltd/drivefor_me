import 'package:DriveForme/src/data/models/trip_location_model.dart';
import 'package:DriveForme/src/data/utils/date_utils.dart';

class TripModel {
  /// Shown when the backend does not provide a driver / person full name.
  static const String noNameFound = 'No name found';

  static String resolveDriverName(String? name) {
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return noNameFound;
    return trimmed;
  }

  final String id;
  final String tripNumber;
  final String status;
  final String tripDirection;
  final String tripType;
  final String rideTime;
  final TripLocation pickupLocation;
  final TripLocation? dropoffLocation;
  final TripLocation? driverLocation;
  final double? distanceKm;
  final String? estimatedDurationLabel;
  final int durationValue;
  final String durationUnit;
  final int additionalHours;
  final DateTime? pickupAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final double? priceMinimum;
  final double? priceMaximum;
  final String currency;
  final String paymentMethod;
  final String paymentStatus;
  final DateTime? cashCollectedAt;
  final double? paymentTotalFare;
  final double? paymentPackageFare;
  final double? paymentBaseFare;
  final double? paymentExtraTimeCharge;
  final int paymentExtraHours;
  final int paymentOvertimeMinutes;
  final int paymentExpectedDurationMinutes;
  final double? paymentOtherCharge;
  final String? driverName;
  final double? driverRating;
  final int? driverTrips;
  final String? driverPhone;
  final String? driverPhotoUrl;
  final String vehicleName;
  final String vehicleNumber;
  final String vehicleType;
  final String transmission;
  final String? driverId;
  final bool isRated;
  final int? ratingStars;
  final String? ratingComment;
  final List<String> feedbackTags;
  final double cancellationChargeAmount;
  final double cancellationCompensationAmount;
  final String? cancellationChargeMessage;
  final String? cancellationChargeStage;

  const TripModel({
    required this.id,
    required this.tripNumber,
    required this.status,
    required this.tripDirection,
    required this.tripType,
    required this.rideTime,
    required this.pickupLocation,
    this.dropoffLocation,
    this.driverLocation,
    this.distanceKm,
    this.estimatedDurationLabel,
    required this.durationValue,
    required this.durationUnit,
    this.additionalHours = 0,
    this.pickupAt,
    this.startedAt,
    this.completedAt,
    this.cancelledAt,
    this.priceMinimum,
    this.priceMaximum,
    this.currency = 'INR',
    required this.paymentMethod,
    this.paymentStatus = 'pending',
    this.cashCollectedAt,
    this.paymentTotalFare,
    this.paymentPackageFare,
    this.paymentBaseFare,
    this.paymentExtraTimeCharge,
    this.paymentExtraHours = 0,
    this.paymentOvertimeMinutes = 0,
    this.paymentExpectedDurationMinutes = 0,
    this.paymentOtherCharge,
    this.driverName,
    this.driverRating,
    this.driverTrips,
    this.driverPhone,
    this.driverPhotoUrl,
    this.vehicleName = '',
    this.vehicleNumber = '',
    this.vehicleType = '',
    this.transmission = '',
    this.driverId,
    this.isRated = false,
    this.ratingStars,
    this.ratingComment,
    this.feedbackTags = const [],
    this.cancellationChargeAmount = 0,
    this.cancellationCompensationAmount = 0,
    this.cancellationChargeMessage,
    this.cancellationChargeStage,
  });

  factory TripModel.fromJson(Map<String, dynamic> json) {
    final route = json['route'];
    final routeMap = route is Map ? Map<String, dynamic>.from(route) : null;
    final routeSummary = routeMap != null ? _asMap(routeMap['summary']) : null;
    final tripDetails = json['tripDetails'];
    final timeline = json['timeline'];
    final priceEstimate = tripDetails is Map ? tripDetails['priceEstimate'] : null;
    final vehicleDetails = json['vehicleDetails'];
    final payment = _asMap(json['payment']);
    final driver = _resolveDriver(json);
    final rating = json['rating'];
    final ratingMap = rating is Map ? Map<String, dynamic>.from(rating) : null;
    final charges = _resolveCancellationCharges(json);

    return TripModel(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      tripNumber: json['tripNumber']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      tripDirection: tripDetails is Map
          ? tripDetails['tripDirection']?.toString() ?? 'one_way'
          : 'one_way',
      tripType: () {
        if (tripDetails is Map && tripDetails['tripType'] != null) {
          return tripDetails['tripType'].toString();
        }
        return json['tripType']?.toString() ?? 'short_trip';
      }(),
      rideTime: tripDetails is Map
          ? tripDetails['rideTime']?.toString() ?? 'now'
          : 'now',
      pickupLocation: routeMap != null
          ? TripLocation.fromDynamic(routeMap['pickupLocation'])
          : const TripLocation.empty(),
      dropoffLocation: routeMap != null
          ? _optionalLocation(routeMap['dropoffLocation'])
          : null,
      driverLocation: _resolveDriverLocation(json, routeMap),
      distanceKm: _toDouble(routeSummary?['distanceKm']),
      estimatedDurationLabel:
          routeSummary?['estimatedDurationLabel']?.toString(),
      durationValue: tripDetails is Map
          ? (tripDetails['durationValue'] as num?)?.toInt() ?? 1
          : 1,
      durationUnit: tripDetails is Map
          ? tripDetails['durationUnit']?.toString() ?? 'hours'
          : 'hours',
      additionalHours: tripDetails is Map
          ? (tripDetails['additionalHours'] as num?)?.toInt() ?? 0
          : 0,
      pickupAt: tripDetails is Map ? _parseDate(tripDetails['pickupAt']) : null,
      startedAt: timeline is Map ? _parseDate(timeline['startedAt']) : null,
      completedAt: timeline is Map ? _parseDate(timeline['completedAt']) : null,
      cancelledAt: timeline is Map ? _parseDate(timeline['cancelledAt']) : null,
      priceMinimum: priceEstimate is Map
          ? _toDouble(priceEstimate['minimum'])
          : null,
      priceMaximum: priceEstimate is Map
          ? _toDouble(priceEstimate['maximum'])
          : null,
      currency: priceEstimate is Map
          ? priceEstimate['currency']?.toString() ?? 'INR'
          : 'INR',
      paymentMethod: json['paymentMethod']?.toString() ?? 'cash',
      paymentStatus: json['paymentStatus']?.toString() ??
          json['payment_status']?.toString() ??
          (json['isPaid'] == true ? 'paid' : 'pending'),
      cashCollectedAt: _parseDate(json['cashCollectedAt']),
      paymentTotalFare: _toDouble(payment?['totalFare']),
      paymentPackageFare: _toDouble(payment?['packageFare']),
      paymentBaseFare: _toDouble(payment?['baseFare']),
      paymentExtraTimeCharge: _toDouble(payment?['extraTimeCharge']),
      paymentExtraHours: (payment?['extraHours'] as num?)?.toInt() ?? 0,
      paymentOvertimeMinutes:
          (payment?['overtimeMinutes'] as num?)?.toInt() ?? 0,
      paymentExpectedDurationMinutes:
          (payment?['expectedDurationMinutes'] as num?)?.toInt() ?? 0,
      paymentOtherCharge: _toDouble(payment?['otherCharge']),
      driverName: _userName(driver),
      driverRating: _userRating(driver),
      driverTrips: _userTotalTrips(driver),
      driverPhone: _userPhone(driver),
      driverPhotoUrl: _driverPhotoUrl(driver),
      vehicleName: vehicleDetails is Map
          ? vehicleDetails['vehicleName']?.toString() ?? ''
          : '',
      vehicleNumber: vehicleDetails is Map
          ? vehicleDetails['vehicleNumber']?.toString() ?? ''
          : '',
      vehicleType: vehicleDetails is Map
          ? vehicleDetails['vehicleType']?.toString() ?? ''
          : '',
      transmission: vehicleDetails is Map
          ? vehicleDetails['transmission']?.toString() ?? ''
          : '',
      driverId: _driverId(driver),
      isRated: json['isRated'] == true ||
          ratingMap?['stars'] != null ||
          json['ratedAt'] != null,
      ratingStars: ratingMap?['stars'] is num
          ? (ratingMap!['stars'] as num).toInt()
          : null,
      ratingComment: ratingMap?['comment']?.toString(),
      feedbackTags: ratingMap?['feedbackTags'] is List
          ? (ratingMap!['feedbackTags'] as List)
              .map((e) => e.toString())
              .toList()
          : const [],
      cancellationChargeAmount:
          _toDouble(charges?['customerChargeAmount']) ?? 0,
      cancellationCompensationAmount:
          _toDouble(charges?['driverCompensationAmount']) ?? 0,
      cancellationChargeMessage: charges?['message']?.toString(),
      cancellationChargeStage: charges?['stage']?.toString(),
    );
  }

  bool get hasCancellationCharge => cancellationChargeAmount > 0;

  String get cancellationChargeDisplay =>
      hasCancellationCharge ? _formatInr(cancellationChargeAmount) : '₹ 0';

  bool get isLongTrip => tripType == 'long_trip';
  bool get isOneWay => tripDirection == 'one_way';

  String get pickupAddress => pickupLocation.address;

  String? get dropoffAddress {
    final address = dropoffLocation?.address ?? '';
    return address.isEmpty ? null : address;
  }

  bool get hasDriver =>
      driverId != null && driverId!.isNotEmpty && hasDriverName;

  bool get hasDriverName => driverName != null && driverName!.isNotEmpty;

  String get displayDriverName => resolveDriverName(driverName);

  bool get isDriverAssigned =>
      status == 'driver_assigned' && driverId != null && driverId!.isNotEmpty;

  /// True when a driver is on the booking (including future scheduled accepts).
  bool get hasAssignedDriver =>
      driverId != null && driverId!.isNotEmpty;

  bool get isPickupTimeReached {
    if (pickupAt == null) return rideTime != 'scheduled';
    final nowClock = DateTime.now();
    final pickup = pickupAt!.toLocal();
    final now = DateTime(
      nowClock.year,
      nowClock.month,
      nowClock.day,
      nowClock.hour,
      nowClock.minute,
    );
    final scheduled = DateTime(
      pickup.year,
      pickup.month,
      pickup.day,
      pickup.hour,
      pickup.minute,
    );
    return !now.isBefore(scheduled);
  }

  /// Scheduled booking that should not enter the live trip screens yet.
  bool get isFutureScheduled =>
      (rideTime == 'scheduled' || status == 'scheduled') &&
      !isPickupTimeReached &&
      !isCancelled;

  /// Statuses that still occupy the owner's single booking slot.
  static const activeBookingStatuses = [
    'pre_booked',
    'awaiting_pre_auth_window',
    'requires_admin_call',
    'call_completed_pending_auth',
    'pre_authorized',
    'confirmed',
    'pending_assignment',
    'driver_assigned',
    'scheduled',
    'in_progress',
  ];

  bool get isInProgress => status == 'in_progress';

  bool get isCompleted => status == 'completed';

  bool get isCancelled => status == 'cancelled';

  /// True while this booking should stop the owner from creating another.
  /// A trip with a cancellation time is finished even if its status lagged behind.
  bool get isActiveBooking =>
      cancelledAt == null &&
      !isCancelled &&
      !isCompleted &&
      activeBookingStatuses.contains(status);

  bool get isWalletPayment => paymentMethod == 'wallet';

  bool get isCashPayment =>
      paymentMethod == 'cash' || paymentMethod == 'offline';

  /// Cash is paid only after the driver confirms "Mark as Collected".
  bool get isPaymentCollected =>
      paymentStatus == 'paid' ||
      paymentStatus == 'completed' ||
      cashCollectedAt != null;

  bool get isAwaitingCashCollection =>
      isCashPayment && isCompleted && !isPaymentCollected;

  String get displayTripId =>
      tripNumber.isNotEmpty ? '# $tripNumber' : '# ${id.substring(0, 8)}';

  String get tripTitle => isOneWay ? 'One Way Trip' : 'Round Trip';

  String get directionChipLabel => isOneWay ? 'One Way' : 'Round Trip';

  String get tripTypeChipLabel => isLongTrip ? 'LONG TRIP' : 'SHORT TRIP';

  String get displayPrice {
    final amount = paymentTotalFare ?? priceMinimum ?? priceMaximum;
    if (amount == null) return '—';
    return _formatInr(amount);
  }

  /// Package fare (maps/booking estimate) — excludes runtime Extra Time.
  String get tripFareDisplay {
    final amount = paymentPackageFare ??
        (paymentTotalFare != null && paymentExtraTimeCharge != null
            ? paymentTotalFare! - paymentExtraTimeCharge!
            : null) ??
        priceMinimum ??
        priceMaximum;
    if (amount == null) return '—';
    return _formatInr(amount);
  }

  String get baseFareDisplay => tripFareDisplay;

  String get extraTimeAmountDisplay {
    final amount = paymentExtraTimeCharge ?? 0;
    if (amount <= 0) return '—';
    return _formatInr(amount);
  }

  /// Actual overtime label (e.g. "1 hr 40 min"), not billable ceil hours.
  String get extraTimeDurationDisplay {
    if (paymentOvertimeMinutes <= 0 && paymentExtraHours <= 0) return '—';
    if (paymentOvertimeMinutes > 0) {
      return _formatDurationMinutes(paymentOvertimeMinutes);
    }
    return paymentExtraHours == 1 ? '1 hr' : '$paymentExtraHours hrs';
  }

  String get expectedDurationDisplay {
    if (paymentExpectedDurationMinutes > 0) {
      return _formatDurationMinutes(paymentExpectedDurationMinutes);
    }
    return durationLabel;
  }

  String get totalAmountDisplay {
    final amount = paymentTotalFare ?? priceMinimum ?? priceMaximum;
    if (amount == null) return '—';
    return _formatInr(amount);
  }

  static String _formatInr(double amount) => '₹ ${amount.toStringAsFixed(0)}';

  static String _formatDurationMinutes(int minutes) {
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final remaining = minutes % 60;
    if (remaining == 0) return hours == 1 ? '1 hr' : '$hours hrs';
    return '$hours hr $remaining min';
  }

  String get vehicleTypesLabel {
    if (vehicleName.isNotEmpty && vehicleNumber.isNotEmpty) {
      return '$vehicleName • $vehicleNumber';
    }
    if (vehicleName.isNotEmpty) return vehicleName;
    if (vehicleNumber.isNotEmpty) return vehicleNumber;

    final type = _titleCase(vehicleType);
    final trans = _titleCase(transmission);
    if (type.isEmpty && trans.isEmpty) return '—';
    if (type.isEmpty) return trans;
    if (trans.isEmpty) return type;
    return '$trans + $type';
  }

  String get driverFoundSubtitle {
    if (pickupAt != null && rideTime != 'now') {
      return 'Pickup ${formatScheduleLine(pickupAt)}';
    }
    return 'Share the OTP below with your driver to start the trip';
  }

  String get durationLabel {
    if (durationUnit == 'custom') {
      final dayPart = durationValue == 1 ? '1 Day' : '$durationValue Days';
      final hourPart =
          additionalHours == 1 ? '1 Hour' : '$additionalHours Hours';
      if (durationValue > 0 && additionalHours > 0) {
        return '$dayPart • $hourPart';
      }
      if (durationValue > 0) return dayPart;
      return hourPart;
    }
    if (estimatedDurationLabel != null && estimatedDurationLabel!.isNotEmpty) {
      return estimatedDurationLabel!;
    }
    if (durationUnit == 'days') {
      return durationValue == 1 ? '1 day' : '$durationValue days';
    }
    return durationValue == 1 ? '1 hr' : '$durationValue hrs';
  }

  String get distanceLabel {
    if (distanceKm == null) return '';
    final value = distanceKm!;
    final formatted = value % 1 == 0
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return '$formatted km';
  }

  String get metaRest {
    final parts = <String>[durationLabel];
    if (distanceLabel.isNotEmpty) parts.add(distanceLabel);
    return ' • ${parts.join(' • ')}';
  }

  String formatMetaPrimary(DateTime? date) {
    if (date == null) return '—';
    final local = date.toLocal();
    if (isLongTrip && durationUnit == 'days' && durationValue > 1) {
      final end = local.add(Duration(days: durationValue - 1));
      return '${formatLocalDateTime(local, 'd MMMM')} to ${formatLocalDateTime(end, 'd MMMM')}';
    }
    return formatLocalDateTime(local, 'd MMMM');
  }

  String formatScheduleLine(DateTime? date) {
    if (date == null) return metaRest.trim();
    final local = date.toLocal();
    final dayLabel = _relativeDayLabel(local);
    final time = formatLocalDateTime(local, 'hh:mm a');
    return '$dayLabel, $time$metaRest';
  }

  String upcomingStatusLabel() {
    switch (status) {
      case 'scheduled':
        return 'Scheduled';
      case 'driver_assigned':
        return 'Driver Assigned';
      case 'pending_assignment':
        return 'Pending';
      default:
        return 'Upcoming';
    }
  }

  DateTime? get referenceDate {
    switch (status) {
      case 'completed':
        return completedAt ?? pickupAt;
      case 'cancelled':
        return cancelledAt ?? pickupAt;
      case 'in_progress':
        return startedAt ?? pickupAt;
      default:
        return pickupAt ?? startedAt;
    }
  }

  String get paymentTypeKey =>
      paymentMethod == 'pay_online' || paymentMethod == 'upi' ? 'online' : 'offline';

  String get paymentTypeLabel =>
      paymentTypeKey == 'online' ? 'Online(Prepaid)' : 'Cash';

  Map<String, dynamic> toDriverFoundArguments() {
    return {
      'tripMongoId': id,
      'tripTitle': tripTitle,
      'tripId': displayTripId,
      'pickup': pickupAddress,
      'dropoff': dropoffAddress ?? pickupAddress,
      'price': displayPrice,
      'distance': distanceLabel.isEmpty ? '—' : distanceLabel,
      'duration': durationLabel,
      'driverId': driverId ?? '',
      'driverName': displayDriverName,
      'driverPhone': driverPhone ?? '',
      'driverPhotoUrl': driverPhotoUrl ?? '',
      'driverRating': driverRating ?? 5.0,
      'driverTrips': driverTrips ?? 0,
      'vehicleName': vehicleName,
      'vehicleNumber': vehicleNumber,
      'vehicleTypes': vehicleTypesLabel,
      'paymentType': paymentTypeKey,
    };
  }

  Map<String, dynamic> toProgressArguments() {
    return {
      'tripMongoId': id,
      'tripTitle': tripTitle,
      'tripId': displayTripId,
      'headingTo': dropoffAddress ?? pickupAddress,
      'pickup': pickupAddress,
      'dropoff': dropoffAddress ?? pickupAddress,
      'driverId': driverId ?? '',
      'driverName': displayDriverName,
      'driverPhone': driverPhone ?? '',
      'driverPhotoUrl': driverPhotoUrl ?? '',
      'driverRating': driverRating ?? 5.0,
      'driverTrips': driverTrips ?? 0,
      'vehicleName': vehicleName,
      'vehicleNumber': vehicleNumber,
      'vehicleTypes': vehicleTypesLabel,
      'price': displayPrice,
      'distance': distanceLabel.isEmpty ? '—' : distanceLabel,
      'duration': durationLabel,
      'paymentType': paymentTypeKey,
      'paymentMethod': paymentMethod,
    };
  }

  Map<String, dynamic> toTripCompletedArguments() {
    final total = totalAmountDisplay;

    return {
      'tripMongoId': id,
      'paymentType': paymentTypeKey,
      'paymentMethod': paymentMethod,
      'tripTypeLabel': isLongTrip ? 'Long Trip' : 'Short Trip',
      'destinationName': dropoffAddress ?? pickupAddress,
      'destinationAddress': dropoffAddress ?? pickupAddress,
      'totalFare': total,
      'prepaidAmount': tripFareDisplay,
      'prepaidDuration': expectedDurationDisplay,
      'tripFare': tripFareDisplay,
      'tripDuration': expectedDurationDisplay,
      'extraTimeAmount': extraTimeAmountDisplay,
      'extraTimeDuration': extraTimeDurationDisplay,
      'remainingDue': total,
      'remainingDuration': '—',
      'totalAmount': total,
      'driverId': driverId ?? '',
      'driverName': displayDriverName,
      'driverPhone': driverPhone ?? '',
      'driverPhotoUrl': driverPhotoUrl ?? '',
      'driverRating': driverRating ?? 5.0,
      'driverTrips': driverTrips ?? 0,
      'vehicleName': vehicleName,
      'vehicleNumber': vehicleNumber,
      'vehicleTypes': vehicleTypesLabel,
      'isRated': isRated,
    };
  }

  Map<String, dynamic> toRatingArguments() {
    return {
      'tripMongoId': id,
      'driverId': driverId ?? '',
      'driverName': displayDriverName,
      'driverPhone': driverPhone ?? '',
      'driverPhotoUrl': driverPhotoUrl ?? '',
      'driverRating': driverRating ?? 5.0,
      'driverTrips': driverTrips ?? 0,
      'vehicleName': vehicleName,
      'vehicleNumber': vehicleNumber,
      'vehicleTypes': vehicleTypesLabel,
    };
  }

  Map<String, dynamic> toWaitingDriverArguments() {
    return {
      'tripMongoId': id,
      'tripTitle': tripTitle,
      'tripId': displayTripId,
      'paymentType': paymentTypeKey,
      'pickup': pickupAddress,
      'dropoff': dropoffAddress ?? pickupAddress,
      'price': displayPrice,
      'distance': distanceLabel.isEmpty ? '—' : distanceLabel,
      'duration': durationLabel,
    };
  }

  Map<String, dynamic> toScheduledDetailsArguments() {
    return {
      'tripMongoId': id,
      'tripTitle': tripTitle,
      'tripId': displayTripId,
      'scheduledAt': pickupAt ?? DateTime.now(),
      'pickup': pickupAddress,
      'dropoff': dropoffAddress ?? pickupAddress,
      'distance': distanceLabel.isEmpty ? '—' : distanceLabel,
      'duration': durationLabel,
      'vehicleType': _titleCase(vehicleType),
      'tripFare': displayPrice,
      'paymentTypeLabel': paymentTypeLabel,
      'paymentType': paymentTypeKey,
      'hasDriver': hasDriver,
      'isLongTrip': isLongTrip,
      if (hasDriver) ...{
        'driverName': displayDriverName,
        'driverRating': driverRating ?? 5.0,
        'driverTrips': driverTrips ?? 0,
        'driverPhotoUrl': driverPhotoUrl ?? '',
      },
      'vehicleTypes': vehicleTypesLabel,
    };
  }

  Map<String, dynamic> toCompletedDetailsArguments() {
    return {
      'tripTitle': tripTitle,
      'tripId': displayTripId,
      'tripMongoId': id,
      'isLongTrip': isLongTrip,
      'pickup': pickupAddress,
      'dropoff': dropoffAddress ?? pickupAddress,
      'metaLine':
          '${formatMetaPrimary(referenceDate)}$metaRest',
      'tripFare': tripFareDisplay,
      'tripFareDurationLabel': expectedDurationDisplay,
      'extraTimeFare': extraTimeAmountDisplay,
      'extraTimeDurationLabel': extraTimeDurationDisplay,
      'totalPaid': totalAmountDisplay,
      'driverName': displayDriverName,
      'driverRating': driverRating ?? 5.0,
      'driverTrips': driverTrips ?? 0,
      'driverPhotoUrl': driverPhotoUrl ?? '',
      'vehicleTypes': vehicleTypesLabel,
    };
  }

  bool get isPaid => isPaymentCollected;

  bool get hasRefund => isPaid;

  Map<String, dynamic> toCancelledDetailsArguments() {
    return {
      'tripTitle': tripTitle,
      'tripId': displayTripId,
      'tripMongoId': id,
      'isLongTrip': isLongTrip,
      'pickup': pickupAddress,
      'dropoff': dropoffAddress ?? pickupAddress,
      'metaLine':
          '${formatMetaPrimary(referenceDate)}$metaRest',
      'amountPaid': isPaid ? displayPrice : '₹ 0',
      'refundAmount': isPaid ? displayPrice : '—',
      'refundInitiatedAt': cancelledAt != null
          ? formatLocalDateTime(cancelledAt!, 'd MMMM yyyy, hh:mm a')
          : '—',
      'isPaid': isPaid,
      'hasRefund': hasRefund,
      'cancellationCharge': cancellationChargeDisplay,
      'hasCancellationCharge': hasCancellationCharge,
      'cancellationChargeMessage': cancellationChargeMessage ?? '',
      'driverName': displayDriverName,
      'driverRating': driverRating ?? 5.0,
      'driverTrips': driverTrips ?? 0,
      'driverPhotoUrl': driverPhotoUrl ?? '',
      'vehicleTypes': vehicleTypesLabel,
      'hasDriver': hasDriver,
    };
  }

  static Map<String, dynamic>? _resolveCancellationCharges(
    Map<String, dynamic> json,
  ) {
    final topLevel = _asMap(json['cancellationCharges']);
    if (topLevel != null) return topLevel;
    final cancellation = _asMap(json['cancellation']);
    return _asMap(cancellation?['charges']);
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static dynamic _resolveDriver(Map<String, dynamic> json) {
    final topLevel = json['driver'];
    if (topLevel is Map && topLevel.isNotEmpty) return topLevel;

    final assignment = json['driverAssignment'];
    if (assignment is Map) return assignment['assignedDriver'];
    return null;
  }

  static TripLocation? _optionalLocation(dynamic location) {
    final parsed = TripLocation.fromDynamic(location);
    if (!parsed.hasAddress && !parsed.hasCoordinates) return null;
    return parsed;
  }

  static TripLocation? _resolveDriverLocation(
    Map<String, dynamic> json,
    Map<String, dynamic>? routeMap,
  ) {
    final candidates = <dynamic>[
      json['liveDriverLocation'],
      json['driverLocation'],
      routeMap?['driverLocation'],
      routeMap?['liveDriverLocation'],
    ];

    final driver = _resolveDriver(json);
    if (driver is Map) {
      candidates.addAll([
        driver['lastLocation'],
        driver['currentLocation'],
        driver['location'],
        driver['liveLocation'],
      ]);
    }

    final assignment = json['driverAssignment'];
    if (assignment is Map) {
      candidates.addAll([
        assignment['currentLocation'],
        assignment['driverLocation'],
        assignment['liveLocation'],
      ]);
    }

    for (final candidate in candidates) {
      final location = TripLocation.fromDynamic(candidate);
      if (location.hasCoordinates) return location;
    }

    return null;
  }

  static DateTime? _parseDate(dynamic value) => parseApiDateTime(value);

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static String? _driverId(dynamic user) {
    if (user is Map) {
      final id = user['_id'] ?? user['id'];
      if (id != null) return id.toString();
    }
    return null;
  }

  static String? _userName(dynamic user) {
    if (user is Map) {
      final profile = user['profile'];
      if (profile is Map && profile['fullName'] != null) {
        final name = profile['fullName'].toString().trim();
        if (name.isNotEmpty) return name;
      }
    }
    return null;
  }

  static double? _userRating(dynamic user) {
    if (user is Map && user['rating'] != null) {
      return (user['rating'] as num).toDouble();
    }
    return null;
  }

  static int? _userTotalTrips(dynamic user) {
    if (user is Map && user['totalTrips'] != null) {
      return (user['totalTrips'] as num).toInt();
    }
    return null;
  }

  static String? _userPhone(dynamic user) {
    if (user is Map) {
      final phone = user['phoneNumber']?.toString().trim();
      if (phone != null && phone.isNotEmpty) return phone;
    }
    return null;
  }

  static String? _driverPhotoUrl(dynamic user) {
    if (user is! Map) return null;

    final candidates = <dynamic>[
      if (user['driverVerification'] is Map)
        (user['driverVerification'] as Map)['livePhotoUrl'],
      if (user['profile'] is Map) (user['profile'] as Map)['livePhotoUrl'],
      if (user['profile'] is Map) (user['profile'] as Map)['avatarUrl'],
      user['livePhotoUrl'],
      user['photoUrl'],
      user['avatar'],
      user['avatarUrl'],
      user['profilePhotoUrl'],
    ];

    for (final candidate in candidates) {
      final url = candidate?.toString().trim();
      if (url != null && url.isNotEmpty) return url;
    }
    return null;
  }

  static String _titleCase(String value) {
    if (value.isEmpty) return value;
    return value
        .split('_')
        .map(
          (part) => part.isEmpty
              ? part
              : '${part[0].toUpperCase()}${part.substring(1)}',
        )
        .join(' ');
  }

  static String _relativeDayLabel(DateTime date) {
    final local = date.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(local.year, local.month, local.day);
    final diff = target.difference(today).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff == -1) return 'Yesterday';
    return formatLocalDateTime(local, 'EEE, dd MMM');
  }
}
