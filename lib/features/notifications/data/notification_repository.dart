import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

class NotificationRepository {
  NotificationRepository(this._client);

  final SupabaseClient _client;

  /// Registers this device's FCM token against the signed-in user — a
  /// no-op if nobody's signed in yet. Goes through claim_fcm_token (security
  /// definer) rather than a plain upsert: a device token is only ever
  /// meaningful for whoever's currently signed in on it, but RLS stops a
  /// client from clearing a *different* user's row for the same token —
  /// so a straight upsert would leave a previous account on this device
  /// still registered, and both would get pushed on every send. The RPC
  /// atomically drops any other owner's claim on this exact token first.
  Future<void> registerFcmToken(String token) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    await _client.rpc('claim_fcm_token', params: {'p_token': token});
  }

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

  Future<void> markNotificationRead(String notificationId) async {
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('id', notificationId);
  }

  Future<void> deleteNotification(String notificationId) async {
    await _client.from('notifications').delete().eq('id', notificationId);
  }

  /// No row yet (never opened this screen before) means every toggle is
  /// still effectively on — [NotificationPreferences.defaults] mirrors the
  /// database column defaults exactly.
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

  /// Use case 4.2.4 "Broadcast Announcement" — staff/admin only (enforced
  /// again inside the RPC). p_target is 'students', 'staff' (covers
  /// staff+admin), or 'all'.
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
