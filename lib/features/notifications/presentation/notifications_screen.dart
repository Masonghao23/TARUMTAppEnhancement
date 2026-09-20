import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../data/models.dart';
import '../providers.dart';
import 'notification_preferences_screen.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  /// Formats a date heading for grouped notifications.
  static String _dayLabel(DateTime sentAt) {
    final now = DateTime.now();
    final local = sentAt.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(local.year, local.month, local.day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return 'Earlier';
  }

  /// Builds the notifications screen interface.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final notificationsAsync = ref.watch(myNotificationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            tooltip: 'Notification preferences',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const NotificationPreferencesScreen(),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(myNotificationsProvider),
          child: notificationsAsync.when(
            data: (notifications) {
              if (notifications.isEmpty) {
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
                  children: [
                    Icon(
                      Icons.notifications_none_rounded,
                      size: 56,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No notifications yet',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                );
              }

              final groups = <String, List<AppNotification>>{};
              for (final n in notifications) {
                groups.putIfAbsent(_dayLabel(n.sentAt), () => []).add(n);
              }
              final order = ['Today', 'Yesterday', 'Earlier'];

              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  for (final label in order)
                    if (groups[label] != null) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8, top: 8),
                        child: Text(
                          label.toUpperCase(),
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                      for (final n in groups[label]!) ...[
                        _NotificationCard(
                          notification: n,
                          onTap: n.isRead
                              ? null
                              : () async {
                                  await ref
                                      .read(notificationRepositoryProvider)
                                      .markNotificationRead(n.id);
                                  ref.invalidate(myNotificationsProvider);
                                },
                          onDelete: () async {
                            await ref
                                .read(notificationRepositoryProvider)
                                .deleteNotification(n.id);
                            ref.invalidate(myNotificationsProvider);
                          },
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(
              child: Text(
                'Could not load notifications',
                style: TextStyle(color: scheme.error),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.onTap,
    required this.onDelete,
  });

  final AppNotification notification;
  final VoidCallback? onTap;
  final VoidCallback onDelete;

  /// Returns the icon for the notification category.
  static IconData _icon(NotificationCategory category) {
    switch (category) {
      case NotificationCategory.attendance:
        return Icons.school_rounded;
      case NotificationCategory.parking:
        return Icons.local_parking_rounded;
      case NotificationCategory.classReminder:
        return Icons.schedule_rounded;
      case NotificationCategory.booking:
        return Icons.event_available_rounded;
      case NotificationCategory.reschedule:
        return Icons.event_repeat_rounded;
      case NotificationCategory.broadcast:
        return Icons.campaign_rounded;
    }
  }

  /// Returns the color for the notification category.
  static Color _color(BuildContext context, NotificationCategory category) {
    final scheme = Theme.of(context).colorScheme;
    switch (category) {
      case NotificationCategory.attendance:
        return scheme.error;
      case NotificationCategory.parking:
        return scheme.tertiary;
      case NotificationCategory.classReminder:
        return scheme.primary;
      case NotificationCategory.booking:
        return scheme.primary;
      case NotificationCategory.reschedule:
        return scheme.tertiary;
      case NotificationCategory.broadcast:
        return scheme.secondary;
    }
  }

  /// Formats a time for display.
  String _fmtTime(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final sameDay =
        local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    if (sameDay) return time;
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')} · $time';
  }

  /// Builds the notification card interface.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _color(context, notification.category);

    return Material(
      color: notification.isRead
          ? scheme.surfaceContainerHigh.withValues(alpha: 0.6)
          : scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
                child: Icon(
                  _icon(notification.category),
                  color: color,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (!notification.isRead)
                          Container(
                            width: 7,
                            height: 7,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            notification.title,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: notification.isRead
                                      ? FontWeight.w500
                                      : FontWeight.w700,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      notification.message,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _fmtTime(notification.sentAt),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 32,
                height: 32,
                child: IconButton(
                  tooltip: 'Delete',
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  icon: Icon(
                    Icons.close_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                  onPressed: onDelete,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
