import 'package:DriveForme/src/data/models/trip_model.dart';

class TripNavigationTarget {
  final String route;
  final Map<String, dynamic> arguments;

  const TripNavigationTarget({
    required this.route,
    required this.arguments,
  });
}

const _activeTripStatuses = {
  'pre_booked',
  'awaiting_pre_auth_window',
  'requires_admin_call',
  'call_completed_pending_auth',
  'pre_authorized',
  'confirmed',
  'pending_assignment',
  'scheduled',
  'driver_assigned',
  'in_progress',
};

bool isActiveTripStatus(String status) => _activeTripStatuses.contains(status);

/// Returns the route + args for resuming or transitioning based on trip status.
TripNavigationTarget? tripNavigationTarget(TripModel trip) {
  switch (trip.status) {
    case 'pre_booked':
    case 'awaiting_pre_auth_window':
    case 'requires_admin_call':
    case 'call_completed_pending_auth':
    case 'pre_authorized':
    case 'confirmed':
    case 'pending_assignment':
      if (trip.isFutureScheduled || trip.hasAssignedDriver) {
        return TripNavigationTarget(
          route: 'scheduled_trip_details',
          arguments: trip.toScheduledDetailsArguments(),
        );
      }
      return TripNavigationTarget(
        route: 'waiting_driver',
        arguments: trip.toWaitingDriverArguments(),
      );
    case 'scheduled':
      // Driver accepted early — show scheduled details with driver info.
      if (trip.hasAssignedDriver) {
        return TripNavigationTarget(
          route: 'scheduled_trip_details',
          arguments: trip.toScheduledDetailsArguments(),
        );
      }
      return TripNavigationTarget(
        route: 'waiting_driver',
        arguments: trip.toWaitingDriverArguments(),
      );
    case 'driver_assigned':
      // Legacy / edge: assigned before pickup on a scheduled ride.
      if (trip.isFutureScheduled) {
        return TripNavigationTarget(
          route: 'scheduled_trip_details',
          arguments: trip.toScheduledDetailsArguments(),
        );
      }
      return TripNavigationTarget(
        route: 'driver_found',
        arguments: trip.toDriverFoundArguments(),
      );
    case 'in_progress':
      return TripNavigationTarget(
        route: 'trip_progress',
        arguments: trip.toProgressArguments(),
      );
    case 'completed':
      if (trip.isRated) return null;
      return TripNavigationTarget(
        route: 'trip_completed',
        arguments: trip.toTripCompletedArguments(),
      );
    case 'cancelled':
      return null;
    default:
      return null;
  }
}
