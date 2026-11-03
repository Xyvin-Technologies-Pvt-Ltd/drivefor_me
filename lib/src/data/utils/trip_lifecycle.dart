import 'package:DriveForme/src/data/apis/trip_api.dart';
import 'package:DriveForme/src/data/models/trip_model.dart';
import 'package:DriveForme/src/data/providers/active_trip_provider.dart';
import 'package:DriveForme/src/data/services/navigation_services.dart';
import 'package:DriveForme/src/data/services/secure_storage_service.dart';
import 'package:DriveForme/src/data/services/snackbar_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens create-trip only when the owner has no active booking.
/// Returns `true` if navigation happened.
Future<bool> navigateToCreateTripIfAllowed({
  required BuildContext context,
  WidgetRef? ref,
}) async {
  final tripApi = ref != null
      ? ref.read(tripApiProvider)
      : ProviderScope.containerOf(context).read(tripApiProvider);
  final response = await tripApi.findActiveOwnerTrip();
  if (!context.mounted) return false;

  if (!response.success) {
    await _showMessageDialog(
      context,
      response.message ?? 'Unable to verify your active trips.',
    );
    return false;
  }

  final activeTrip = response.data;
  if (activeTrip != null) {
    final cleared = await resolveActiveTripBeforeBooking(
      context: context,
      activeTrip: activeTrip,
      ref: ref,
    );
    if (!context.mounted || !cleared) return false;
  }

  NavigationService().pushNamed('create_trip');
  return true;
}

String _formatChargeAmount(num? amount) {
  final value = (amount ?? 0).toDouble();
  if (value <= 0) return '₹ 0';
  return '₹ ${value.toStringAsFixed(0)}';
}

Future<bool> showCancelTripDialog(
  BuildContext context, {
  String? chargeMessage,
  double chargeAmount = 0,
}) async {
  final chargeLine = chargeAmount > 0
      ? 'Cancellation charge: ${_formatChargeAmount(chargeAmount)} will be deducted from your wallet.'
      : (chargeMessage?.trim().isNotEmpty == true
          ? chargeMessage!.trim()
          : 'No cancellation charge at this stage.');

  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Cancel ride?'),
      content: Text(
        'Are you sure you want to cancel this trip?\n\n$chargeLine',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep ride'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Cancel ride'),
        ),
      ],
    ),
  );
  return result == true;
}

String _activeTripPhrase(TripModel trip) {
  switch (trip.status) {
    case 'in_progress':
      return 'in progress';
    case 'pending_assignment':
      return 'waiting for a driver';
    case 'driver_assigned':
      return 'assigned to a driver';
    case 'scheduled':
      return 'scheduled';
    default:
      return trip.upcomingStatusLabel().toLowerCase();
  }
}

/// Explains the booking that is blocking a new one.
/// Returns true when that booking was cancelled.
Future<bool> resolveActiveTripBeforeBooking({
  required BuildContext context,
  required TripModel activeTrip,
  WidgetRef? ref,
}) async {
  final number = activeTrip.tripNumber.isNotEmpty
      ? activeTrip.tripNumber
      : activeTrip.displayTripId;
  final choice = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Active trip'),
      content: Text(
        'Trip $number is still ${_activeTripPhrase(activeTrip)}. '
        'Cancel it before booking a new one.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop('close'),
          child: const Text('Close'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop('cancel'),
          child: const Text('Cancel trip'),
        ),
      ],
    ),
  );

  if (choice != 'cancel' || !context.mounted) return false;

  final cancelled = await cancelTripWithDialog(
    context: context,
    ref: ref,
    tripMongoId: activeTrip.id,
    reason: 'Cancelled to book a new trip',
  );
  return cancelled != null;
}

Future<void> _showMessageDialog(BuildContext context, String message) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

TripApi _tripApi(BuildContext context, WidgetRef? ref) {
  if (ref != null) return ref.read(tripApiProvider);
  return ProviderScope.containerOf(context).read(tripApiProvider);
}

SecureStorageService _storage(BuildContext context, WidgetRef? ref) {
  if (ref != null) return ref.read(secureStorageServiceProvider);
  return ProviderScope.containerOf(context).read(secureStorageServiceProvider);
}

ActiveTripNotifier _activeTrips(BuildContext context, WidgetRef? ref) {
  if (ref != null) return ref.read(activeTripProvider.notifier);
  return ProviderScope.containerOf(context).read(activeTripProvider.notifier);
}

Future<TripModel?> cancelTripWithDialog({
  required BuildContext context,
  WidgetRef? ref,
  required String tripMongoId,
  String? reason,
}) async {
  if (tripMongoId.isEmpty) return null;

  final tripApi = _tripApi(context, ref);

  double previewAmount = 0;
  String? previewMessage;
  final preview = await tripApi.previewCancellationCharges(tripMongoId);
  if (preview.success && preview.data != null) {
    previewAmount =
        (preview.data!['customerChargeAmount'] as num?)?.toDouble() ?? 0;
    previewMessage = preview.data!['message']?.toString();
    if (preview.data!['allowed'] == false) {
      if (context.mounted) {
        await _showMessageDialog(
          context,
          previewMessage ?? 'Cancellation is not allowed at this stage.',
        );
      }
      return null;
    }
  }

  if (!context.mounted) return null;

  final confirmed = await showCancelTripDialog(
    context,
    chargeMessage: previewMessage,
    chargeAmount: previewAmount,
  );
  if (!confirmed || !context.mounted) return null;

  final storage = _storage(context, ref);
  final activeTrips = _activeTrips(context, ref);
  final response = await tripApi.cancelTrip(
    tripMongoId,
    reason: reason ?? 'Cancelled by vehicle owner',
  );

  if (!context.mounted) return null;

  if (!response.success) {
    await _showMessageDialog(
      context,
      response.message ?? 'Failed to cancel trip.',
    );
    return null;
  }

  await storage.clearActiveTripId();
  activeTrips.clear();

  final trip = response.data;
  if (trip != null && trip.hasCancellationCharge && context.mounted) {
    await _showMessageDialog(
      context,
      response.message ??
          'Trip cancelled. Cancellation charge: ${trip.cancellationChargeDisplay}.',
    );
  }

  return trip;
}

Future<void> navigateAfterTripCancelled(
  Map<String, dynamic> cancelledArguments,
) async {
  NavigationService().resetToNavbarThenPush(
    'cancelled_trip_details',
    arguments: cancelledArguments,
  );
}

Future<void> navigateAfterDriverReassigned({
  required TripModel trip,
  String? message,
}) async {
  final context = NavigationService.navigatorKey.currentContext;
  if (context != null && context.mounted) {
    showAppSnackBar(
      context,
      message ??
          'Your driver cancelled. Finding another driver nearby...',
    );
  }

  NavigationService().pushNamedReplacement(
    'waiting_driver',
    arguments: trip.toWaitingDriverArguments(),
  );
}

void openChatScreen({
  required String receiverId,
  required String receiverName,
  String? tripId,
}) {
  if (receiverId.isEmpty) return;
  NavigationService().pushNamed(
    'chat_screen',
    arguments: {
      'receiverId': receiverId,
      'receiverName': receiverName,
      if (tripId != null && tripId.isNotEmpty) 'tripId': tripId,
      'participantName': receiverName,
    },
  );
}
