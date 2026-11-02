import 'dart:developer';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

/// Socket.IO client for live trip tracking and in-app notifications.
class TripSocketService {
  TripSocketService({required this.socketUrl});

  final String socketUrl;
  io.Socket? _socket;
  void Function(Map<String, dynamic>)? _onDriverLocation;
  void Function(Map<String, dynamic>)? _onNewNotification;
  String? _userId;
  String? _authToken;
  String? _tripId;
  bool _handshakeAuthenticated = false;

  bool get isConnected => _socket?.connected ?? false;

  void ensureConnected() => connect();

  Map<String, dynamic> _handshakeAuth() {
    return {
      if (_authToken != null && _authToken!.isNotEmpty) 'token': _authToken,
      if (_userId != null && _userId!.isNotEmpty) 'userId': _userId,
    };
  }

  void connect({
    void Function(Map<String, dynamic>)? onDriverLocation,
    String? authToken,
    String? userId,
  }) {
    if (onDriverLocation != null) _onDriverLocation = onDriverLocation;
    if (authToken != null && authToken.isNotEmpty) _authToken = authToken;
    if (userId != null && userId.isNotEmpty) _userId = userId;

    final auth = _handshakeAuth();
    final created = _socket == null;
    _socket ??= io.io(
      socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .enableReconnection()
          .disableAutoConnect()
          .setAuth(auth)
          .build(),
    );
    if (!created && auth.isNotEmpty) {
      _socket!.auth = auth;
    }

    _socket!
      ..off('connect')
      ..off('disconnect')
      ..off('driver_location_update')
      ..on('connect', (_) {
        log('Trip socket connected', name: 'TripSocketService');
        _rejoinRooms();
      })
      ..on('disconnect', (_) {
        log('Trip socket disconnected', name: 'TripSocketService');
      })
      ..on('driver_location_update', (data) {
        final map = _asMap(data);
        if (map != null) _onDriverLocation?.call(map);
      });
    _bindNotificationListener();

    // A socket that connected before the login token was available never
    // auto-joined user_room_*, so the server emitted the trip alert into an
    // empty room. Reconnect once the handshake can identify the owner.
    final needsAuthenticatedHandshake =
        auth.isNotEmpty && !_handshakeAuthenticated && _socket!.connected == true;
    if (auth.isNotEmpty) _handshakeAuthenticated = true;

    if (_socket!.connected != true) {
      _socket!.connect();
    } else if (needsAuthenticatedHandshake) {
      _socket!
        ..disconnect()
        ..connect();
    } else {
      _rejoinRooms();
    }
  }

  void _rejoinRooms() {
    if (_socket?.connected != true) return;
    if (_userId != null && _userId!.isNotEmpty) {
      _socket!.emit('join_user_room', {'userId': _userId});
    }
    if (_tripId != null && _tripId!.isNotEmpty) {
      _socket!.emit('join_trip_room', {'tripId': _tripId});
    }
  }

  void joinUserRoom(String userId) {
    if (userId.isEmpty) return;
    _userId = userId;
    ensureConnected();

    void join() => _socket?.emit('join_user_room', {'userId': userId});

    if (_socket?.connected == true) {
      join();
      return;
    }

    _socket?.once('connect', (_) => join());
  }

  void leaveUserRoom(String userId) {
    if (_userId == userId) _userId = null;
    if (_socket?.connected == true && userId.isNotEmpty) {
      _socket!.emit('leave_user_room', {'userId': userId});
    }
  }

  void joinTripRoom(String tripId) {
    if (tripId.isEmpty) return;
    _tripId = tripId;
    ensureConnected();

    void join() => _socket?.emit('join_trip_room', {'tripId': tripId});

    if (_socket?.connected == true) {
      join();
      return;
    }

    _socket?.once('connect', (_) => join());
  }

  void leaveTripRoom(String tripId) {
    if (_tripId == tripId) _tripId = null;
    if (_socket?.connected == true && tripId.isNotEmpty) {
      _socket!.emit('leave_trip_room', {'tripId': tripId});
    }
  }

  void listenForNewNotifications(
    void Function(Map<String, dynamic> notification) onNewNotification,
  ) {
    _onNewNotification = onNewNotification;
    _bindNotificationListener();
  }

  void _bindNotificationListener() {
    final socket = _socket;
    final handler = _onNewNotification;
    if (socket == null || handler == null) return;
    socket
      ..off('new_notification')
      ..on('new_notification', (data) {
        final map = _asMap(data);
        if (map != null) handler(map);
      });
  }

  final List<void Function(Map<String, dynamic>)> _tripReassignedHandlers = [];
  final List<void Function(Map<String, dynamic>)> _tripUpdatedHandlers = [];

  void listenForTripReassigned(
    void Function(Map<String, dynamic> payload) onTripReassigned,
  ) {
    ensureConnected();
    if (!_tripReassignedHandlers.contains(onTripReassigned)) {
      _tripReassignedHandlers.add(onTripReassigned);
    }
    _socket?.off('trip_reassigned');
    _socket?.on('trip_reassigned', (data) {
      final map = _asMap(data);
      if (map == null) return;
      for (final handler in List<void Function(Map<String, dynamic>)>.from(
        _tripReassignedHandlers,
      )) {
        handler(map);
      }
    });
  }

  void removeTripReassignedListener(
    void Function(Map<String, dynamic> payload) onTripReassigned,
  ) {
    _tripReassignedHandlers.remove(onTripReassigned);
  }

  void listenForTripUpdated(
    void Function(Map<String, dynamic> payload) onTripUpdated,
  ) {
    ensureConnected();
    if (!_tripUpdatedHandlers.contains(onTripUpdated)) {
      _tripUpdatedHandlers.add(onTripUpdated);
    }
    _socket?.off('trip_updated');
    _socket?.on('trip_updated', (data) {
      final map = _asMap(data);
      if (map == null) return;
      for (final handler in List<void Function(Map<String, dynamic>)>.from(
        _tripUpdatedHandlers,
      )) {
        handler(map);
      }
    });
  }

  void removeTripUpdatedListener(
    void Function(Map<String, dynamic> payload) onTripUpdated,
  ) {
    _tripUpdatedHandlers.remove(onTripUpdated);
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _onDriverLocation = null;
    _onNewNotification = null;
    _userId = null;
    _authToken = null;
    _handshakeAuthenticated = false;
    _tripId = null;
    _tripReassignedHandlers.clear();
    _tripUpdatedHandlers.clear();
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }
}

String socketUrlFromApiBase(String apiBaseUrl) {
  final uri = Uri.parse(apiBaseUrl);
  final portPart = uri.hasPort ? ':${uri.port}' : '';
  return '${uri.scheme}://${uri.host}$portPart';
}

final tripSocketServiceProvider = Provider<TripSocketService>((ref) {
  ref.keepAlive();
  final apiBase = dotenv.env['BASE_URL'] ?? '';
  final socketUrl = socketUrlFromApiBase(apiBase);
  final service = TripSocketService(socketUrl: socketUrl);
  ref.onDispose(service.disconnect);
  return service;
});
