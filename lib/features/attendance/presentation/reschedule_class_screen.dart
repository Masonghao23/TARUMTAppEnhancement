import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../data/models.dart';
import '../providers.dart';
import 'schedule_form_widgets.dart';

/// Stage 3 of the Timetable feature — move or cancel one occurrence of a
/// recurring slot (a "replacement class"), without touching the recurring
/// pattern itself. [originalDate] is the specific calendar date of the
/// occurrence being changed.
class RescheduleClassScreen extends ConsumerStatefulWidget {
  const RescheduleClassScreen({
    super.key,
    required this.slot,
    required this.originalDate,
    this.currentMoveDate,
    this.currentMoveStartTime,
    this.currentMoveEndTime,
    this.currentMoveRoomId,
    this.currentMoveRoomName,
  });

  final ScheduleSlot slot;
  final DateTime originalDate;

  /// When this occurrence has already been moved once, its current
  /// destination — pre-fills the form with where it moved to, so
  /// rescheduling again edits that instead of starting over from the
  /// recurring template's usual day/time.
  final DateTime? currentMoveDate;
  final WallClockTime? currentMoveStartTime;
  final WallClockTime? currentMoveEndTime;
  final String? currentMoveRoomId;
  final String? currentMoveRoomName;

  @override
  ConsumerState<RescheduleClassScreen> createState() =>
      _RescheduleClassScreenState();
}

class _RescheduleClassScreenState extends ConsumerState<RescheduleClassScreen> {
  String _mode = 'move';
  late DateTime _newDate;
  late TimeOfDay _newStartTime;
  late TimeOfDay _newEndTime;
  Facility? _newRoom;
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
    _newDate = widget.currentMoveDate ?? widget.originalDate;
    final startSource = widget.currentMoveStartTime ?? widget.slot.startTime;
    final endSource = widget.currentMoveEndTime ?? widget.slot.endTime;
    _newStartTime = TimeOfDay(
      hour: startSource.hour,
      minute: startSource.minute,
    );
    _newEndTime = TimeOfDay(hour: endSource.hour, minute: endSource.minute);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _newDate,
      firstDate: widget.originalDate,
      lastDate: widget.originalDate.add(const Duration(days: 90)),
    );
    if (picked != null) setState(() => _newDate = picked);
  }

  Future<void> _pickStart() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _newStartTime,
    );
    if (picked != null) setState(() => _newStartTime = picked);
  }

  Future<void> _pickEnd() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _newEndTime,
    );
    if (picked != null) setState(() => _newEndTime = picked);
  }

  Future<void> _save() async {
    if (_mode == 'move') {
      final room = _newRoom;
      if (room == null) {
        setState(() => _error = 'Choose a room for the new time.');
        return;
      }
      final start = WallClockTime(_newStartTime.hour, _newStartTime.minute);
      final end = WallClockTime(_newEndTime.hour, _newEndTime.minute);
      if (end.decimalHours <= start.decimalHours) {
        setState(() => _error = 'End time must be after start time.');
        return;
      }
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(attendanceRepositoryProvider)
          .createScheduleException(
            exceptionType: _mode,
            scheduleId: widget.slot.id,
            originalDate: widget.originalDate,
            occurrenceDate: _mode == 'move' ? _newDate : null,
            startTime: _mode == 'move'
                ? WallClockTime(_newStartTime.hour, _newStartTime.minute)
                : null,
            endTime: _mode == 'move'
                ? WallClockTime(_newEndTime.hour, _newEndTime.minute)
                : null,
            roomId: _mode == 'move' ? _newRoom?.id : null,
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

  String _fmtTime(WallClockTime t) {
    final period = t.hour >= 12 ? 'PM' : 'AM';
    final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$h12:${t.minute.toString().padLeft(2, '0')} $period';
  }

  String _fmtDate(DateTime d) =>
      '${_dayLabels[d.weekday - 1]}, ${d.day}/${d.month}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final facilitiesAsync = ref.watch(facilitiesProvider);
    final slot = widget.slot;

    return Scaffold(
      appBar: AppBar(title: const Text('Reschedule class')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${slot.courseName} · ${slot.sessionType.name[0].toUpperCase()}${slot.sessionType.name.substring(1)}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Originally: ${_fmtDate(widget.originalDate)} · '
                      '${_fmtTime(slot.startTime)}–${_fmtTime(slot.endTime)} · ${slot.roomName}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (widget.currentMoveDate != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Currently moved to: ${_fmtDate(widget.currentMoveDate!)} · '
                          '${_fmtTime(widget.currentMoveStartTime!)}–${_fmtTime(widget.currentMoveEndTime!)}'
                          '${widget.currentMoveRoomName != null ? ' · ${widget.currentMoveRoomName}' : ''}',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: scheme.tertiary),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'move', label: Text('Move')),
                  ButtonSegment(value: 'cancel', label: Text('Cancel')),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
              if (_mode == 'move') ...[
                const SizedBox(height: 20),
                Text(
                  'New date',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    ),
                    child: Text(
                      _fmtDate(_newDate),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TimePickerField(
                        label: 'New start',
                        time: _newStartTime,
                        onTap: _pickStart,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TimePickerField(
                        label: 'New end',
                        time: _newEndTime,
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
                    if (_newRoom == null && widget.currentMoveRoomId != null) {
                      for (final room in rooms) {
                        if (room.id == widget.currentMoveRoomId) {
                          _newRoom = room;
                          break;
                        }
                      }
                    }
                    return DropdownPickerField<Facility>(
                      items: rooms,
                      value: _newRoom,
                      labelOf: (r) => r.label,
                      hint: 'Select room',
                      onChanged: (v) => setState(() => _newRoom = v),
                    );
                  },
                  loading: () => const LinearProgressIndicator(),
                  error: (_, _) => Text(
                    'Could not load rooms',
                    style: TextStyle(color: scheme.error),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
                child: Text(
                  _mode == 'move'
                      ? 'Students will see this class struck through on its original day, with a link to the new time.'
                      : 'Students will see this class marked cancelled for that date only — the recurring slot is unaffected.',
                  style: TextStyle(
                    color: scheme.onTertiaryContainer,
                    fontSize: 12.5,
                  ),
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
                    : Text(
                        _mode == 'move'
                            ? 'Save reschedule'
                            : 'Cancel this class',
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
