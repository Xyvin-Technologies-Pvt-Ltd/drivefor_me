import 'dart:async';
import 'dart:developer';

import 'package:DriveForme/src/data/models/route_summary_model.dart';
import 'package:DriveForme/src/data/services/directions_service.dart';
import 'package:DriveForme/src/data/utils/trip_plan_service.dart';
import 'package:DriveForme/src/data/providers/current_location_provider.dart';
import 'package:DriveForme/src/data/models/trip_location_model.dart';
import 'package:DriveForme/src/data/models/trip_model.dart';
import 'package:DriveForme/src/data/models/trip_price_estimate_model.dart';
import 'package:DriveForme/src/data/constants/app_colors.dart';
import 'package:DriveForme/src/data/constants/colour_constants.dart';
import 'package:DriveForme/src/data/constants/style_constants.dart';
import 'package:DriveForme/src/data/apis/onboarding_api.dart';
import 'package:DriveForme/src/data/apis/trip_api.dart';
import 'package:DriveForme/src/data/apis/vehicle_api.dart';
import 'package:DriveForme/src/data/models/api_response.dart';
import 'package:DriveForme/src/data/models/vehicle_model.dart';
import 'package:DriveForme/src/data/services/navigation_services.dart';
import 'package:DriveForme/src/data/providers/pricing_provider.dart';
import 'package:DriveForme/src/data/services/trip_fare_service.dart';
import 'package:DriveForme/src/data/utils/trip_lifecycle.dart';
import 'package:DriveForme/src/interfaces/components/add_vehicle_sheet.dart';
import 'package:DriveForme/src/interfaces/components/primaryButton.dart';
import 'package:DriveForme/src/interfaces/components/schedule_sheet.dart';
import 'package:DriveForme/src/interfaces/components/select_rider.dart';
import 'package:DriveForme/src/data/services/snackbar_service.dart';
import 'package:intl/intl.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CreateTripPage extends ConsumerStatefulWidget {
  const CreateTripPage({super.key});

  @override
  ConsumerState<CreateTripPage> createState() => _CreateTripPageState();
}

class _CreateTripPageState extends ConsumerState<CreateTripPage> {
  int selectedHour = 1;
  int selectedNight = 1;
  int customDays = 1;
  int customHours = 1;
  int customNights = 3;
  bool? isOvernightStay;

  bool isTripProtectionEnabled = true;

  bool isOneWay = true;

  bool isShortTrip = true;
  bool isRideNow = true;
  DateTime? scheduledRideAt;
  int? selectedPaymentIndex;
  bool _isSubmitting = false;
  bool _hasUserSetPickup = false;
  bool _hasUserAdjustedDuration = false;
  bool _isLoadingPickup = true;
  bool _isLoadingRoute = false;
  TripLocation _pickupLocation = const TripLocation.empty();
  TripLocation? _dropoffLocation;
  RouteSummary? _routeSummary;
  List<VehicleModel> _vehicles = [];
  VehicleModel? _selectedVehicle;
  bool _isLoadingVehicles = true;
  TripPriceEstimateModel? _priceEstimate;
  bool _isLoadingEstimate = false;
  int _estimateRequestId = 0;
  Timer? _estimateDebounce;
  Timer? _routeDebounce;
  final DirectionsService _directionsService = DirectionsService();
  static const _tripPlanService = TripPlanService();

  static const _tripProtectionFee = 19;
  static const _estimateDebounceDuration = Duration(milliseconds: 350);

  static final _apiDateFormat = DateFormat('yyyy-MM-dd');
  static final _apiTimeFormat = DateFormat('HH:mm');

  String get _pickupDisplayLabel {
    if (_isLoadingPickup) return 'Getting location...';
    if (_pickupLocation.hasAddress) return _pickupLocation.displayLabel;
    return 'Select pickup location';
  }

  String get _routeInsightLabel {
    if (_isLoadingRoute) return 'Calculating route...';
    if (_routeSummary == null) {
      return isOneWay
          ? 'Select destination to auto-detect trip type'
          : 'Select where you are going to calculate round-trip distance';
    }
    return 'Drive time: ${_routeSummary!.durationLabel} • Booking: $_durationUsageLabel';
  }

