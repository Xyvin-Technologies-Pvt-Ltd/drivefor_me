import 'package:DriveForme/src/interfaces/components/vehicle_document_field.dart';
import 'package:DriveForme/src/data/constants/colour_constants.dart';
import 'package:DriveForme/src/data/constants/style_constants.dart';
import 'package:DriveForme/src/data/apis/vehicle_api.dart';
import 'package:DriveForme/src/data/models/vehicle_model.dart';
import 'package:DriveForme/src/data/services/navigation_services.dart';
import 'package:DriveForme/src/data/services/secure_storage_service.dart';
import 'package:DriveForme/src/interfaces/components/input_field.dart';
import 'package:DriveForme/src/data/services/snackbar_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<VehicleModel?> showAddVehicleBottomSheet(BuildContext context) {
  return showModalBottomSheet<VehicleModel>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return UncontrolledProviderScope(
        container: ProviderScope.containerOf(sheetContext, listen: false),
        child: const AddVehicleBottomSheet(),
      );
    },
  );
}

class AddVehicleBottomSheet extends ConsumerStatefulWidget {
  const AddVehicleBottomSheet({super.key});

  @override
  ConsumerState<AddVehicleBottomSheet> createState() =>
      _AddVehicleBottomSheetState();
}

class _AddVehicleBottomSheetState extends ConsumerState<AddVehicleBottomSheet> {
  final Map<String, String> _documentUrls = {};
  final Set<String> _busyDocuments = {};
  bool get _busy => _isSubmitting || _busyDocuments.isNotEmpty;

  String transmission = 'Manual';
  int selectedVehicle = -1;
  bool _isSubmitting = false;
  bool _isLoadingTypes = true;

  final TextEditingController nameController = TextEditingController();
  final TextEditingController numberController = TextEditingController();

  static const _fallbackVehicleTypes = [
    {'label': 'Hatchback', 'value': 'hatchback'},
    {'label': 'Sedan', 'value': 'sedan'},
    {'label': 'SUV', 'value': 'suv'},
    {'label': 'Premium', 'value': 'premium'},
  ];

  List<Map<String, String>> vehicleTypes = List.of(_fallbackVehicleTypes);

