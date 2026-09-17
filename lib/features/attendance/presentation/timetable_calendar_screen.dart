import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../campus_map/campus_map_screen.dart';
import '../../user_management/data/models.dart';
import '../../user_management/providers.dart';
import '../data/models.dart';
import '../providers.dart';
import 'add_edit_schedule_slot_screen.dart';
import 'request_reschedule_screen.dart';
import 'reschedule_class_screen.dart';

/// Second step of the Manage Timetable flow — a month calendar highlighting
/// days with classes for the courses chosen on ManageTimetableScreen；
/// tapping a day shows that day's classes below, with edit/reschedule
/// actions on the ones that support it.
class TimetableCalendarScreen extends ConsumerStatefulWidget {
  const TimetableCalendarScreen({super.key, required this.courseIdsKey});

  final String courseIdsKey;

  @override
  ConsumerState<TimetableCalendarScreen> createState() =>
      _TimetableCalendarScreenState();
}

class _TimetableCalendarScreenState
    extends ConsumerState<TimetableCalendarScreen> {
  late DateTime _month;
  late DateTime _selectedDate;

  static const _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  static const _dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month, 1);
    _selectedDate = DateTime(now.year, now.month, now.day);
  }

  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta, 1);
      _selectedDate = _month;
    });
  }

  void _refresh() {
    ref.invalidate(
      lecturerOccurrencesForMonthProvider((
        courseIdsKey: widget.courseIdsKey,
        month: _month,
      )),
    );
  }

  void _addOnDay() {
    final courseIds = widget.courseIdsKey.split(',');
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => AddEditScheduleSlotScreen(
              initialDayOfWeek: _selectedDate.weekday,
              initialCourseId: courseIds.length == 1 ? courseIds.first : null,
            ),
          ),
        )
        .then((_) => _refresh());
  }

  void _edit(ScheduleSlot slot) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => AddEditScheduleSlotScreen(existing: slot),
          ),
        )
        .then((_) => _refresh());
  }

  /// Admin still reschedules instantly (writes the exception directly, as
  /// before); staff now submits a request for admin to approve — see
  /// request_class_reschedule's own ownership check, which is exactly the
  /// same one create_schedule_exception already applies to admin.
  void _reschedule(TimetableOccurrence occurrence) {
    final isAdmin = ref.read(currentProfileProvider).value?.role == UserRole.admin;
    final slot = ScheduleSlot(
      id: occurrence.scheduleId!,
      courseId: occurrence.courseId,
      courseCode: occurrence.courseCode,
      courseName: occurrence.courseName,
      sessionType: occurrence.sessionType,
      dayOfWeek: occurrence.occurrenceDate.weekday,
      startTime: occurrence.startTime,
      endTime: occurrence.endTime,
      roomId: occurrence.roomId,
      roomName: occurrence.roomName,
    );
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => isAdmin
                ? RescheduleClassScreen(
                    slot: slot,
                    originalDate: occurrence.occurrenceDate,
                    // Already moved once — pre-fill with where it
                    // currently moved to, so re-rescheduling edits that
                    // instead of starting over from the recurring
                    // template's usual time.
                    currentMoveDate: occurrence.movedToDate,
                    currentMoveStartTime: occurrence.movedToStartTime,
                    currentMoveEndTime: occurrence.movedToEndTime,
                    currentMoveRoomId: occurrence.movedToRoomId,
                    currentMoveRoomName: occurrence.movedToRoomName,
                  )
                : RequestRescheduleScreen(
                    slot: slot,
                    originalDate: occurrence.occurrenceDate,
                  ),
          ),
        )
        .then((_) => _refresh());
  }

  Future<void> _undo(String exceptionId) async {
    final result = await ref
        .read(attendanceRepositoryProvider)
        .removeScheduleException(exceptionId);
    if (!mounted) return;
    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.reason ?? 'Could not undo.')),
      );
      return;
    }
    _refresh();
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final occurrencesAsync = ref.watch(
      lecturerOccurrencesForMonthProvider((
        courseIdsKey: widget.courseIdsKey,
        month: _month,
      )),
    );
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Timetable Calendar')),
      body: SafeArea(
        child: occurrencesAsync.when(
          data: (occurrences) {
            final highlighted = <DateTime>{};
            for (final o in occurrences) {
              if (o.status == TimetableOccurrenceStatus.cancelled ||
                  o.status == TimetableOccurrenceStatus.movedAway) {
                continue;
              }
              highlighted.add(
                DateTime(
                  o.occurrenceDate.year,
                  o.occurrenceDate.month,
                  o.occurrenceDate.day,
                ),
              );
            }
            final dayOccurrences =
                occurrences
                    .where((o) => _isSameDay(o.occurrenceDate, _selectedDate))
                    .toList()
                  ..sort(
                    (a, b) => a.startTime.decimalHours.compareTo(
                      b.startTime.decimalHours,
                    ),
                  );

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => _changeMonth(-1),
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                      Expanded(
                        child: Text(
                          '${_monthNames[_month.month - 1]} ${_month.year}',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        onPressed: () => _changeMonth(1),
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      for (final label in _dayLabels)
                        Expanded(
                          child: Center(
                            child: Text(
                              label,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: _MonthGrid(
                    month: _month,
                    selectedDate: _selectedDate,
                    highlightedDates: highlighted,
                    onSelect: (d) => setState(() => _selectedDate = d),
                  ),
                ),
                const Divider(height: 24),
                Expanded(
                  child: dayOccurrences.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'No classes on ${_fmtDate(_selectedDate)}',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed: _addOnDay,
                                  icon: const Icon(Icons.add_rounded),
                                  label: const Text('Add a class this day'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                          children: [
                            for (final occurrence in dayOccurrences) ...[
                              _OccurrenceManageCard(
                                occurrence: occurrence,
                                onEdit: _edit,
                                onReschedule: _reschedule,
                                onUndo: _undo,
                              ),
                              const SizedBox(height: 10),
                            ],
                            const SizedBox(height: 4),
                            OutlinedButton.icon(
                              onPressed: _addOnDay,
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Add another class this day'),
                            ),
                          ],
                        ),
                ),
              ],
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

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.selectedDate,
    required this.highlightedDates,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime selectedDate;
  final Set<DateTime> highlightedDates;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leadingBlanks = DateTime(month.year, month.month, 1).weekday - 1;
    final totalCells = leadingBlanks + daysInMonth;
    final rows = (totalCells / 7).ceil();

    return Column(
      children: [
        for (var row = 0; row < rows; row++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(child: _buildCell(context, row * 7 + col)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCell(BuildContext context, int cellIndex) {
    final scheme = Theme.of(context).colorScheme;
    final leadingBlanks = DateTime(month.year, month.month, 1).weekday - 1;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final dayNum = cellIndex - leadingBlanks + 1;
    if (dayNum < 1 || dayNum > daysInMonth) {
      return const SizedBox(height: 40);
    }
    final date = DateTime(month.year, month.month, dayNum);
    final isSelected =
        date.year == selectedDate.year &&
        date.month == selectedDate.month &&
        date.day == selectedDate.day;
    final isHighlighted = highlightedDates.contains(date);

    return GestureDetector(
      onTap: () => onSelect(date),
      child: Container(
        height: 40,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: isSelected ? scheme.primary : Colors.transparent,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$dayNum',
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? scheme.onPrimary : scheme.onSurface,
                fontSize: 13,
              ),
            ),
            if (isHighlighted)
              Container(
                width: 4,
                height: 4,
                margin: const EdgeInsets.only(top: 1),
                decoration: BoxDecoration(
                  color: isSelected ? scheme.onPrimary : scheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OccurrenceManageCard extends StatelessWidget {
  const _OccurrenceManageCard({
    required this.occurrence,
    required this.onEdit,
    required this.onReschedule,
    required this.onUndo,
  });

  final TimetableOccurrence occurrence;
  final ValueChanged<ScheduleSlot> onEdit;
  final ValueChanged<TimetableOccurrence> onReschedule;
  final ValueChanged<String> onUndo;

  String _fmt(WallClockTime t) {
    final period = t.hour >= 12 ? 'PM' : 'AM';
    final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$h12:${t.minute.toString().padLeft(2, '0')} $period';
  }

  String _fmtDate(DateTime d) => '${d.day}/${d.month}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final o = occurrence;

    late final Color barColor;
    late final String typeLabel;
    switch (o.sessionType) {
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

    // Editing/rescheduling act on the recurring template (schedule_id),
    // which 'normal', 'moved_away' and 'cancelled' all still have — only
    // 'moved_in'/'added' have no template behind them (they *are* the
    // exception). Undo just needs an exception to remove, which is every
    // status except 'normal'.
    final canManageTemplate = o.scheduleId != null;
    final slot = canManageTemplate
        ? ScheduleSlot(
            id: o.scheduleId!,
            courseId: o.courseId,
            courseCode: o.courseCode,
            courseName: o.courseName,
            sessionType: o.sessionType,
            dayOfWeek: o.occurrenceDate.weekday,
            startTime: o.startTime,
            endTime: o.endTime,
            roomId: o.roomId,
            roomName: o.roomName,
          )
        : null;
    final struck =
        o.status == TimetableOccurrenceStatus.cancelled ||
        o.status == TimetableOccurrenceStatus.movedAway;

    return Opacity(
      opacity: struck ? 0.7 : 1,
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
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
                    o.courseName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      decoration: struck ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (o.status != TimetableOccurrenceStatus.cancelled) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${_fmt(o.startTime)} – ${_fmt(o.endTime)}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 2),
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => CampusMapScreen(initialQuery: o.roomName),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.location_on_outlined,
                              size: 14,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              o.locationLabel,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (o.status == TimetableOccurrenceStatus.movedAway &&
                      o.movedToDate != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.tertiaryContainer,
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusPill,
                          ),
                        ),
                        child: Text(
                          'Moved to ${_fmtDate(o.movedToDate!)}, ${_fmt(o.movedToStartTime!)}',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: scheme.onTertiaryContainer,
                          ),
                        ),
                      ),
                    ),
                  if (o.status == TimetableOccurrenceStatus.cancelled)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Cancelled',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: scheme.error,
                        ),
                      ),
                    ),
                  if (o.status == TimetableOccurrenceStatus.movedIn)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Rescheduled class',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: scheme.tertiary,
                        ),
                      ),
                    ),
                  if (o.status == TimetableOccurrenceStatus.added)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Extra class',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: scheme.tertiary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (slot != null) ...[
              IconButton(
                onPressed: () => onEdit(slot),
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Edit',
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                onPressed: () => onReschedule(o),
                icon: const Icon(Icons.event_repeat_outlined),
                tooltip: 'Reschedule',
                visualDensity: VisualDensity.compact,
              ),
            ],
            if (o.exceptionId != null)
              IconButton(
                onPressed: () => onUndo(o.exceptionId!),
                icon: const Icon(Icons.undo_rounded),
                tooltip: 'Undo',
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ),
    );
  }
}