  bool get _isDayBasedLongTrip {
    if (isShortTrip) return false;
    return selectedHour == -1 && customDays > 0;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadVehicles();
      _schedulePriceEstimate();
      _applyDefaultPickupLocation();
    });
  }

  Future<void> _applyDefaultPickupLocation() async {
    final location = await ref.read(currentLocationProvider.future);
    if (!mounted || _hasUserSetPickup) return;

    setState(() {
      _isLoadingPickup = false;
      if (location != null &&
          (location.hasAddress || location.hasCoordinates)) {
        _pickupLocation = location;
      }
    });
    _scheduleRouteRefresh();
  }

  @override
  void dispose() {
    _estimateDebounce?.cancel();
    _routeDebounce?.cancel();
    _directionsService.dispose();
    super.dispose();
  }

  void _mutateTripForm(VoidCallback fn, {bool userAdjustedDuration = false}) {
    setState(() {
      fn();
      if (userAdjustedDuration) {
        _hasUserAdjustedDuration = true;
      }
    });
    _schedulePriceEstimate();
  }

  void _scheduleRouteRefresh() {
    _routeDebounce?.cancel();
    _routeDebounce = Timer(_estimateDebounceDuration, _refreshRouteAndTripPlan);
  }

  Future<void> _refreshRouteAndTripPlan() async {
    if (!_pickupLocation.hasAddress ||
        _dropoffLocation == null ||
        !_dropoffLocation!.hasAddress) {
      if (!mounted) return;
      setState(() {
        _isLoadingRoute = false;
        _routeSummary = null;
      });
      _schedulePriceEstimate();
      return;
    }

    if (mounted) setState(() => _isLoadingRoute = true);

    final summary = await _directionsService.routeSummaryBetween(
      origin: _pickupLocation,
      destination: _dropoffLocation!,
    );

    if (!mounted) return;

    if (summary == null) {
      setState(() => _isLoadingRoute = false);
      _schedulePriceEstimate();
      return;
    }

    final tripSummary = isOneWay ? summary : summary.doubled();

    setState(() {
      _routeSummary = tripSummary;
      _isLoadingRoute = false;
      if (!_hasUserAdjustedDuration) {
        _applyTripPlan(_tripPlanService.suggestFromRoute(route: tripSummary));
      }
    });
    _schedulePriceEstimate();
  }

  void _applyTripPlan(TripPlanSuggestion plan) {
    isShortTrip = plan.isShortTrip;
    if (plan.durationUnit == 'days') {
      selectedHour = -1;
      customDays = plan.durationValue;
      isOvernightStay = false;
      selectedNight = 1;
      return;
    }

    isOvernightStay = null;

    if (plan.isShortTrip) {
      selectedHour = plan.durationValue.clamp(
        1,
        TripPlanService.shortTripMaxHours,
      );
      return;
    }

    if (plan.durationValue > 14) {
      selectedHour = -1;
      customHours = plan.durationValue;
      return;
    }

    selectedHour = plan.durationValue.clamp(
      TripPlanService.longTripMinHours,
      14,
    );
  }

  void _schedulePriceEstimate() {
    _estimateDebounce?.cancel();
    _estimateDebounce = Timer(_estimateDebounceDuration, _fetchPriceEstimate);
  }

  Future<void> _fetchPriceEstimate() async {
    final duration = _resolveDuration();
    if (!duration.success || duration.data == null) {
      if (!mounted) return;
      setState(() {
        _isLoadingEstimate = false;
        _priceEstimate = null;
      });
      return;
    }

    final overnight = _resolveOvernightStay(duration.data!);
    if (!overnight.success || overnight.data == null) {
      if (!mounted) return;
      setState(() {
        _isLoadingEstimate = false;
        _priceEstimate = null;
      });
      return;
    }

    if (!mounted) return;
    final requestId = ++_estimateRequestId;
    setState(() => _isLoadingEstimate = true);

    final settings = await ref.read(pricingSettingsProvider.future);

    final estimate = ref
        .read(tripFareServiceProvider)
        .estimate(
          payload: {
            'tripType': isShortTrip ? 'short_trip' : 'long_trip',
            'tripDirection': isOneWay ? 'one_way' : 'round_trip',
            'durationValue': duration.data!['durationValue'],
            'durationUnit': duration.data!['durationUnit'],
            if (duration.data!['additionalHours'] != null)
              'additionalHours': duration.data!['additionalHours'],
            'pickupLocation': _pickupLocation.toJson(),
            if (_dropoffLocation != null)
              'dropoffLocation': _dropoffLocation!.toJson(),
            if (_routeSummary != null) 'routeSummary': _routeSummary!.toJson(),
            'tripProtection': {
              'enabled': isTripProtectionEnabled,
              'fee': isTripProtectionEnabled ? _tripProtectionFee : 0,
            },
            'overnightStay': overnight.data,
            'rideTime': isRideNow ? 'now' : 'scheduled',
            if (!isRideNow && scheduledRideAt != null) ...{
              'pickupTime': _apiTimeFormat.format(scheduledRideAt!),
              'pickupDate': _apiDateFormat.format(scheduledRideAt!),
            },
          },
          settings: settings,
        );

    if (!mounted || requestId != _estimateRequestId) return;
    setState(() {
      _isLoadingEstimate = false;
      _priceEstimate = estimate;
    });
  }

  String get _durationPriceLabel {
    if (_isLoadingEstimate) return '...';
    return _priceEstimate?.displayAmount ?? '—';
  }

  String get _estimatedTotalLabel {
    if (_isLoadingEstimate) return '...';
    if (_priceEstimate == null) return '—';
    if (selectedPaymentIndex == 1) {
      return _priceEstimate!.totalForPaymentMethod('pay_online');
    }
    return _priceEstimate!.displayAmount;
  }

  String get _onlinePaymentTotalLabel {
    if (_isLoadingEstimate) return '...';
    return _priceEstimate?.totalForPaymentMethod('pay_online') ?? '—';
  }

  String get _durationUsageLabel {
    if (!isShortTrip && selectedHour == -1) {
      return '$customDays Day • $customHours Hour';
    }
    return '${isShortTrip ? selectedHour : selectedHour} hrs';
  }

  Future<void> _loadVehicles({VehicleModel? selectVehicle}) async {
    final response = await ref.read(vehicleApiProvider).getMyVehicles();
    if (!mounted) return;

    if (!response.success || response.data == null) {
      setState(() => _isLoadingVehicles = false);
      return;
    }

    final vehicles = response.data!;
    setState(() {
      _vehicles = vehicles;
      _isLoadingVehicles = false;

      if (selectVehicle != null) {
        _selectedVehicle = vehicles.firstWhere(
          (vehicle) => vehicle.id == selectVehicle.id,
          orElse: () => selectVehicle,
        );
        return;
      }

      if (_selectedVehicle != null &&
          vehicles.any((vehicle) => vehicle.id == _selectedVehicle!.id)) {
        return;
      }

      _selectedVehicle = vehicles.isNotEmpty ? vehicles.first : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCreateTripScreenBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: kScreenPaddingH),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),

              /// ================= HEADER =================
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      height: 40,
                      width: 40,
                      decoration: BoxDecoration(
                        color: kWhite,
                        shape: BoxShape.circle,
                        border: Border.all(color: kCardBorder, width: 1),
                      ),
                      child: const Icon(Icons.arrow_back_ios_new, size: 16),
                    ),
                  ),

                  const SizedBox(width: 10),

                  Expanded(
                    child: Text(
                      'Where to go?',
                      style: kStyle(kSemiBold, 14, color: kTextColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  const SizedBox(width: 8),

                  Flexible(
                    child: GestureDetector(
                      onTap: () => showSelectRiderBottomSheet(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: kTripCreamBg,
                          borderRadius: BorderRadius.circular(kPillRadius),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                'For: My Self',
                                style: kTripForPillM,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Icon(Icons.keyboard_arrow_down, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              /// ================= LOCATION CARD =================
              _buildLocationCard(),

              const SizedBox(height: 12),

              /// ================= VEHICLE CARD =================
              _buildVehicleCard(),

              const SizedBox(height: 12),

              /// ================= TRIP DETAILS =================
              _buildTripDetailsCard(),

              const SizedBox(height: 12),

              /// ================= TRIP PROTECTION =================
              _buildProtectionCard(),

              const SizedBox(height: 12),

              /// ================= PAYMENT =================
              _buildPaymentCard(),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _priceEstimate == null && !_isLoadingEstimate
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
              decoration: const BoxDecoration(
                color: kWhite,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.shadowLight,
                    blurRadius: 10,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selectedPaymentIndex == null ? 'Estimated' : 'Total',
                          style: kTripTotalLabelR,
                        ),
                        Text(_estimatedTotalLabel, style: kTripTotalPriceB),
                      ],
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: primaryButton(
                        label: _isSubmitting
                            ? 'Creating trip...'
                            : selectedPaymentIndex == null
                            ? 'Select payment to continue'
                            : selectedPaymentIndex == 1
                            ? 'Pay Online & find driver'
                            : 'Confirm Cash on Pay',
                        onPressed: _isSubmitting || selectedPaymentIndex == null
                            ? null
                            : () => _submitTripCreation(),
                        buttonHeight: 64,
                        fontSize: 18,
                        buttonColor: kTripCtaBlue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  /// ============================================================
  /// LOCATION CARD
  /// ============================================================

  Widget _buildLocationCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kWhite,
        borderRadius: BorderRadius.circular(kCardRadiusMd),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowLight,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          _TripDirectionToggle(
            isOneWay: isOneWay,
            onOneWayTap: () {
              _mutateTripForm(() {
                isOneWay = true;
                _hasUserAdjustedDuration = false;
              });
              _scheduleRouteRefresh();
            },
            onRoundTripTap: () {
              _mutateTripForm(() {
                isOneWay = false;
                _routeSummary = null;
                _hasUserAdjustedDuration = false;
                _hasUserSetPickup = false;
              });
              _applyDefaultPickupLocation();
            },
          ),

          const SizedBox(height: 14),

          _buildOneWayLocationFields(),
        ],
      ),
    );
  }

  Widget _buildOneWayLocationFields() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              height: 18,
              width: 18,
              decoration: BoxDecoration(
                color: kActiveGreen,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(Icons.star, size: 12, color: kWhite),
            ),
            Container(width: 1.5, height: isOneWay ? 56 : 72, color: kLineGrey),
            Container(
              height: 18,
              width: 18,
              decoration: BoxDecoration(
                color: kTripDestIconBg,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(Icons.star, size: 12, color: kTripIconMuted),
            ),
          ],
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: _pickPickupLocation,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('From', style: kTripLocationLabelR),
                          const SizedBox(height: 4),
                          Text(_pickupDisplayLabel, style: kTripLocationValueM),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () =>
                          _openScheduleSheet(openOnScheduleTab: !isRideNow),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: kTripCreamBg,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.access_time, size: 15),
                            const SizedBox(width: 6),
                            Text(
                              isRideNow ? 'Now' : 'Later',
                              style: kTripTimePillM,
                            ),
                            const SizedBox(width: 2),
                            const Icon(Icons.keyboard_arrow_down, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 24, thickness: 1, color: kLineGrey),
              GestureDetector(
                onTap: _pickDropoffLocation,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isOneWay ? 'To' : 'Going to',
                      style: kTripLocationLabelR,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _dropoffLocation?.address ??
                          (isOneWay
                              ? 'Enter destination'
                              : 'Select where you are going'),
                      style: kTripLocationValueM.copyWith(
                        color: _dropoffLocation == null
                            ? kTripMutedLabel
                            : kTextColor,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!isOneWay) ...[
                      const SizedBox(height: 4),
                      Text('Returns to pickup', style: kTripOvernightSubR),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// ============================================================
  /// VEHICLE CARD
  /// ============================================================

  Widget _buildVehicleCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kWhite,
        borderRadius: BorderRadius.circular(kCardRadiusMd),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowLight,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Choose your Vehicle', style: kTripSectionTitleSB),
              ),
              if (_vehicles.isNotEmpty)
                GestureDetector(
                  onTap: _openAddVehicleSheet,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Change', style: kTripChipCustomM),
                      const Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: kBrandBlue,
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isLoadingVehicles)
            const SizedBox(
              height: 168,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_vehicles.isEmpty)
            GestureDetector(
              onTap: _openAddVehicleSheet,
              child: Container(
                height: 56,
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kTripGold, width: 1.2),
                ),
                child: Row(
                  children: [
                    Container(
                      height: 28,
                      width: 28,
                      decoration: BoxDecoration(
                        color: kChipGreyBg,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.add, size: 18, color: kTextColor),
                    ),
                    const SizedBox(width: 12),
                    Text('Add Your Vehicle', style: kTripVehicleAddM),
                    const Spacer(),
                    const Icon(
                      Icons.directions_car_filled_rounded,
                      size: 22,
                      color: kBrandBlue,
                    ),
                  ],
                ),
              ),
            )
          else
            SizedBox(
              height: 146,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _vehicles.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final vehicle = _vehicles[index];
                  final isSelected = _selectedVehicle?.id == vehicle.id;
                  return _buildVehicleOptionCard(
                    vehicle: vehicle,
                    isSelected: isSelected,
                    onTap: () {
                      setState(() => _selectedVehicle = vehicle);
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVehicleOptionCard({
    required VehicleModel vehicle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 124,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: kWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? kTripGold : kTripBorder,
            width: isSelected ? 1.4 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/pngs/car_image.png',
              height: 46,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 8),
            Text(
              _vehicleTypeLabel(vehicle.vehicleType),
              style: kStyle(kSemiBold, kSize14, color: kTextColor),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Text(
              vehicle.vehicleNumber,
              style: kTripDurationPriceB.copyWith(fontSize: kSize13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Text(
              _vehicleSeaterLabel(vehicle.vehicleType),
              style: kTripDurationMetaR,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _vehicleTypeLabel(String vehicleType) {
    if (vehicleType.trim().isEmpty) return 'Vehicle';
    return vehicleType
        .split('_')
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
  }

  String _vehicleSeaterLabel(String vehicleType) {
    switch (vehicleType.toLowerCase()) {
      case 'suv':
        return '6 Seater';
      case 'premium':
        return '4 Seater';
      default:
        return '4 Seater';
    }
  }

  Future<void> _openScheduleSheet({bool openOnScheduleTab = false}) async {
    final result = await showScheduleBottomSheet(
      context,
      initialDateTime: scheduledRideAt,
      initialIsNow: openOnScheduleTab ? false : isRideNow,
    );

    if (!mounted) return;

    if (result == null) {
      if (openOnScheduleTab) {
        _mutateTripForm(() => isRideNow = scheduledRideAt == null);
      }
      return;
    }

    _mutateTripForm(() {
      isRideNow = result.isNow;
      scheduledRideAt = result.scheduledAt;
    });
  }

  /// ============================================================
  /// TRIP DETAILS
  /// ============================================================

  Widget _buildTripDetailsCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kWhite,
        borderRadius: BorderRadius.circular(kCardRadiusMd),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowLight,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Trip Details', style: kTripSectionTitleSB),

          const SizedBox(height: 16),

          Text('Trip type', style: kTripSubSectionSB),

          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _tripTypeChip(
                  label: 'Short Trip',
                  selected: isShortTrip,
                  onTap: () {
                    _mutateTripForm(() {
                      isShortTrip = true;
                      if (selectedHour < 1 || selectedHour > 7) {
                        selectedHour = 1;
                      }
                    }, userAdjustedDuration: true);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _tripTypeChip(
                  label: 'Long Trip',
                  selected: !isShortTrip,
                  onTap: () {
                    _mutateTripForm(() {
                      isShortTrip = false;
                      if (selectedHour != -1 && selectedHour < 8) {
                        selectedHour = 8;
                      }
                    }, userAdjustedDuration: true);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _routeInsightLabel,
            style: kTripDurationMetaR.copyWith(color: kMutedText),
          ),

          const SizedBox(height: 16),

          Text('Trip Duration', style: kTripSubSectionSB),

          const SizedBox(height: 12),

          RichText(
            text: TextSpan(
              style: kTripDurationMetaR.copyWith(color: kTextColor),
              children: [
                TextSpan(
                  text: '$_durationPriceLabel ',
                  style: kTripDurationPriceB,
                ),
                TextSpan(
                  text: 'Based on $_durationUsageLabel usage',
                  style: kTripDurationMetaR,
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          SizedBox(
            height: 62,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemBuilder: (context, index) {
                if (!isShortTrip && selectedHour == -1) {
                  if (index == 0) {
                    return GestureDetector(
                      onTap: _showCustomDurationBottomSheet,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: kTripGold),
                          color: kTripSelectedTint,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '$customDays Day • $customHours Hour',
                              style: kTripChipDurationSB,
                            ),
                          ],
                        ),
                      ),
                    );
                  } else {
                    return GestureDetector(
                      onTap: _showCustomDurationBottomSheet,
                      child: Container(
                        width: 48,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: kTripBorder),
                          color: kWhite,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              height: 20,
                              width: 20,
                              decoration: const BoxDecoration(
                                color: kTripCreamBg,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.add,
                                size: 14,
                                color: kTripIconMuted,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text('Custom', style: kTripChipCustomM),
                          ],
                        ),
                      ),
                    );
                  }
                }

                final isCustomOption = !isShortTrip && index == 6;
                final hour = isShortTrip ? (index + 1) : (index + 9);

                if (isCustomOption) {
                  final selected = selectedHour == -1;
                  return GestureDetector(
                    onTap: () {
                      _showCustomDurationBottomSheet();
                    },
                    child: Container(
                      width: 48,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected ? kTripGold : kTripBorder,
                        ),
                        color: kWhite,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            height: 20,
                            width: 20,
                            decoration: const BoxDecoration(
                              color: kTripCreamBg,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.add,
                              size: 14,
                              color: kTripIconMuted,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text('Custom', style: kTripChipCustomM),
                        ],
                      ),
                    ),
                  );
                }

                final selected = selectedHour == hour;

                return GestureDetector(
                  onTap: () {
                    _mutateTripForm(() {
                      selectedHour = hour;
                    }, userAdjustedDuration: true);
                  },
                  child: Container(
                    width: 42,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected ? kTripGold : kTripBorder,
                      ),
                      color: kWhite,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$hour',
                          style: selected
                              ? kTripChipHourB
                              : kTripChipHourMutedB,
                        ),
                        const SizedBox(height: 2),
                        Text('Hrs', style: kTripChipUnitM),
                      ],
                    ),
                  ),
                );
              },
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemCount: (!isShortTrip && selectedHour == -1) ? 2 : 7,
            ),
          ),

          if (_isDayBasedLongTrip) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _overnightOptionCard(
                    title: 'No Overnight Stay',
                    subtitle: 'Driver will not stay overnight',
                    isSelected: isOvernightStay == false,
                    onTap: () {
                      _mutateTripForm(() {
                        isOvernightStay = false;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _overnightOptionCard(
                    title: 'Driver Night stay required',
                    subtitle: 'Include driver\'s accommodation allowance',
                    isSelected: isOvernightStay == true,
                    onTap: () {
                      _mutateTripForm(() {
                        isOvernightStay = true;
                        if (selectedNight < 1) {
                          selectedNight = 1;
                        }
                      });
                    },
                  ),
                ),
              ],
            ),
            if (isOvernightStay == true) ...[
              const SizedBox(height: 24),
              Text('Stay Duration', style: kTripSubSectionSB),
              const SizedBox(height: 16),
              SizedBox(
                height: 74,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemBuilder: (context, index) {
                    if (selectedNight == -1) {
                      if (index == 0) {
                        return GestureDetector(
                          onTap: _showCustomStayDurationBottomSheet,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: kScreenPaddingH,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: kTripGold),
                              color: const Color(
                                0xFFFFFDF9,
                              ), // Very light golden tint
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '$customNights Night',
                                  style: kTripChipDurationSB,
                                ),
                              ],
                            ),
                          ),
                        );
                      } else {
                        return GestureDetector(
                          onTap: _showCustomStayDurationBottomSheet,
                          child: Container(
                            width: 74,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: kTripBorder),
                              color: kWhite,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  height: 24,
                                  width: 24,
                                  decoration: const BoxDecoration(
                                    color: kTripCreamBg,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.add,
                                    size: 16,
                                    color: kTripIconMuted,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text('Custom', style: kTripChipCustomM),
                              ],
                            ),
                          ),
                        );
                      }
                    }

                    if (index == 3) {
                      return GestureDetector(
                        onTap: _showCustomStayDurationBottomSheet,
                        child: Container(
                          width: 74,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: kTripBorder),
                            color: kWhite,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                height: 24,
                                width: 24,
                                decoration: const BoxDecoration(
                                  color: kTripCreamBg,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.add,
                                  size: 16,
                                  color: kTripIconMuted,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text('Custom', style: kTripChipCustomM),
                            ],
                          ),
                        ),
                      );
                    }

                    final night = index + 1;
                    final selected = selectedNight == night;

                    return GestureDetector(
                      onTap: () {
                        _mutateTripForm(() {
                          selectedNight = night;
                        });
                      },
                      child: Container(
                        width: 74,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: selected ? kTripGold : kTripBorder,
                          ),
                          color: kWhite,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '$night Night',
                              style: selected
                                  ? kTripChipDurationSB
                                  : kTripChipHourMutedB,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  separatorBuilder: (_, __) => const SizedBox(width: 14),
                  itemCount: selectedNight == -1 ? 2 : 4,
                ),
              ),
            ],
          ] else ...[
            const SizedBox(height: 10),
            Text('Includes waiting time', style: kTripWaitingNoteM),
          ],
        ],
      ),
    );
  }

  Widget _tripTypeChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? kTripSelectedTint : kWhite,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? kTripGold : kTripBorder),
        ),
        child: Text(
          label,
          style: selected ? kTripChipDurationSB : kTripSegmentInactiveM,
        ),
      ),
    );
  }

  Widget _overnightOptionCard({
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 85,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? kTripGold : kTripBorder),
          color: kWhite,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 2),
              height: 16,
              width: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? kTripGold : kTripRadioMuted,
                  width: isSelected ? 4 : 1.5,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(title, style: kTripOvernightTitleSB),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: kTripOvernightSubR,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ============================================================
  /// PROTECTION CARD
  /// ============================================================

  Widget _buildProtectionCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: kWhite,
        borderRadius: BorderRadius.circular(kCardRadiusMd),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowLight,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Trip Protection', style: kTripProtectionTitleSB),

                    const SizedBox(width: 10),

                    Text(
                      '+ ₹$_tripProtectionFee',
                      style: kTripProtectionAddonB,
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Covers accidents & emergencies during your ride',
                        style: kTripProtectionDescR,
                      ),
                    ),

                    Container(
                      height: 18,
                      width: 18,
                      decoration: const BoxDecoration(
                        color: AppColors.linkBlue,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          'i',
                          style: kCaption12R.copyWith(color: kWhite),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 14),

          Switch(
            value: isTripProtectionEnabled,
            activeColor: kWhite,
            activeTrackColor: kBrandBlue,
            onChanged: (value) {
              _mutateTripForm(() {
                isTripProtectionEnabled = value;
              });
            },
          ),
        ],
      ),
    );
  }

  /// ============================================================
  /// PAYMENT CARD
  /// ============================================================

  Widget _buildPaymentCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kWhite,
        borderRadius: BorderRadius.circular(kCardRadiusMd),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowLight,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Choose Payment Option', style: kTripSectionTitleSB),

          const SizedBox(height: 16),

          _paymentTile(
            title: 'Cash on Pay',
            subtitle: 'Pay the driver after your trip is completed.',
            trailingText: 'Pay after trip',
            isSelected: selectedPaymentIndex == 0,
            onTap: () {
              _mutateTripForm(() {
                selectedPaymentIndex = 0;
              });
            },
          ),

          const SizedBox(height: 10),

          _paymentTile(
            title: 'Pay Online Now',
            subtitle: 'Pay now and we will start searching driver for you.',
            isSelected: selectedPaymentIndex == 1,
            onTap: () {
              _mutateTripForm(() {
                selectedPaymentIndex = 1;
              });
            },
            trailingWidget: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_onlinePaymentTotalLabel, style: kTripPaymentPriceB),
                const SizedBox(width: 10),
                Icon(
                  selectedPaymentIndex == 1
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: kBrandBlue,
                ),
              ],
            ),
          ),
          if (selectedPaymentIndex == 1) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kTripSecureBannerBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_user_outlined, color: kActiveGreen),
                  const SizedBox(width: 10),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: kTripSecureBannerR,
                        children: [
                          TextSpan(
                            text: 'Secure payment. 100% safe & encrypted. ',
                            style: kTripSecureBannerB,
                          ),
                          const TextSpan(
                            text: 'UPI, Cards, Wallets & Net Banking accepted.',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _paymentTile({
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
    String? trailingText,
    Widget? trailingWidget,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? kTripGold : kTripBorder),
          color: kWhite,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 3),
              height: 18,
              width: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? kTripGold : kTripRadioMuted,
                  width: isSelected ? 4 : 1.5,
                ),
              ),
            ),

            const SizedBox(width: 10),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: kTripPaymentTitleSB),

                  const SizedBox(height: 4),

                  Text(subtitle, style: kTripPaymentSubtitleR),
                ],
              ),
            ),

            if (trailingText != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(trailingText, style: kTripPaymentTrailingR),
              ),

            if (trailingWidget != null) trailingWidget,
          ],
        ),
      ),
    );
  }

  void _showCustomDurationBottomSheet() async {
    final result = await showDialog<Map<String, int>>(
      context: context,
      builder: (context) {
        return Dialog(
          alignment: Alignment.bottomCenter,
          backgroundColor: kWhite,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          insetPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 24),
          child: _CustomDurationSheet(
            initialDays: customDays,
            initialHours: customHours,
          ),
        );
      },
    );

    if (result != null) {
      _mutateTripForm(() {
        selectedHour = -1;
        customDays = result['days']!;
        customHours = result['hours']!;
        if (customDays > 0) {
          isShortTrip = false;
          isOvernightStay = false;
          selectedNight = 1;
        } else if (customHours >= TripPlanService.longTripMinHours) {
          isShortTrip = false;
          isOvernightStay = null;
        }
      }, userAdjustedDuration: true);
    }
  }

  void _showCustomStayDurationBottomSheet() async {
    final result = await showDialog<int>(
      context: context,
      builder: (context) {
        return Dialog(
          alignment: Alignment.bottomCenter,
          backgroundColor: kWhite,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          insetPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 24),
          child: _CustomStayDurationSheet(initialNights: customNights),
        );
      },
    );

    if (result != null) {
      _mutateTripForm(() {
        selectedNight = -1; // -1 means custom
        customNights = result;
      });
    }
  }

  Future<void> _submitTripCreation() async {
    final userResponse = await ref.read(onboardingApiProvider).getMe();
    if (!userResponse.success || userResponse.data == null) {
      _showError(userResponse.message ?? 'Unable to load your profile.');
      return;
    }

    final activeCheck = await ref.read(tripApiProvider).findActiveOwnerTrip();
    if (!mounted) return;
    if (!activeCheck.success) {
      _showError(activeCheck.message ?? 'Unable to verify your active trips.');
      return;
    }
    final activeTrip = activeCheck.data;
    if (activeTrip != null) {
      final cleared = await resolveActiveTripBeforeBooking(
        context: context,
        activeTrip: activeTrip,
        ref: ref,
      );
      if (!mounted || !cleared) return;
    }

    final payloadResult = _buildTripPayload(userResponse.data!.userId);
    if (!payloadResult.success || payloadResult.data == null) {
      _showError(payloadResult.message ?? 'Please review trip details.');
      return;
    }

    await _fetchPriceEstimate();
    if (!mounted) return;

    final refreshedPayloadResult = _buildTripPayload(userResponse.data!.userId);
    if (!refreshedPayloadResult.success ||
        refreshedPayloadResult.data == null) {
      _showError(
        refreshedPayloadResult.message ?? 'Please review trip details.',
      );
      return;
    }

    setState(() => _isSubmitting = true);

    log('Create Trip Request Body: ${refreshedPayloadResult.data}');

    final createResponse = await ref
        .read(tripApiProvider)
        .createManualTrip(refreshedPayloadResult.data!);

    log('Create Trip Response Message: ${createResponse.message}');

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (!createResponse.success) {
      _showError(createResponse.message ?? 'Trip creation failed.');
      return;
    }

    final tripData = nestedData(createResponse.data) ?? createResponse.data;
    if (tripData == null) {
      _showError('Trip created but response was invalid.');
      return;
    }

    final trip = TripModel.fromJson(Map<String, dynamic>.from(tripData));

    if (!isRideNow && scheduledRideAt != null) {
      NavigationService().pushNamed(
        'trip_scheduled',
        arguments: _buildScheduledConfirmationArgs(
          trip: trip,
          scheduledAt: scheduledRideAt!,
        ),
      );
      return;
    }

    NavigationService().pushNamed(
      'booking_confirmed',
      arguments: trip.toWaitingDriverArguments(),
    );
  }

  Map<String, dynamic> _buildScheduledConfirmationArgs({
    required TripModel trip,
    required DateTime scheduledAt,
  }) {
    final args = trip.toScheduledDetailsArguments();
    args['scheduledAt'] = trip.pickupAt ?? scheduledAt;

    if (!trip.pickupLocation.hasAddress && _pickupLocation.hasAddress) {
      args['pickup'] = _pickupLocation.address;
    }
    if ((trip.dropoffAddress == null || trip.dropoffAddress!.isEmpty) &&
        _dropoffLocation != null &&
        _dropoffLocation!.hasAddress) {
      args['dropoff'] = _dropoffLocation!.address;
    }

    return args;
  }

  String _formatTimezoneOffset(DateTime dateTime) {
    final offset = dateTime.timeZoneOffset;
    final hours = offset.inHours.abs().toString().padLeft(2, '0');
    final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    final sign = offset.isNegative ? '-' : '+';
    return '$sign$hours:$minutes';
  }

  ApiResponse<Map<String, dynamic>> _buildTripPayload(String userId) {
    if (!_pickupLocation.hasAddress) {
      return ApiResponse.error('Please select pickup location.');
    }

    if (_dropoffLocation == null || !_dropoffLocation!.hasAddress) {
      return ApiResponse.error('Please select destination for this trip.');
    }

    if (_selectedVehicle == null || _selectedVehicle!.id.isEmpty) {
      return ApiResponse.error('Please add a vehicle before booking.');
    }

    if (!isRideNow && scheduledRideAt == null) {
      return ApiResponse.error('Select a schedule time for this trip.');
    }

    final duration = _resolveDuration();
    if (!duration.success || duration.data == null) {
      return ApiResponse.error(duration.message ?? 'Invalid trip duration.');
    }

    final overnight = _resolveOvernightStay(duration.data!);
    if (!overnight.success || overnight.data == null) {
      return ApiResponse.error(
        overnight.message ?? 'Invalid overnight stay details.',
      );
    }

    final payload = <String, dynamic>{
      'userId': userId,
      'tripDirection': isOneWay ? 'one_way' : 'round_trip',
      'pickupLocation': _pickupLocation.toJson(),
      if (_dropoffLocation != null)
        'dropoffLocation': _dropoffLocation!.toJson(),
      if (_routeSummary != null) 'routeSummary': _routeSummary!.toJson(),
      'tripType': isShortTrip ? 'short_trip' : 'long_trip',
      'rideTime': isRideNow ? 'now' : 'scheduled',
      'durationValue': duration.data!['durationValue'],
      'durationUnit': duration.data!['durationUnit'],
      if (duration.data!['additionalHours'] != null)
        'additionalHours': duration.data!['additionalHours'],
      'vehicleId': _selectedVehicle!.id,
      'assignmentType': 'auto_assign',
      'source': 'user_app',
      'tripProtection': {
        'enabled': isTripProtectionEnabled,
        'fee': isTripProtectionEnabled ? _tripProtectionFee : 0,
      },
      'paymentMethod': selectedPaymentIndex == 1 ? 'pay_online' : 'cash',
      if (_priceEstimate != null)
        'priceEstimate': _priceEstimate!.toPriceEstimatePayload()
      else
        'priceEstimate': {
          'currency': 'INR',
          'includesWaitingTime': isShortTrip,
        },
      'overnightStay': overnight.data,
    };

    if (!isRideNow && scheduledRideAt != null) {
      payload['pickupDate'] = _apiDateFormat.format(scheduledRideAt!);
      payload['pickupTime'] =
          '${_apiTimeFormat.format(scheduledRideAt!)}:00${_formatTimezoneOffset(scheduledRideAt!)}';
    }

    return ApiResponse.success(payload);
  }

  ApiResponse<Map<String, dynamic>> _resolveDuration() {
    if (isShortTrip) {
      if (selectedHour < 1 || selectedHour > 7) {
        return ApiResponse.error('Short trips must be between 1 and 7 hours.');
      }
      return ApiResponse.success({
        'durationValue': selectedHour,
        'durationUnit': 'hours',
      });
    }

    if (selectedHour == -1) {
      // Custom picker can set days and/or hours (e.g. 1 day + 13 hrs).
      if (customDays > 0 && customHours > 0) {
        return ApiResponse.success({
          'durationValue': customDays,
          'durationUnit': 'custom',
          'additionalHours': customHours,
        });
      }
      if (customDays > 0) {
        return ApiResponse.success({
          'durationValue': customDays,
          'durationUnit': 'days',
          'additionalHours': 0,
        });
      }
      if (customHours >= 8) {
        return ApiResponse.success({
          'durationValue': customHours,
          'durationUnit': 'hours',
          'additionalHours': 0,
        });
      }
      return ApiResponse.error(
        'Long custom trip must be at least 8 hours or 1 day.',
      );
    }

    if (selectedHour < 8) {
      return ApiResponse.error('Long trips must be 8+ hours.');
    }

    return ApiResponse.success({
      'durationValue': selectedHour,
      'durationUnit': 'hours',
    });
  }

  ApiResponse<Map<String, dynamic>> _resolveOvernightStay(
    Map<String, dynamic> resolvedDuration,
  ) {
    final unit = resolvedDuration['durationUnit']?.toString();
    final days = (resolvedDuration['durationValue'] as num?)?.toInt() ?? 0;
    final isDayBasedLongTrip = !isShortTrip &&
        (unit == 'days' || (unit == 'custom' && days >= 1));
    final overnightRequired = isDayBasedLongTrip && isOvernightStay == true;

    if (!overnightRequired) {
      return ApiResponse.success({'required': false, 'nights': null});
    }

    final nights = selectedNight == -1 ? customNights : selectedNight;
    if (nights < 1) {
      return ApiResponse.error('Overnight stay requires at least 1 night.');
    }

    return ApiResponse.success({'required': true, 'nights': nights});
  }

  void _showError(String message) {
    if (!mounted) return;
    showAppSnackBar(context, message);
  }

  Future<void> _pickPickupLocation() async {
    final result = await NavigationService().pushNamed(
      'search_location',
      arguments: {
        'title': 'Where are you leaving from?',
        'showCurrentLocation': true,
      },
    );

    final selectedLocation = _extractLocationFromSelection(result);
    if (selectedLocation == null || !selectedLocation.hasAddress || !mounted) {
      return;
    }

    setState(() {
      _hasUserSetPickup = true;
      _isLoadingPickup = false;
      _pickupLocation = selectedLocation;
      _hasUserAdjustedDuration = false;
    });
    _scheduleRouteRefresh();
  }

  Future<void> _pickDropoffLocation() async {
    final result = await NavigationService().pushNamed(
      'search_location',
      arguments: {
        'title': isOneWay ? 'Where are you heading?' : 'Where are you going?',
        'showCurrentLocation': false,
      },
    );

    final selectedLocation = _extractLocationFromSelection(result);
    if (selectedLocation == null || !selectedLocation.hasAddress || !mounted) {
      return;
    }

    setState(() {
      _dropoffLocation = selectedLocation;
      _hasUserAdjustedDuration = false;
    });
    _scheduleRouteRefresh();
  }

  TripLocation? _extractLocationFromSelection(dynamic result) {
    if (result is TripLocation) return result;
    if (result is Map) return TripLocation.fromDynamic(result);
    if (result is String) {
      final address = result.trim();
      if (address.isEmpty) return null;
      return TripLocation.fromAddress(address);
    }
    return null;
  }

  Future<void> _openAddVehicleSheet() async {
    final addedVehicle = await showAddVehicleBottomSheet(context);
    if (!mounted) return;

    await _loadVehicles(selectVehicle: addedVehicle);
  }
}

