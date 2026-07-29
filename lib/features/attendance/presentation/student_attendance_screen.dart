import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../user_management/providers.dart';
import '../data/models.dart';
import '../providers.dart';
import 'scan_screen.dart';

class StudentAttendanceScreen extends ConsumerWidget {
  const StudentAttendanceScreen({super.key});

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
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ScanScreen()),
                  ),
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Text('Scan'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
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
                    .map((entry) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _HistoryTile(entry: entry),
                        ))
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

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry});

  final AttendanceHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
              color: scheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: Icon(
              Icons.check_circle_rounded,
              color: scheme.onTertiaryContainer,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.courseName, style: Theme.of(context).textTheme.titleMedium),
                Text(dateLabel, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