  bool get _isFormValid {
    return _documentUrls.length == 3 &&
        !_busy &&
        nameController.text.trim().isNotEmpty &&
        numberController.text.trim().isNotEmpty &&
        transmission.isNotEmpty &&
        selectedVehicle >= 0 &&
        selectedVehicle < vehicleTypes.length;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadVehicleTypes());
    nameController.addListener(_onInputChanged);
    numberController.addListener(_onInputChanged);
  }

  void _onInputChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    nameController.removeListener(_onInputChanged);
    numberController.removeListener(_onInputChanged);
    nameController.dispose();
    numberController.dispose();
    super.dispose();
  }

  Future<void> _loadVehicleTypes() async {
    final token = await ref.read(secureStorageServiceProvider).getAuthToken();
    if (token == null || token.isEmpty) {
      if (mounted) {
        setState(() => _isLoadingTypes = false);
        _showMessage('Please log in again to add a vehicle.');
      }
      return;
    }

    final response = await ref.read(vehicleApiProvider).getVehicleTypes();
    if (!mounted) return;

    if (response.success && response.data != null) {
      final backendTypes = response.data!['vehicleTypes'] ?? const <String>[];
      if (backendTypes.isNotEmpty) {
        vehicleTypes = backendTypes
            .map((type) => {'label': _labelForVehicleType(type), 'value': type})
            .toList();
      }
    }

    setState(() {
      _isLoadingTypes = false;
      selectedVehicle = -1;
    });
  }

  String _labelForVehicleType(String value) {
    return value
        .split('_')
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * .80,
      decoration: const BoxDecoration(
        color: kWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Add Vehicle',
                    style: kStyle(kSemiBold, 20, color: kTextColor),
                  ),
                ),
                GestureDetector(
                  onTap: _busy ? null : () => Navigator.pop(context),
                  child: Container(
                    height: 44,
                    width: 44,
                    decoration: const BoxDecoration(
                      color: kTripCloseBtnBg,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, size: 24, color: kTextColor),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Expanded(
            child: _isLoadingTypes
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Vehicle Name *',
                          style: kStyle(kSemiBold, 16, color: kTextColor),
                        ),
                        const SizedBox(height: 14),
                        InputField(
                          type: CustomFieldType.text,
                          hint: 'Enter Your Vehicle Name',
                          controller: nameController,
                        ),
                        const SizedBox(height: 28),
                        Text(
                          'Vehicle Number *',
                          style: kStyle(kSemiBold, 16, color: kTextColor),
                        ),
                        const SizedBox(height: 14),
                        InputField(
                          type: CustomFieldType.text,
                          hint: 'Enter Your Vehicle Number',
                          controller: numberController,
                        ),
                        const SizedBox(height: 28),
                        Text(
                          'Transmission *',
                          style: kStyle(kSemiBold, 14, color: kTextColor),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            _radioButton(
                              title: 'Manual',
                              selected: transmission == 'Manual',
                              onTap: () =>
                                  setState(() => transmission = 'Manual'),
                            ),
                            const SizedBox(width: 32),
                            _radioButton(
                              title: 'Automatic',
                              selected: transmission == 'Automatic',
                              onTap: () =>
                                  setState(() => transmission = 'Automatic'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),
                        Text(
                          'Vehicle Type *',
                          style: kStyle(kSemiBold, 14, color: kTextColor),
                        ),
                        const SizedBox(height: 20),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: vehicleTypes.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 14,
                                mainAxisSpacing: 14,
                                childAspectRatio: 1.2,
                              ),
                          itemBuilder: (context, index) {
                            final selected = selectedVehicle == index;
                            return GestureDetector(
                              onTap: () =>
                                  setState(() => selectedVehicle = index),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: kWhite,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: selected ? kTripGold : kTripBorder,
                                    width: selected ? 1.5 : 1,
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Image.asset(
                                      'assets/pngs/car_image.png',
                                      height: 50,
                                      fit: BoxFit.contain,
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      vehicleTypes[index]['label'] ?? '',
                                      style: kStyle(
                                        kSemiBold,
                                        12,
                                        color: kTextColor,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Vehicle documents',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Upload clear photos of your RC, insurance and PUC. Expiry dates are read automatically.',
                        ),
                        for (final entry in const {
                          'registration': 'Registration Certificate (RC)',
                          'insurance': 'Insurance',
                          'pollution': 'Pollution Certificate (PUC)',
                        }.entries)
                          VehicleDocumentField(
                            key: ValueKey(entry.key),
                            type: entry.key,
                            label: entry.value,
                            enabled: !_busy,
                            onChanged: (url) => setState(() {
                              if (url == null) {
                                _documentUrls.remove(entry.key);
                              } else {
                                _documentUrls[entry.key] = url;
                              }
                            }),
                            onBusyChanged: (busy) => setState(() {
                              if (busy) {
                                _busyDocuments.add(entry.key);
                              } else {
                                _busyDocuments.remove(entry.key);
                              }
                            }),
                          ),
                        const SizedBox(height: 40),
                        GestureDetector(
                          onTap: _isFormValid ? _submitVehicle : null,
                          child: Opacity(
                            opacity: _isSubmitting ? 0.7 : 1,
                            child: Container(
                              height: 64,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: _isFormValid
                                    ? kBrandBlue
                                    : kTripDestIconBg,
                                borderRadius: BorderRadius.circular(32),
                              ),
                              child: Center(
                                child: _isSubmitting
                                    ? const SizedBox(
                                        height: 22,
                                        width: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: kWhite,
                                        ),
                                      )
                                    : Text(
                                        'Add vehicle Details',
                                        style: kStyle(
                                          kSemiBold,
                                          16,
                                          color: _isFormValid
                                              ? kWhite
                                              : kMutedText,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _radioButton({
    required String title,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 22,
            width: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? kTripGold : kTripBorder,
                width: selected ? 6 : 1.5,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(title, style: kStyle(kSemiBold, 14, color: kTextColor)),
        ],
      ),
    );
  }

  Future<void> _submitVehicle() async {
    if (!_isFormValid) return;
    final vehicleName = nameController.text.trim();
    final vehicleNumber = numberController.text.trim().toUpperCase();

    if (vehicleName.isEmpty) {
      _showMessage('Vehicle name is required.');
      return;
    }

    if (vehicleNumber.isEmpty) {
      _showMessage('Vehicle number is required.');
      return;
    }

    if (selectedVehicle == -1) {
      _showMessage('Please select a vehicle type.');
      return;
    }

    final vehicleType = vehicleTypes[selectedVehicle]['value'] ?? 'hatchback';
    final transmissionValue = transmission.toLowerCase() == 'automatic'
        ? 'automatic'
        : 'manual';

    final token = await ref.read(secureStorageServiceProvider).getAuthToken();
    if (!mounted) return;
    if (token == null || token.isEmpty) {
      _showMessage('Session expired. Please log in again.');
      return;
    }

    setState(() => _isSubmitting = true);

    final createResponse = await ref
        .read(vehicleApiProvider)
        .createVehicle(
          vehicleName: vehicleName,
          vehicleNumber: vehicleNumber,
          vehicleType: vehicleType,
          transmission: transmissionValue,
          registrationUrl: _documentUrls['registration']!,
          insuranceUrl: _documentUrls['insurance']!,
          pollutionUrl: _documentUrls['pollution']!,
        );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (!createResponse.success || createResponse.data == null) {
      _showMessage(createResponse.message ?? 'Failed to add vehicle.');
      return;
    }

    _showMessage('Vehicle added successfully.');
    Navigator.pop(context, createResponse.data);
  }

  void _showMessage(String message) {
    final rootContext = NavigationService.navigatorKey.currentContext;
    if (rootContext == null) return;
    showAppSnackBar(rootContext, message);
  }
}
