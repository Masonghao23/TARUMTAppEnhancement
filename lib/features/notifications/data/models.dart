enum NotificationCategory {
  attendance,
  parking,
  classReminder,
  booking,
  reschedule,
  broadcast,
}

/// Converts a stored notification category to its enum value.
NotificationCategory _categoryFromString(String value) {
  switch (value) {
    case 'attendance':
      return NotificationCategory.attendance;
    case 'parking':
      return NotificationCategory.parking;
    case 'class':
      return NotificationCategory.classReminder;
    case 'booking':
      return NotificationCategory.booking;
    case 'reschedule':
      return NotificationCategory.reschedule;
    default:
      return NotificationCategory.broadcast;
  }
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.category,
    required this.isRead,
    required this.sentAt,
  });

  /// Creates app notification data from a database row.
  factory AppNotification.fromMap(Map<String, dynamic> map) {
    return AppNotification(
      id: map['id'] as String,
      title: map['title'] as String? ?? '',
      message: map['message'] as String? ?? '',
      category: _categoryFromString(map['type'] as String? ?? 'broadcast'),
      isRead: map['is_read'] as bool? ?? false,
      sentAt: DateTime.parse(map['sent_at'] as String),
    );
  }

  final String id;
  final String title;
  final String message;
  final NotificationCategory category;
  final bool isRead;
  final DateTime sentAt;
}

class NotificationPreferences {
  const NotificationPreferences({
    required this.allowAttendanceAlerts,
    required this.allowParkingAlerts,
    required this.allowClassReminders,
    required this.allowBookingReminders,
    required this.allowRescheduleUpdates,
  });

  static const defaults = NotificationPreferences(
    allowAttendanceAlerts: true,
    allowParkingAlerts: true,
    allowClassReminders: true,
    allowBookingReminders: true,
    allowRescheduleUpdates: true,
  );

  /// Creates notification preferences data from a database row.
  factory NotificationPreferences.fromMap(Map<String, dynamic> map) {
    return NotificationPreferences(
      allowAttendanceAlerts: map['allow_attendance_alerts'] as bool? ?? true,
      allowParkingAlerts: map['allow_parking_alerts'] as bool? ?? true,
      allowClassReminders: map['allow_class_reminders'] as bool? ?? true,
      allowBookingReminders: map['allow_booking_reminders'] as bool? ?? true,
      allowRescheduleUpdates:
          map['allow_reschedule_updates'] as bool? ?? true,
    );
  }

  final bool allowAttendanceAlerts;
  final bool allowParkingAlerts;
  final bool allowClassReminders;
  final bool allowBookingReminders;
  final bool allowRescheduleUpdates;

  /// Copies notification preferences with the supplied changes.
  NotificationPreferences copyWith({
    bool? allowAttendanceAlerts,
    bool? allowParkingAlerts,
    bool? allowClassReminders,
    bool? allowBookingReminders,
    bool? allowRescheduleUpdates,
  }) {
    return NotificationPreferences(
      allowAttendanceAlerts:
          allowAttendanceAlerts ?? this.allowAttendanceAlerts,
      allowParkingAlerts: allowParkingAlerts ?? this.allowParkingAlerts,
      allowClassReminders: allowClassReminders ?? this.allowClassReminders,
      allowBookingReminders:
          allowBookingReminders ?? this.allowBookingReminders,
      allowRescheduleUpdates:
          allowRescheduleUpdates ?? this.allowRescheduleUpdates,
    );
  }
}

class BroadcastResult {
  const BroadcastResult({
    required this.success,
    this.reason,
    this.recipientCount,
  });

  /// Creates broadcast result data from a database row.
  factory BroadcastResult.fromMap(Map<String, dynamic> map) {
    return BroadcastResult(
      success: map['success'] as bool? ?? false,
      reason: map['reason'] as String?,
      recipientCount: map['recipientCount'] as int?,
    );
  }

  final bool success;
  final String? reason;
  final int? recipientCount;
}
