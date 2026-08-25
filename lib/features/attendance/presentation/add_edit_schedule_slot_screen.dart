import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../data/models.dart';
import '../providers.dart';
import 'schedule_form_widgets.dart';

/// Stage 3 of the Timetable feature — create or edit one recurring weekly
/// slot. [existing] null means "add slot"; non-null means "edit slot".
/// [initialDayOfWeek]/[initialCourseId] only apply when adding (pre-filled
/// from whichever day/course the Manage Timetable calendar was showing),
/// and are ignored when [existing] is set.
class AddEditScheduleSlotScreen extends ConsumerStatefulWidget {
  const AddEditScheduleSlotScreen({
    super.key,
    this.existing,
    this.initialDayOfWeek,
    this.initialCourseId,
  });

  final ScheduleSlot? existing;
  final int? initialDayOfWeek;
  final String? initialCourseId;

  @override
  ConsumerState<AddEditScheduleSlotScreen> createState() =>
      _AddEditScheduleSlotScreenState();
}

class _AddEditScheduleSlotScreenState
    extends ConsumerState<AddEditScheduleSlotScreen> {
  Course? _course;
  Facility? _room;
  SessionSlotType _sessionType = SessionSlotType.lecture;
  late int _dayOfWeek;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  bool _saving = false;
  String? _error;

  static const _dayLabels = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _dayOfWeek = existing?.dayOfWeek ?? widget.initialDayOfWeek ?? 1;
    _startTime = existing == null
        ? const TimeOfDay(hour: 9, minute: 0)
        : TimeOfDay(
            hour: existing.startTime.hour,
            minute: existing.startTime.minute,
          );
    _endTime = existing == null
        ? const TimeOfDay(hour: 11, minute: 0)
        : TimeOfDay(
            hour: existing.endTime.hour,
            minute: existing.endTime.minute,
          );
    _sessionType = existing?.sessionType ?? SessionSlotType.lecture;
  }

  Future<void> _pickStart() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (picked != null) setState(() => _startTime = picked);
  }

  Future<void> _pickEnd() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
    );
    if (picked != null) setState(() => _endTime = picked);
  }

  Future<void> _save() async {
    final course = _course;
    final room = _room;
    if (course == null || room == null) {
      setState(() => _error = 'Choose a course and a room.');
      return;
    }
    final start = WallClockTime(_startTime.hour, _startTime.minute);
    final end = WallClockTime(_endTime.hour, _endTime.minute);
    if (end.decimalHours <= start.decimalHours) {
      setState(() => _error = 'End time must be after start time.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(attendanceRepositoryProvider)
          .upsertClassSchedule(
            id: widget.existing?.id,
            courseId: course.id,
            sessionType: _sessionType,
            roomId: room.id,
            dayOfWeek: _dayOfWeek,
            startTime: start,
            endTime: end,
          );
      if (!mounted) return;
      if (!result.success) {
        setState(() => _error = result.reason ?? 'Could not save.');
        return;
      }
      // The pushing screen (TimetableCalendarScreen) refreshes its own
      // occurrences provider when this route pops, since it's the one
      // that knows which month/course-filter key is currently showing.
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final coursesAsync = ref.watch(coursesProvider);
    final facilitiesAsync = ref.watch(facilitiesProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Add slot' : 'Edit slot'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Course', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              coursesAsync.when(
                data: (courses) {
                  _course ??= _findById(
                    courses,
                    (c) => c.id,
                    widget.existing?.courseId ?? widget.initialCourseId,
                  );
                  return DropdownPickerField<Course>(
                    items: courses,
                    value: _course,
                    labelOf: (c) => c.label,
                    hint: 'Select course',
                    onChanged: (v) => setState(() => _course = v),
                  );
                },
                loading: () => const LinearProgressIndicator(),
                error: (_, _) => Text(
                  'Could not load courses',
                  style: TextStyle(color: scheme.error),
                ),
              ),
              const SizedBox(height: 20),
              Text('Type', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SegmentedButton<SessionSlotType>(
                segments: const [
                  ButtonSegment(
                    value: SessionSlotType.lecture,
                    label: Text('Lecture'),
                  ),
                  ButtonSegment(
                    value: SessionSlotType.tutorial,
                    label: Text('Tutorial'),
                  ),
                  ButtonSegment(
                    value: SessionSlotType.practical,
                    label: Text('Practical'),
                  ),
                ],
                selected: {_sessionType},
                onSelectionChanged: (selection) =>
                    setState(() => _sessionType = selection.first),
              ),
              const SizedBox(height: 20),
              Text('Day', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              DropdownPickerField<int>(
                items: List.generate(7, (i) => i + 1),
                value: _dayOfWeek,
                labelOf: (d) => _dayLabels[d - 1],
                hint: 'Select day',
                onChanged: (v) => setState(() => _dayOfWeek = v ?? _dayOfWeek),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TimePickerField(
                      label: 'Start',
                      time: _startTime,
                      onTap: _pickStart,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TimePickerField(
                      label: 'End',
                      time: _endTime,
                      onTap: _pickEnd,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text('Room', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              facilitiesAsync.when(
                data: (rooms) {
                  _room ??= _findById(
                    rooms,
                    (r) => r.id,
                    widget.existing?.roomId,
                  );
                  return DropdownPickerField<Facility>(
                    items: rooms,
                    value: _room,
                    labelOf: (r) => r.label,
                    hint: 'Select room',
                    onChanged: (v) => setState(() => _room = v),
                  );
                },
                loading: () => const LinearProgressIndicator(),
                error: (_, _) => Text(
                  'Could not load rooms',
                  style: TextStyle(color: scheme.error),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(color: scheme.onErrorContainer),
                  ),
                ),
              ],
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  T? _findById<T>(List<T> items, String Function(T) idOf, String? targetId) {
    if (targetId == null) return null;
    for (final item in items) {
      if (idOf(item) == targetId) return item;
    }
    return null;
  }
}
