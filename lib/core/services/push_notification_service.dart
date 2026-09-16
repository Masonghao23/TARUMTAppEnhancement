import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';

import '../../features/notifications/data/notification_repository.dart';

/// Requests notification permission, captures this device's FCM token, and
/// keeps it registered against the signed-in user. Delivery itself (the
/// actual push) is handled server-side by the send-push-notification Edge
/// Function — this class only ever writes to user_fcm_tokens.
class PushNotificationService {
  PushNotificationService(this._repo);

  final NotificationRepository _repo;
  StreamSubscription<String>? _refreshSub;
  bool _initialized = false;

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

  void dispose() {
    _refreshSub?.cancel();
  }
}