class _CustomDurationSheet extends StatefulWidget {
  final int initialDays;
  final int initialHours;

  const _CustomDurationSheet({
    required this.initialDays,
    required this.initialHours,
  });

  @override
  State<_CustomDurationSheet> createState() => _CustomDurationSheetState();
}

class _CustomDurationSheetState extends State<_CustomDurationSheet> {
  late int selectedDays;
  late int selectedHours;
  late FixedExtentScrollController _daysController;
  late FixedExtentScrollController _hoursController;

  @override
  void initState() {
    super.initState();
    selectedDays = widget.initialDays;
    selectedHours = widget.initialHours;
    _daysController = FixedExtentScrollController(initialItem: selectedDays);
    _hoursController = FixedExtentScrollController(initialItem: selectedHours);
  }

  @override
  void dispose() {
    _daysController.dispose();
    _hoursController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 400,
      padding: const EdgeInsets.only(left: 24, right: 24, top: 28, bottom: 24),
      decoration: BoxDecoration(
        color: kWhite,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Select Custom Duration', style: kTripModalTitleSB),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: kTripCloseBtnBg,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Center(
            child: RichText(
              text: TextSpan(
                style: kTripModalSummaryR,
                children: [
                  const TextSpan(text: 'Trip Duration:  '),
                  TextSpan(
                    text: '$selectedDays Day • $selectedHours Hour',
                    style: kTripModalSummaryB,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 120,
                  child: CupertinoPicker.builder(
                    scrollController: _daysController,
                    itemExtent: 54,
                    selectionOverlay: Container(
                      decoration: const BoxDecoration(
                        border: Border.symmetric(
                          horizontal: BorderSide(color: kBrandBlue, width: 1.5),
                        ),
                      ),
                    ),
                    childCount: 30, // 0 to 29 days
                    onSelectedItemChanged: (index) {
                      setState(() {
                        selectedDays = index;
                      });
                    },
                    itemBuilder: (context, index) {
                      final isSelected = index == selectedDays;
                      return Center(
                        child: Text(
                          '$index Day',
                          style: isSelected
                              ? kTripPickerSelectedM
                              : kTripPickerUnselectedM,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 32),
                SizedBox(
                  width: 120,
                  child: CupertinoPicker.builder(
                    scrollController: _hoursController,
                    itemExtent: 54,
                    selectionOverlay: Container(
                      decoration: const BoxDecoration(
                        border: Border.symmetric(
                          horizontal: BorderSide(color: kBrandBlue, width: 1.5),
                        ),
                      ),
                    ),
                    childCount: 24, // 0 to 23 hours
                    onSelectedItemChanged: (index) {
                      setState(() {
                        selectedHours = index;
                      });
                    },
                    itemBuilder: (context, index) {
                      final isSelected = index == selectedHours;
                      final hrStr = index == 0
                          ? '0'
                          : index.toString().padLeft(2, '0');
                      return Center(
                        child: Text(
                          '$hrStr hrs',
                          style: isSelected
                              ? kTripPickerSelectedM
                              : kTripPickerUnselectedM,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          GestureDetector(
            onTap: () {
              Navigator.pop(context, {
                'days': selectedDays,
                'hours': selectedHours,
              });
            },
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                color: kTripCtaBlue,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Center(
                child: Text('Apply Duration', style: kTripModalButtonM),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomStayDurationSheet extends StatefulWidget {
  final int initialNights;

  const _CustomStayDurationSheet({required this.initialNights});

  @override
  State<_CustomStayDurationSheet> createState() =>
      _CustomStayDurationSheetState();
}

class _CustomStayDurationSheetState extends State<_CustomStayDurationSheet> {
  late int selectedNights;

  @override
  void initState() {
    super.initState();
    selectedNights = widget.initialNights;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 24, right: 24, top: 28, bottom: 24),
      decoration: BoxDecoration(
        color: kWhite,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Stay Duration', style: kTripStaySheetTitleSB),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: kTripCloseBtnBg,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 36),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () {
                  if (selectedNights > 1) {
                    setState(() {
                      selectedNights--;
                    });
                  }
                },
                child: Container(
                  height: 52,
                  width: 52,
                  decoration: BoxDecoration(
                    color: kScreenBg,
                    borderRadius: BorderRadius.circular(kCardRadiusMd),
                  ),
                  child: const Icon(Icons.remove, size: 28, color: kTextColor),
                ),
              ),
              Text(
                '$selectedNights Night${selectedNights > 1 ? 's' : ''}',
                style: kTripStayCounterB,
              ),
              GestureDetector(
                onTap: () {
                  setState(() {
                    selectedNights++;
                  });
                },
                child: Container(
                  height: 52,
                  width: 52,
                  decoration: BoxDecoration(
                    color: kScreenBg,
                    borderRadius: BorderRadius.circular(kCardRadiusMd),
                  ),
                  child: const Icon(Icons.add, size: 28, color: kTextColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 48),
          GestureDetector(
            onTap: () {
              Navigator.pop(context, selectedNights);
            },
            child: Container(
              height: 58,
              decoration: BoxDecoration(
                color: kTripCtaBlue,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Center(
                child: Text('Confirm Stay Duration', style: kTripModalButtonM),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TripDirectionToggle extends StatelessWidget {
  final bool isOneWay;
  final VoidCallback onOneWayTap;
  final VoidCallback onRoundTripTap;

  const _TripDirectionToggle({
    required this.isOneWay,
    required this.onOneWayTap,
    required this.onRoundTripTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: kSegmentTrackCream,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TripDirectionSegment(
              label: 'One Way',
              selected: isOneWay,
              onTap: onOneWayTap,
              icon: _OneWayTripIcon(color: isOneWay ? kWhite : kTextColor),
            ),
          ),
          Expanded(
            child: _TripDirectionSegment(
              label: 'Round Trip',
              selected: !isOneWay,
              onTap: onRoundTripTap,
              icon: Icon(
                Icons.sync,
                size: 16,
                color: !isOneWay ? kWhite : kTextColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TripDirectionSegment extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget icon;

  const _TripDirectionSegment({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: selected ? kSegmentActiveBrown : Colors.transparent,
          borderRadius: BorderRadius.circular(21),
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              const SizedBox(width: 4),
              Text(
                label,
                style: selected ? kTripSegmentActiveM : kTripSegmentInactiveM,
                maxLines: 1,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OneWayTripIcon extends StatelessWidget {
  final Color color;

  const _OneWayTripIcon({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 12,
      child: Row(
        children: [
          Container(
            width: 10,
            height: 1.5,
            margin: const EdgeInsets.only(right: 1),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          Icon(Icons.arrow_right, size: 14, color: color),
        ],
      ),
    );
  }
}
