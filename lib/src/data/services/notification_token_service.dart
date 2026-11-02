import 'package:flutter/material.dart';
import 'package:DriveForme/src/data/services/navigation_services.dart';
import 'package:DriveForme/src/data/services/secure_storage_service.dart';
import 'package:DriveForme/src/interfaces/main_pages/support/support_pages.dart';
import 'dart:convert';
import 'dart:developer';

import 'package:DriveForme/firebase_options.dart';
import 'package:DriveForme/src/data/apis/notification_api.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _kTripChannelId = 'driveforme_trips';
const _kTripChannelName = 'Trip updates';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  log(
    'Background FCM: ${message.messageId} ${message.notification?.title}',
    name: 'PushNotification',
  );
}

class PushNotificationService {
  PushNotificationService(this._notificationApi, this._storage);

  final SecureStorageService _storage;
  String? _pendingSupportTicket;
  String? _openSupportTicket;

  final NotificationApi _notificationApi;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  Future<void>? _initFuture;
  final Set<String> _shownAlertIds = {};

  void _captureSupportNotification(Map<String, dynamic> data) {
    if (data['action'] != 'open_support_chat') return;
    final id = data['ticketId']?.toString() ?? '';
    if (RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(id)) _pendingSupportTicket = id;
  }

  Future<void> openPendingSupportChat() async {
    final token = await _storage.getAuthToken();
    final navigator = NavigationService.navigatorKey.currentState;
    final id = _pendingSupportTicket;
    if (token == null || token.isEmpty || navigator == null || id == null) {
      return;
    }
    _pendingSupportTicket = null;
    if (_openSupportTicket == id) return;
    _openSupportTicket = id;
    try {
      await navigator.push(
        MaterialPageRoute<void>(builder: (_) => SupportChatPage(ticketId: id)),
      );
    } finally {
      _openSupportTicket = null;
    }
  }

  void _onNotificationPayload(String? payload) {
    if (payload == null) return;
    try {
      final data = jsonDecode(payload);
      if (data is Map) {
        _captureSupportNotification(Map<String, dynamic>.from(data));
        openPendingSupportChat();
      }
    } on FormatException {
      // Ignore notifications created by an older app with a different payload.
    }
  }

  Future<void> initialize() {
    return _initFuture ??= _initialize();
  }

  Future<void> _initialize() async {

    await _messaging.requestPermission(alert: true, badge: true, sound: true);

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _local.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (response) =>
          _onNotificationPayload(response.payload),
    );

    const androidChannel = AndroidNotificationChannel(
      _kTripChannelId,
      _kTripChannelName,
      description: 'Trip status alerts',
      importance: Importance.high,
    );
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(androidChannel);

    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onMessage.listen(_showForegroundNotification);
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _captureSupportNotification(message.data);
      openPendingSupportChat();
    });
    final initial = await _messaging.getInitialMessage();
    if (initial != null) _captureSupportNotification(initial.data);
    final localLaunch = await _local.getNotificationAppLaunchDetails();
    if (localLaunch?.didNotificationLaunchApp == true) {
      final payload = localLaunch?.notificationResponse?.payload;
      if (payload != null) {
        try {
          final data = jsonDecode(payload);
          if (data is Map) {
            _captureSupportNotification(Map<String, dynamic>.from(data));
          }
        } on FormatException {
          /* Ignore legacy payloads. */
        }
      }
    }
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    final title = notification?.title ?? message.data['title']?.toString();
    final body = notification?.body ?? message.data['body']?.toString();
    await showTripAlert(
      id: message.data['notificationId']?.toString(),
      title: title,
      body: body,
      payload: message.data,
    );
  }

  /// Banner for a trip alert that arrived over FCM or the live socket.
  Future<void> showTripAlert({
    String? id,
    String? title,
    String? body,
    Map<String, dynamic>? payload,
  }) async {
    if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) {
      return;
    }
    final key = id?.trim() ?? '';
    if (key.isNotEmpty) {
      if (!_shownAlertIds.add(key)) return;
      if (_shownAlertIds.length > 40) {
        _shownAlertIds.remove(_shownAlertIds.first);
      }
    }

    try {
      await initialize();
    } catch (e) {
      log('Local notification init failed: $e', name: 'PushNotification');
      return;
    }

    await _local.show(
      key.isEmpty
          ? DateTime.now().millisecondsSinceEpoch.remainder(1 << 31)
          : key.hashCode & 0x7fffffff,
      title ?? 'DriveForme',
      body ?? '',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _kTripChannelId,
          _kTripChannelName,
          channelDescription: 'Trip status alerts',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: jsonEncode(payload ?? const <String, dynamic>{}),
    );
  }

  Future<String?> getToken() async {
    try {
      return await _messaging.getToken();
    } catch (e) {
      log('FCM getToken failed: $e', name: 'PushNotification');
      return null;
    }
  }

  Future<void> registerTokenWithBackend() async {
    final token = await getToken();
    if (token == null || token.isEmpty) return;
    final response = await _notificationApi.registerFcmToken(token);
    if (!response.success) {
      log(
        'Failed to register FCM token: ${response.message}',
        name: 'PushNotification',
      );
    }
  }

  void listenForTokenRefresh() {
    _messaging.onTokenRefresh.listen((token) async {
      if (token.isEmpty) return;
      await _notificationApi.registerFcmToken(token);
    });
  }
}

class NotificationTokenService {
  NotificationTokenService(this._push);

  final PushNotificationService _push;

  Future<void> registerTokenIfAvailable() async {
    try {
      await _push.initialize();
      _push.listenForTokenRefresh();
      await _push.registerTokenWithBackend();
    } catch (e) {
      log('FCM registration skipped: $e', name: 'NotificationTokenService');
    }
  }
}

final pushNotificationServiceProvider = Provider<PushNotificationService>((
  ref,
) {
  return PushNotificationService(
    ref.watch(notificationApiProvider),
    ref.watch(secureStorageServiceProvider),
  );
});

final notificationTokenServiceProvider = Provider<NotificationTokenService>((
  ref,
) {
  return NotificationTokenService(ref.watch(pushNotificationServiceProvider));
});
