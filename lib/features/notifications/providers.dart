import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/push_notification_service.dart';
import '../auth/providers.dart';
import '../user_management/providers.dart';
import 'data/models.dart';
import 'data/notification_repository.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(ref.watch(supabaseClientProvider));
});

/// Depends on [currentUserIdProvider] purely so the cache invalidates on a
/// user switch (logout/login as someone else without an app restart) —
/// fetchMyNotifications() itself just reads whoever's currently signed in.
final myNotificationsProvider = FutureProvider.autoDispose<
  List<AppNotification>
>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(notificationRepositoryProvider).fetchMyNotifications();
});

final unreadNotificationCountProvider = Provider.autoDispose<int>((ref) {
  final notifications = ref.watch(myNotificationsProvider).value ?? const [];
  return notifications.where((n) => !n.isRead).length;
});

final notificationPreferencesProvider = FutureProvider.autoDispose<
  NotificationPreferences
>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(notificationRepositoryProvider).fetchMyPreferences();
});

final pushNotificationServiceProvider = Provider<PushNotificationService>((
  ref,
) {
  final service = PushNotificationService(
    ref.watch(notificationRepositoryProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Watching this from the widget tree (see HomeShell) is what actually
/// triggers FCM setup — it re-runs once per distinct signed-in user, not on
/// every rebuild, since it depends on [currentUserIdProvider] rather than
/// running unconditionally.
final pushNotificationSetupProvider = FutureProvider.autoDispose<void>((
  ref,
) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return;
  await ref.watch(pushNotificationServiceProvider).initialize();
});
