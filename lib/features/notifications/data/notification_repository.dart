import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

class NotificationRepository {
  NotificationRepository(this._client);

  final SupabaseClient _client;

  /// Registers the device’s FCM token for the signed-in user.
  Future<void> registerFcmToken(String token) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    await _client.rpc('claim_fcm_token', params: {'p_token': token});
  }

  /// Fetches the signed-in user’s recent notifications.
  Future<List<AppNotification>> fetchMyNotifications() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];
    final rows = await _client
        .from('notifications')
        .select()
        .eq('user_id', userId)
        .order('sent_at', ascending: false)
        .limit(100);
    return rows.map(AppNotification.fromMap).toList();
  }

  /// Marks a notification as read.
  Future<void> markNotificationRead(String notificationId) async {
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('id', notificationId);
  }

  /// Deletes the selected notification.
  Future<void> deleteNotification(String notificationId) async {
    await _client.from('notifications').delete().eq('id', notificationId);
  }

  /// Fetches notification preferences or returns their defaults.
  Future<NotificationPreferences> fetchMyPreferences() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return NotificationPreferences.defaults;
    final rows = await _client
        .from('notification_preferences')
        .select()
        .eq('user_id', userId)
        .limit(1);
    if (rows.isEmpty) return NotificationPreferences.defaults;
    return NotificationPreferences.fromMap(rows.first);
  }

  /// Saves the user’s notification preferences.
  Future<void> updatePreferences(NotificationPreferences prefs) async {
    await _client.rpc(
      'upsert_notification_preferences',
      params: {
        'p_allow_attendance_alerts': prefs.allowAttendanceAlerts,
        'p_allow_parking_alerts': prefs.allowParkingAlerts,
        'p_allow_class_reminders': prefs.allowClassReminders,
        'p_allow_booking_reminders': prefs.allowBookingReminders,
        'p_allow_reschedule_updates': prefs.allowRescheduleUpdates,
      },
    );
  }

  /// Sends an announcement to the selected audience.
  Future<BroadcastResult> sendBroadcastAnnouncement({
    required String title,
    required String message,
    required String target,
  }) async {
    final response = await _client.rpc(
      'send_broadcast_announcement',
      params: {'p_title': title, 'p_message': message, 'p_target': target},
    );
    return BroadcastResult.fromMap(response as Map<String, dynamic>);
  }
}
