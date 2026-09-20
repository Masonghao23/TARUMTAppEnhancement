import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';

import '../../features/notifications/data/notification_repository.dart';

class PushNotificationService {
  PushNotificationService(this._repo);

  final NotificationRepository _repo;
  StreamSubscription<String>? _refreshSub;
  bool _initialized = false;

  /// Initializes push notifications and registers the device token.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();

      final token = await messaging.getToken();
      if (token != null) {
        await _repo.registerFcmToken(token);
      }

      _refreshSub?.cancel();
      _refreshSub = messaging.onTokenRefresh.listen(
        (t) => _repo.registerFcmToken(t).catchError((_) {}),
      );
    } catch (_) {
    }
  }

  /// Releases resources and subscriptions owned by this component.
  void dispose() {
    _refreshSub?.cancel();
  }
}
