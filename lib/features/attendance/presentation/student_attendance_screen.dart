import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../user_management/providers.dart';
import '../data/models.dart';
import '../providers.dart';
import 'course_attendance_screen.dart';
import 'scan_screen.dart';
import 'timetable_screen.dart';

class StudentAttendanceScreen extends ConsumerWidget {
  const StudentAttendanceScreen({super.key});

  /// Builds the student attendance screen interface.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return const SizedBox.shrink();

    final historyAsync = ref.watch(attendanceHistoryProvider(userId));

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(attendanceHistoryProvider(userId)),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [scheme.primary, scheme.primary.withValues(alpha: 0.8)],
              ),
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Check in to class',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: scheme.onPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Scan the lecturer\'s QR code to mark attendance.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onPrimary.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.onPrimary,
                    foregroundColor: scheme.primary,
                    minimumSize: const Size(0, 44),
                  ),
                  onPressed: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const ScanScreen())),
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Text('Scan'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _NavLinkRow(
            icon: Icons.calendar_month_outlined,
            label: 'My Timetable',
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const TimetableScreen())),
          ),
          const SizedBox(height: 8),
          _NavLinkRow(
            icon: Icons.pie_chart_outline_rounded,
            label: 'Attendance by Course',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CourseAttendanceScreen()),
            ),
          ),
          const SizedBox(height: 20),
          Text('History', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          historyAsync.when(
            data: (entries) {
              if (entries.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No attendance recorded yet',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                );
              }
              return Column(
                children: entries
                    .map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _HistoryTile(entry: entry),
                      ),
                    )
                    .toList(),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => Center(
              child: Text(
                'Could not load history',
                style: TextStyle(color: scheme.error),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavLinkRow extends StatelessWidget {
  const _NavLinkRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

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
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// Returns the icon for an attendance status.
IconData _historyStatusIcon(AttendanceStatus status) {
  switch (status) {
    case AttendanceStatus.present:
      return Icons.check_circle_rounded;
    case AttendanceStatus.late:
      return Icons.schedule_rounded;
    case AttendanceStatus.absent:
      return Icons.cancel_rounded;
    case AttendanceStatus.leave:
      return Icons.event_busy_rounded;
    case AttendanceStatus.pending:
      return Icons.hourglass_empty_rounded;
  }
}

/// Returns the color for an attendance history status.
Color _historyStatusColor(BuildContext context, AttendanceStatus status) {
  final scheme = Theme.of(context).colorScheme;
  switch (status) {
    case AttendanceStatus.present:
      return AppTheme.success(context);
    case AttendanceStatus.late:
      return scheme.tertiary;
    case AttendanceStatus.absent:
      return scheme.error;
    case AttendanceStatus.leave:
      return scheme.secondary;
    case AttendanceStatus.pending:
      return scheme.onSurfaceVariant;
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry});

  final AttendanceHistoryEntry entry;

  /// Builds the history tile interface.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = attendanceStatusFromString(entry.record.status);
    final color = _historyStatusColor(context, status);
    final dt = entry.record.scanTimestamp.toLocal();
    final dateLabel =
        '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} · '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: Icon(_historyStatusIcon(status), color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.courseName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(dateLabel, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          Text(
            status.label,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
