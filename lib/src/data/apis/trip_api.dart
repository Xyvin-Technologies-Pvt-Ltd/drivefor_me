import 'package:DriveForme/src/data/models/api_response.dart';
import 'package:DriveForme/src/data/models/trip_model.dart';
import 'package:DriveForme/src/data/providers/api_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TripApi {
  final ApiProvider _api;

  TripApi(this._api);

  Future<ApiResponse<Map<String, dynamic>>> createManualTrip(
    Map<String, dynamic> payload,
  ) {
    return _api.post('/trips/manual', payload, requireAuth: true);
  }

  Future<ApiResponse<List<TripModel>>> listOngoingTrips() async {
    final response = await _listTrips(
      queryParams: {'statuses': activeOwnerTripStatuses},
    );
    if (!response.success) {
      return ApiResponse.error(
        response.message ?? 'Failed to load trips.',
        response.statusCode,
      );
    }
    final trips = (response.data ?? const <TripModel>[])
        .where((trip) => trip.isActiveBooking)
        .toList();
    return ApiResponse.success(trips, response.statusCode);
  }

  Future<ApiResponse<List<TripModel>>> listCompletedTrips() {
    return _listTrips(status: 'completed');
  }

  Future<ApiResponse<List<TripModel>>> listCancelledTrips() {
    return _listTrips(status: 'cancelled');
  }

  /// Any non-completed / non-cancelled trip that blocks a new booking.
  static final activeOwnerTripStatuses =
      TripModel.activeBookingStatuses.join(',');

  Future<ApiResponse<TripModel?>> findActiveOwnerTrip() async {
    final response = await _listTrips(
      queryParams: {'statuses': activeOwnerTripStatuses},
    );

    if (!response.success) {
      return ApiResponse.error(
        response.message ?? 'Failed to check active trips.',
        response.statusCode,
      );
    }

    final trips = (response.data ?? const <TripModel>[])
        .where((trip) => trip.isActiveBooking)
        .toList();
    if (trips.isEmpty) {
      return ApiResponse.success(null, response.statusCode);
    }
    return ApiResponse.success(trips.first, response.statusCode);
  }

  Future<ApiResponse<List<TripModel>>> listUpcomingTrips() async {
    // Backend `status=upcoming` maps to non-terminal booking statuses only.
    final response = await _listTrips(status: 'upcoming');

    if (!response.success) {
      return ApiResponse.error(
        response.message ?? 'Failed to load upcoming trips.',
        response.statusCode,
      );
    }

    final trips = List<TripModel>.from(response.data ?? const [])
        .where((trip) => !trip.isCancelled && !trip.isCompleted)
        .toList()
      ..sort((a, b) {
        final aDate = a.pickupAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.pickupAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return aDate.compareTo(bDate);
      });

    return ApiResponse.success(trips, response.statusCode);
  }

  Future<ApiResponse<List<TripModel>>> _listTrips({
    String? status,
    Map<String, String>? queryParams,
  }) async {
    final params = <String, String>{
      if (status != null) 'status': status,
      ...?queryParams,
    };

    final response = await _api.get(
      '/trips',
      requireAuth: true,
      queryParams: params.isEmpty ? null : params,
    );

    if (!response.success) {
      return ApiResponse.error(
        response.message ?? 'Failed to load trips.',
        response.statusCode,
      );
    }

    final trips = nestedListData(
      response.data,
    ).map(TripModel.fromJson).toList();

    return ApiResponse.success(trips, response.statusCode);
  }

  Future<ApiResponse<TripModel>> getTripById(String tripId) async {
    final response = await _api.get('/trips/$tripId', requireAuth: true);

    if (!response.success) {
      return ApiResponse.error(
        response.message ?? 'Failed to load trip.',
        response.statusCode,
      );
    }

    final data = nestedData(response.data);
    if (data == null) {
      return ApiResponse.error('Invalid trip response');
    }

    return ApiResponse.success(TripModel.fromJson(data), response.statusCode);
  }

  Future<ApiResponse<Map<String, dynamic>>> previewCancellationCharges(
    String tripId,
  ) async {
    final response = await _api.get(
      '/trips/$tripId/cancellation-preview',
      requireAuth: true,
    );

    if (!response.success) {
      return ApiResponse.error(
        response.message ?? 'Failed to load cancellation charges.',
        response.statusCode,
      );
    }

    final data = nestedData(response.data) ?? response.data;
    if (data is! Map) {
      return ApiResponse.error('Invalid cancellation preview response');
    }

    return ApiResponse(
      success: true,
      data: Map<String, dynamic>.from(data!),
      statusCode: response.statusCode,
      message: response.message,
    );
  }

  Future<ApiResponse<TripModel>> cancelTrip(
    String tripId, {
    String? reason,
  }) async {
    final response = await _api.post(
      '/trips/$tripId/cancel',
      {if (reason != null && reason.isNotEmpty) 'reason': reason},
      requireAuth: true,
    );

    if (!response.success) {
      return ApiResponse.error(
        response.message ?? 'Failed to cancel trip.',
        response.statusCode,
      );
    }

    final data = nestedData(response.data);
    if (data == null) {
      return ApiResponse.error('Invalid cancel trip response');
    }

    return ApiResponse(
      success: true,
      data: TripModel.fromJson(data),
      statusCode: response.statusCode,
      message: response.message,
    );
  }

  Future<ApiResponse<TripModel>> rateTrip(
    String tripId, {
    required int stars,
    List<String>? feedbackTags,
    String? comment,
  }) async {
    final response = await _api.post(
      '/trips/$tripId/rate',
      {
        'stars': stars,
        if (feedbackTags != null && feedbackTags.isNotEmpty)
          'feedbackTags': feedbackTags,
        if (comment != null && comment.trim().isNotEmpty)
          'comment': comment.trim(),
      },
      requireAuth: true,
    );

    if (!response.success) {
      return ApiResponse.error(
        response.message ?? 'Failed to submit rating.',
        response.statusCode,
      );
    }

    final data = nestedData(response.data);
    if (data == null) {
      return ApiResponse.error('Invalid rating response');
    }

    return ApiResponse.success(TripModel.fromJson(data), response.statusCode);
  }

  Future<ApiResponse<Map<String, dynamic>>> generateStartOtp(
    String tripId,
  ) async {
    final response = await _api.post(
      '/trips/$tripId/start-otp',
      {},
      requireAuth: true,
    );

    if (!response.success) {
      return ApiResponse.error(
        response.message ?? 'Failed to generate trip OTP.',
        response.statusCode,
      );
    }

    final data = nestedData(response.data) ?? response.data;
    if (data == null) {
      return ApiResponse.error('Invalid OTP response');
    }

    return ApiResponse.success(data, response.statusCode);
  }
}

final tripApiProvider = Provider<TripApi>((ref) {
  return TripApi(ref.watch(apiProviderProvider));
});
