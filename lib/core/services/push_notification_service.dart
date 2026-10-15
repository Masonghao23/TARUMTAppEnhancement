import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../features/notifications/data/notification_repository.dart';

/// Requests notification permission, captures this device's FCM token, and
/// keeps it registered against the signed-in user. Delivery itself (the
/// actual push) is handled server-side by the send-push-notification Edge
/// Function — this class only ever writes to user_fcm_tokens, plus makes the
/// push visible on Android (heads-up channel + foreground display).
class PushNotificationService {
  PushNotificationService(this._repo);

  /// Must match the default_notification_channel_id meta-data in
  /// AndroidManifest.xml, so pushes with no explicit channel use it.
  static const _channelId = 'high_importance_channel';

  final NotificationRepository _repo;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  StreamSubscription<String>? _refreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  bool _initialized = false;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Best-effort by design: a denied permission, missing Play Services, or
  /// (on web, which isn't a real push target here) a missing VAPID key
  /// should never crash app startup — it just means this device gets no
  /// push notifications, not a broken app.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final messaging = FirebaseMessaging.instance;
      // iOS requires this before a token is issued at all; Android 13+
      // also needs it for the runtime POST_NOTIFICATIONS prompt (older
      // Android versions grant it automatically and this is a no-op).
      await messaging.requestPermission();

      await _setUpAndroidDisplay();

      final token = await messaging.getToken();
      if (token != null) {
        await _repo.registerFcmToken(token);
      }

      // A token can rotate (app reinstall, Firebase-side refresh) —
      // without this, a device would silently stop receiving pushes after
      // a rotation since the backend would keep sending to a dead token.
      _refreshSub?.cancel();
      _refreshSub = messaging.onTokenRefresh.listen(
        (t) => _repo.registerFcmToken(t).catchError((_) {}),
      );
    } catch (_) {
      // Swallowed on purpose — see doc comment above.
    }
  }

  /// Without a max-importance channel, Android files pushes in the default
  /// "Miscellaneous" channel: they reach the shade but never pop up. And FCM
  /// shows nothing at all while the app is open, so a foreground message is
  /// re-posted here as a local notification on the same channel.
  Future<void> _setUpAndroidDisplay() async {
    if (!_isAndroid) return;

    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            'Important notifications',
            description: 'Class reminders, parking alerts and announcements.',
            importance: Importance.max,
          ),
        );

    _foregroundSub?.cancel();
    _foregroundSub = FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification == null) return;
      _local.show(
        message.hashCode,
        notification.title,
        notification.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'Important notifications',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
      );
    });
  }

  void dispose() {
    _refreshSub?.cancel();
    _foregroundSub?.cancel();
  }
}
