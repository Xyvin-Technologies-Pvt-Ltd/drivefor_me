import 'package:DriveForme/src/data/apis/vehicle_api.dart';
import 'package:DriveForme/src/data/constants/colour_constants.dart';
import 'package:DriveForme/src/data/constants/style_constants.dart';
import 'package:DriveForme/src/data/models/vehicle_model.dart';
import 'package:DriveForme/src/interfaces/components/add_vehicle_sheet.dart';
import 'package:DriveForme/src/data/services/snackbar_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MyVehiclesPage extends ConsumerStatefulWidget {
  const MyVehiclesPage({super.key});

  @override
  ConsumerState<MyVehiclesPage> createState() => _MyVehiclesPageState();
}

class _MyVehiclesPageState extends ConsumerState<MyVehiclesPage> {
  List<VehicleModel> _vehicles = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadVehicles();
  }

  Future<void> _loadVehicles() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final response = await ref.read(vehicleApiProvider).getMyVehicles();
    if (!mounted) return;

    if (!response.success) {
      setState(() {
        _isLoading = false;
        _error = response.message ?? 'Failed to load vehicles.';
      });
      return;
    }

    setState(() {
      _isLoading = false;
      _vehicles = response.data ?? [];
    });
  }

  Future<void> _addVehicle() async {
    final added = await showAddVehicleBottomSheet(context);
    if (!mounted || added == null) return;
    await _loadVehicles();
  }

  Future<void> _confirmDelete(VehicleModel vehicle) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove vehicle?'),
        content: Text(
          'Remove ${vehicle.vehicleName} (${vehicle.vehicleNumber}) from your account?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final response =
        await ref.read(vehicleApiProvider).deleteVehicle(vehicle.id);
    if (!mounted) return;

    if (!response.success) {
      showAppSnackBar(
        context,
        response.message ?? 'Failed to delete vehicle.',
      );
      return;
    }

    await _loadVehicles();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kScreenBg,
      appBar: AppBar(
        backgroundColor: kWhite,
        surfaceTintColor: kWhite,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(
            Icons.arrow_back_ios_new,
            size: 22,
            color: kTextColor,
          ),
        ),
        title: Text(
          'My Vehicles',
          style: kStyle(kSemiBold, kSize18, color: kTextColor),
        ),
        titleSpacing: 0,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addVehicle,
        backgroundColor: kBrandBlue,
        child: const Icon(Icons.add, color: kWhite),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: kBrandBlue));
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              TextButton(onPressed: _loadVehicles, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    if (_vehicles.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'No vehicles added yet.',
                style: kStyle(kRegular, kSize15, color: kMutedText),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _addVehicle,
                child: const Text('Add a vehicle'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadVehicles,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 88),
        itemCount: _vehicles.length,
        separatorBuilder: (_, _) => const SizedBox(height: 14),
        itemBuilder: (context, index) {
          final vehicle = _vehicles[index];
          return _VehicleCard(
            vehicle: vehicle,
            onDelete: () => _confirmDelete(vehicle),
          );
        },
      ),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  final VehicleModel vehicle;
  final VoidCallback onDelete;

  const _VehicleCard({required this.vehicle, required this.onDelete});

  String get _transmissionLabel {
    if (vehicle.transmission.isEmpty) return '—';
    return vehicle.transmission
        .split('_')
        .map(
          (part) => part.isEmpty
              ? part
              : '${part[0].toUpperCase()}${part.substring(1)}',
        )
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kWhite,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kTripBorder, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Image.asset(
            'assets/pngs/car_image.png',
            width: 96,
            height: 52,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vehicle.vehicleName,
                  style: kStyle(
                    kSemiBold,
                    kSize16,
                    color: kTextColor,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  vehicle.vehicleNumber,
                  style: kTripDurationPriceB,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _transmissionLabel,
                  style: kStyle(
                    kRegular,
                    kSize14,
                    color: kMutedText,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onDelete,
              borderRadius: BorderRadius.circular(20),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.delete_outline, color: kRed, size: 26),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
