import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../user_management/providers.dart';
import '../data/models.dart';
import '../providers.dart';
import 'attendance_charts_screen.dart';
import 'live_session_screen.dart';
import 'manage_timetable_screen.dart';
import 'reschedule_requests_screen.dart';
import 'session_history_screen.dart';
import 'timetable_screen.dart';

class StaffSessionsScreen extends ConsumerWidget {
  const StaffSessionsScreen({super.key});

  /// Builds the staff sessions screen interface.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final lecturerId = ref.watch(currentUserIdProvider);
    if (lecturerId == null) return const SizedBox.shrink();

    final sessionsAsync = ref.watch(activeSessionsProvider(lecturerId));
    final pendingRequestCount = ref.watch(
      pendingRescheduleRequestCountProvider,
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Column(
            children: [
              _NavLinkRow(
                icon: Icons.calendar_month_outlined,
                label: 'My Timetable',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const TimetableScreen(forLecturer: true),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _NavLinkRow(
                icon: Icons.edit_calendar_outlined,
                label: 'Manage Timetable',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ManageTimetableScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _NavLinkRow(
                icon: Icons.history_rounded,
                label: 'History Classes',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SessionHistoryScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _NavLinkRow(
                icon: Icons.event_repeat_outlined,
                label: 'Reschedule Requests',
                badgeCount: pendingRequestCount,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const RescheduleRequestsScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _NavLinkRow(
                icon: Icons.insights_outlined,
                label: 'Attendance Charts',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AttendanceChartsScreen(),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(activeSessionsProvider(lecturerId)),
            child: sessionsAsync.when(
              data: (live) {
                if (live.isEmpty) {
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
                    children: [
                      Icon(
                        Icons.qr_code_2_rounded,
                        size: 56,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No live class right now',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Tap "Start session" to start taking attendance.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  );
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
                  children: [
                    Text(
                      'Live now',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    for (final session in live) ...[
                      _LiveSessionTile(session: session),
                      const SizedBox(height: 10),
                    ],
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Center(
                child: Text(
                  'Could not load sessions',
                  style: TextStyle(color: scheme.error),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NavLinkRow extends StatelessWidget {
  const _NavLinkRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int badgeCount;

  /// Builds the nav link row interface.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (badgeCount > 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.error,
                    borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                  ),
                  child: Text(
                    badgeCount > 9 ? '9+' : '$badgeCount',
                    style: TextStyle(
                      color: scheme.onError,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Icon(
                Icons.chevron_right_rounded,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveSessionTile extends StatelessWidget {
  const _LiveSessionTile({required this.session});

  final ClassSession session;

  /// Builds the live session tile interface.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => LiveSessionScreen(session: session)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
                child: Icon(
                  Icons.sensors_rounded,
                  color: scheme.onTertiaryContainer,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.courseName ?? 'Class session',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Live now${session.roomName != null ? ' · ${session.roomName}' : ''}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
