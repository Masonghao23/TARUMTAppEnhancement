import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../user_management/providers.dart';
import '../data/models.dart';
import '../providers.dart';
import 'live_session_screen.dart';

class StartSessionScreen extends ConsumerWidget {
  const StartSessionScreen({super.key});

  /// Builds the start session screen interface.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final slotsAsync = ref.watch(lecturerScheduleForDateProvider(today));
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Start session')),
      body: SafeArea(
        child: slotsAsync.when(
          data: (slots) {
            if (slots.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.event_busy_outlined,
                        size: 56,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No classes scheduled today',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              );
            }
            final sorted = [...slots]
              ..sort(
                (a, b) => a.startTime.decimalHours.compareTo(
                  b.startTime.decimalHours,
                ),
              );
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              itemCount: sorted.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) =>
                  _SlotTile(slot: sorted[index], occurrenceDate: today),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) =>
              Center(child: Text('Could not load timetable: $error')),
        ),
      ),
    );
  }
}

class _SlotTile extends ConsumerStatefulWidget {
  const _SlotTile({required this.slot, required this.occurrenceDate});

  final LecturerSlot slot;
  final DateTime occurrenceDate;

  /// Creates the mutable state for this widget.
  @override
  ConsumerState<_SlotTile> createState() => _SlotTileState();
}

class _SlotTileState extends ConsumerState<_SlotTile> {
  bool _busy = false;

  /// Returns whether the scheduled slot has ended.
  bool get _ended => widget.slot.sessionStatus == 'ended';

  /// Starts or opens the scheduled class session.
  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(attendanceRepositoryProvider)
          .startScheduledSession(
            scheduleId: widget.slot.scheduleId,
            exceptionId: widget.slot.exceptionId,
            occurrenceDate: widget.occurrenceDate,
          );
      if (!mounted) return;
      if (!result.success || result.sessionId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.reason ?? 'Could not start session.')),
        );
        return;
      }

      final session = ClassSession(
        id: result.sessionId!,
        courseId: widget.slot.courseId,
        roomId: widget.slot.roomId,
        lecturerId: ref.read(currentUserIdProvider) ?? '',
        qrIntervalSeconds: 20,
        status: SessionStatus.active,
        startTime: DateTime.now(),
        courseName: widget.slot.courseName,
        roomName: widget.slot.roomName,
      );

      ref.invalidate(lecturerScheduleForDateProvider(widget.occurrenceDate));
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => LiveSessionScreen(session: session)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Builds the slot tile interface.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final slot = widget.slot;

    late final Color barColor;
    late final String typeLabel;
    switch (slot.sessionType) {
      case SessionSlotType.lecture:
        barColor = scheme.primary;
        typeLabel = 'LECTURE';
      case SessionSlotType.tutorial:
        barColor = scheme.tertiary;
        typeLabel = 'TUTORIAL';
      case SessionSlotType.practical:
        barColor = AppTheme.success(context);
        typeLabel = 'PRACTICAL';
    }

    final label = !slot.isStarted ? 'Start' : (_ended ? 'Resume' : 'Continue');

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      padding: const EdgeInsets.all(13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 52,
            decoration: BoxDecoration(
              color: barColor,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  typeLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: barColor,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  slot.courseName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '${_fmt(slot.startTime)} – ${_fmt(slot.endTime)} · ${slot.roomName}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _busy ? null : _start,
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            child: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(label),
          ),
        ],
      ),
    );
  }

  /// Formats a time for the timetable display.
  String _fmt(WallClockTime t) {
    final period = t.hour >= 12 ? 'PM' : 'AM';
    final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$h12:${t.minute.toString().padLeft(2, '0')} $period';
  }
}
