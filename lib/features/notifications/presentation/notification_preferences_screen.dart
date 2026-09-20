import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../data/models.dart';
import '../providers.dart';

class NotificationPreferencesScreen extends ConsumerStatefulWidget {
  const NotificationPreferencesScreen({super.key});

  /// Creates the mutable state for this widget.
  @override
  ConsumerState<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends ConsumerState<NotificationPreferencesScreen> {
  NotificationPreferences? _prefs;
  bool _saving = false;

  /// Updates and saves the selected notification preference.
  Future<void> _toggle(
    NotificationPreferences Function(NotificationPreferences) update,
  ) async {
    final current = _prefs;
    if (current == null || _saving) return;
    final next = update(current);
    setState(() {
      _prefs = next;
      _saving = true;
    });
    try {
      await ref.read(notificationRepositoryProvider).updatePreferences(next);
      ref.invalidate(notificationPreferencesProvider);
    } catch (_) {
      if (mounted) {
        setState(() => _prefs = current);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save — try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Builds the notification preferences screen interface.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final prefsAsync = ref.watch(notificationPreferencesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Notification Preferences')),
      body: SafeArea(
        child: prefsAsync.when(
          data: (loaded) {
            _prefs ??= loaded;
            final prefs = _prefs!;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                _PreferenceTile(
                  icon: Icons.school_rounded,
                  label: 'Attendance Alerts',
                  caption:
                      'Not-recorded warnings, below-80% attendance alerts',
                  value: prefs.allowAttendanceAlerts,
                  enabled: !_saving,
                  onChanged: (v) => _toggle(
                    (p) => p.copyWith(allowAttendanceAlerts: v),
                  ),
                ),
                const SizedBox(height: 8),
                _PreferenceTile(
                  icon: Icons.local_parking_rounded,
                  label: 'Parking Alerts',
                  caption: 'Session ending soon, duration exceeded',
                  value: prefs.allowParkingAlerts,
                  enabled: !_saving,
                  onChanged: (v) =>
                      _toggle((p) => p.copyWith(allowParkingAlerts: v)),
                ),
                const SizedBox(height: 8),
                _PreferenceTile(
                  icon: Icons.schedule_rounded,
                  label: 'Class Reminders',
                  caption: 'Class time and venue, shortly before it starts',
                  value: prefs.allowClassReminders,
                  enabled: !_saving,
                  onChanged: (v) =>
                      _toggle((p) => p.copyWith(allowClassReminders: v)),
                ),
                const SizedBox(height: 8),
                _PreferenceTile(
                  icon: Icons.event_available_rounded,
                  label: 'Booking Reminders',
                  caption: 'Parking reservation confirmations and campus events',
                  value: prefs.allowBookingReminders,
                  enabled: !_saving,
                  onChanged: (v) =>
                      _toggle((p) => p.copyWith(allowBookingReminders: v)),
                ),
                const SizedBox(height: 8),
                _PreferenceTile(
                  icon: Icons.event_repeat_rounded,
                  label: 'Reschedule Updates',
                  caption:
                      'New requests, approvals and rejections for class reschedules',
                  value: prefs.allowRescheduleUpdates,
                  enabled: !_saving,
                  onChanged: (v) =>
                      _toggle((p) => p.copyWith(allowRescheduleUpdates: v)),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: Text(
              'Could not load preferences',
              style: TextStyle(color: scheme.error),
            ),
          ),
        ),
      ),
    );
  }
}

class _PreferenceTile extends StatelessWidget {
  const _PreferenceTile({
    required this.icon,
    required this.label,
    required this.caption,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String caption;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  /// Builds the preference tile interface.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Row(
        children: [
          Icon(icon, color: scheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  caption,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            onChanged: enabled ? onChanged : null,
          ),
        ],
      ),
    );
  }
}
