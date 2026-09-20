import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../campus_map/campus_map_screen.dart';
import '../data/models.dart';
import '../providers.dart';

class TimetableScreen extends ConsumerStatefulWidget {
  const TimetableScreen({super.key, this.forLecturer = false});

  final bool forLecturer;

  /// Creates the mutable state for this widget.
  @override
  ConsumerState<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends ConsumerState<TimetableScreen> {
  late DateTime _weekStart;
  late DateTime _selectedDay;

  /// Initializes state and starts this component’s setup.
  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    final todayDateOnly = DateTime(today.year, today.month, today.day);
    _weekStart = todayDateOnly.subtract(
      Duration(days: todayDateOnly.weekday - 1),
    );
    _selectedDay = todayDateOnly;
  }

  /// Changes the timetable’s displayed week.
  void _changeWeek(int deltaWeeks) {
    setState(() {
      _weekStart = _weekStart.add(Duration(days: 7 * deltaWeeks));
      _selectedDay = _weekStart;
    });
  }

  /// Checks whether two dates fall on the same calendar day.
  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Formats the date range of the displayed week.
  String _weekRangeLabel() {
    final end = _weekStart.add(const Duration(days: 4));
    return '${_weekStart.day}/${_weekStart.month} – ${end.day}/${end.month}';
  }

  /// Builds the timetable screen interface.
  @override
  Widget build(BuildContext context) {
    final occurrencesAsync = ref.watch(
      widget.forLecturer
          ? myLecturerTimetableWeekProvider(_weekStart)
          : myTimetableWeekProvider(_weekStart),
    );
    final termInfo = ref.watch(termInfoProvider).value;

    final weekNumber = termInfo == null
        ? null
        : (_weekStart.difference(termInfo.effectiveFrom).inDays ~/ 7) + 1;
    final atFirstWeek = weekNumber != null && weekNumber <= 1;
    final atLastWeek =
        termInfo != null &&
        weekNumber != null &&
        weekNumber >= termInfo.termWeeks;

    return Scaffold(
      appBar: AppBar(title: const Text('My Timetable')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: atFirstWeek ? null : () => _changeWeek(-1),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          weekNumber == null ? 'This week' : 'Week $weekNumber',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          _weekRangeLabel(),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: atLastWeek ? null : () => _changeWeek(1),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  for (var i = 0; i < 5; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    Expanded(
                      child: _DayPill(
                        date: _weekStart.add(Duration(days: i)),
                        selected: _isSameDay(
                          _weekStart.add(Duration(days: i)),
                          _selectedDay,
                        ),
                        onTap: () => setState(
                          () =>
                              _selectedDay = _weekStart.add(Duration(days: i)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: occurrencesAsync.when(
                data: (occurrences) {
                  final dayOccurrences =
                      occurrences
                          .where(
                            (o) => _isSameDay(o.occurrenceDate, _selectedDay),
                          )
                          .toList()
                        ..sort(
                          (a, b) => a.startTime.decimalHours.compareTo(
                            b.startTime.decimalHours,
                          ),
                        );
                  if (dayOccurrences.isEmpty) {
                    return Center(
                      child: Text(
                        'No classes scheduled',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    itemCount: dayOccurrences.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) =>
                        _OccurrenceCard(occurrence: dayOccurrences[index]),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) =>
                    Center(child: Text('Could not load timetable: $error')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayPill extends StatelessWidget {
  const _DayPill({
    required this.date,
    required this.selected,
    required this.onTap,
  });

  final DateTime date;
  final bool selected;
  final VoidCallback onTap;

  static const _labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  /// Builds the day pill interface.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primary : scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              Text(
                _labels[date.weekday - 1],
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? scheme.onPrimary.withValues(alpha: 0.85)
                      : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${date.day}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: selected ? scheme.onPrimary : scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OccurrenceCard extends StatelessWidget {
  const _OccurrenceCard({required this.occurrence});

  final TimetableOccurrence occurrence;

  /// Formats a time for display.
  String _fmtTime(WallClockTime t) {
    final period = t.hour >= 12 ? 'PM' : 'AM';
    final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$h12:${t.minute.toString().padLeft(2, '0')} $period';
  }

  /// Formats a date for display.
  String _fmtDate(DateTime d) => '${d.day}/${d.month}';

  /// Builds the occurrence card interface.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final o = occurrence;
    final cancelled = o.status == TimetableOccurrenceStatus.cancelled;
    final movedAway = o.status == TimetableOccurrenceStatus.movedAway;
    final struck = cancelled || movedAway;

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

    return Opacity(
      opacity: struck ? 0.55 : 1,
      child: Container(
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
                    o.courseName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      decoration: struck ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (!cancelled) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${_fmtTime(o.startTime)} – ${_fmtTime(o.endTime)}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 2),
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              CampusMapScreen(initialQuery: o.roomName),
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
                              color: scheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              o.locationLabel,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: scheme.primary,
                                    decoration: TextDecoration.underline,
                                    decorationColor: scheme.primary.withValues(
                                      alpha: 0.4,
                                    ),
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (movedAway && o.movedToDate != null)
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
                          'Moved to ${_fmtDate(o.movedToDate!)}, ${_fmtTime(o.movedToStartTime!)}',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: scheme.onTertiaryContainer,
                          ),
                        ),
                      ),
                    ),
                  if (cancelled)
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
          ],
        ),
      ),
    );
  }
}
