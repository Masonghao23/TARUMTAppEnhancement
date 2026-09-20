import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../data/models.dart';
import '../providers.dart';
import 'schedule_form_widgets.dart';

class RequestRescheduleScreen extends ConsumerStatefulWidget {
  const RequestRescheduleScreen({
    super.key,
    this.slot,
    this.originalDate,
    this.existingRequest,
  }) : assert(
         existingRequest != null || (slot != null && originalDate != null),
         'Either existingRequest, or both slot and originalDate, must be given.',
       );

  final ScheduleSlot? slot;
  final DateTime? originalDate;

  final RescheduleRequest? existingRequest;

  /// Returns whether an existing request is being edited.
  bool get isEdit => existingRequest != null;

  /// Creates the mutable state for this widget.
  @override
  ConsumerState<RequestRescheduleScreen> createState() =>
      _RequestRescheduleScreenState();
}

class _RequestRescheduleScreenState
    extends ConsumerState<RequestRescheduleScreen> {
  String _mode = 'move';
  late DateTime _newDate;
  late TimeOfDay _newStartTime;
  late TimeOfDay _newEndTime;
  Facility? _newRoom;
  final _reasonController = TextEditingController();
  bool _saving = false;
  bool _withdrawing = false;
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

  /// Returns the original date of the timetable occurrence.
  DateTime get _originalDate =>
      widget.originalDate ?? widget.existingRequest!.originalDate;

  /// Initializes state and starts this component’s setup.
  @override
  void initState() {
    super.initState();
    final existing = widget.existingRequest;
    if (existing != null) {
      _mode = existing.exceptionType;
      _reasonController.text = existing.reason;
      final startSource = existing.newStartTime ?? existing.originalStartTime;
      final endSource = existing.newEndTime ?? existing.originalEndTime;
      _newDate = existing.newDate ?? existing.originalDate;
      _newStartTime = TimeOfDay(
        hour: startSource.hour,
        minute: startSource.minute,
      );
      _newEndTime = TimeOfDay(hour: endSource.hour, minute: endSource.minute);
    } else {
      final slot = widget.slot!;
      _newDate = widget.originalDate!;
      _newStartTime = TimeOfDay(
        hour: slot.startTime.hour,
        minute: slot.startTime.minute,
      );
      _newEndTime = TimeOfDay(
        hour: slot.endTime.hour,
        minute: slot.endTime.minute,
      );
    }
  }

  /// Releases resources and subscriptions owned by this component.
  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  /// Opens a date picker and updates the selected date.
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _newDate,
      firstDate: _originalDate,
      lastDate: _originalDate.add(const Duration(days: 90)),
    );
    if (picked != null) setState(() => _newDate = picked);
  }

  /// Opens the start-time picker and updates the selection.
  Future<void> _pickStart() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _newStartTime,
    );
    if (picked != null) setState(() => _newStartTime = picked);
  }

  /// Opens the end-time picker and updates the selection.
  Future<void> _pickEnd() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _newEndTime,
    );
    if (picked != null) setState(() => _newEndTime = picked);
  }

  /// Validates and submits the reschedule request.
  Future<void> _save() async {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'A reason is required.');
      return;
    }
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
      final repo = ref.read(attendanceRepositoryProvider);
      final occurrenceDate = _mode == 'move' ? _newDate : null;
      final startTime = _mode == 'move'
          ? WallClockTime(_newStartTime.hour, _newStartTime.minute)
          : null;
      final endTime = _mode == 'move'
          ? WallClockTime(_newEndTime.hour, _newEndTime.minute)
          : null;
      final roomId = _mode == 'move' ? _newRoom?.id : null;

      final result = widget.isEdit
          ? await repo.updateRescheduleRequest(
              requestId: widget.existingRequest!.id,
              exceptionType: _mode,
              occurrenceDate: occurrenceDate,
              startTime: startTime,
              endTime: endTime,
              roomId: roomId,
              reason: reason,
            )
          : await repo.requestClassReschedule(
              scheduleId: widget.slot!.id,
              originalDate: _originalDate,
              exceptionType: _mode,
              occurrenceDate: occurrenceDate,
              startTime: startTime,
              endTime: endTime,
              roomId: roomId,
              reason: reason,
            );
      if (!mounted) return;
      if (!result.success) {
        setState(() => _error = result.reason ?? 'Could not submit.');
        return;
      }
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Withdraws the pending reschedule request.
  Future<void> _withdraw() async {
    setState(() => _withdrawing = true);
    try {
      final result = await ref
          .read(attendanceRepositoryProvider)
          .withdrawRescheduleRequest(widget.existingRequest!.id);
      if (!mounted) return;
      if (!result.success) {
        setState(() => _error = result.reason ?? 'Could not withdraw.');
        return;
      }
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _withdrawing = false);
    }
  }

  /// Formats a time for display.
  String _fmtTime(WallClockTime t) {
    final period = t.hour >= 12 ? 'PM' : 'AM';
    final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$h12:${t.minute.toString().padLeft(2, '0')} $period';
  }

  /// Formats a date for display.
  String _fmtDate(DateTime d) =>
      '${_dayLabels[d.weekday - 1]}, ${d.day}/${d.month}';

  /// Builds the request reschedule screen interface.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final facilitiesAsync = ref.watch(facilitiesProvider);
    final busy = _saving || _withdrawing;

    final courseName = widget.slot?.courseName ?? widget.existingRequest!.courseName;
    final sessionTypeName =
        (widget.slot?.sessionType ?? widget.existingRequest!.sessionType)
            .name;
    final originalStart = widget.slot?.startTime ?? widget.existingRequest!.originalStartTime;
    final originalEnd = widget.slot?.endTime ?? widget.existingRequest!.originalEndTime;
    final originalRoom = widget.slot?.roomName ?? widget.existingRequest!.originalRoomName;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEdit ? 'Edit request' : 'Request reschedule'),
      ),
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
                      '$courseName · ${sessionTypeName[0].toUpperCase()}${sessionTypeName.substring(1)}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Originally: ${_fmtDate(_originalDate)} · '
                      '${_fmtTime(originalStart)}–${_fmtTime(originalEnd)} · $originalRoom',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (widget.isEdit)
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
                            'Pending admin review',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: scheme.onTertiaryContainer,
                            ),
                          ),
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
                onSelectionChanged: busy
                    ? null
                    : (s) => setState(() => _mode = s.first),
              ),
              if (_mode == 'move') ...[
                const SizedBox(height: 20),
                Text(
                  'New date',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: busy ? null : _pickDate,
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
                        onTap: busy ? () {} : _pickStart,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TimePickerField(
                        label: 'New end',
                        time: _newEndTime,
                        onTap: busy ? () {} : _pickEnd,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text('Room', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                facilitiesAsync.when(
                  data: (rooms) {
                    final currentRoomId =
                        widget.existingRequest?.newRoomId;
                    if (_newRoom == null && currentRoomId != null) {
                      for (final room in rooms) {
                        if (room.id == currentRoomId) {
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
                      onChanged: busy
                          ? (_) {}
                          : (v) => setState(() => _newRoom = v),
                    );
                  },
                  loading: () => const LinearProgressIndicator(),
                  error: (_, _) => Text(
                    'Could not load rooms',
                    style: TextStyle(color: scheme.error),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Text(
                'Reason',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _reasonController,
                enabled: !busy,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'e.g. Attending a conference, room conflict…',
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
                child: Text(
                  'This won\'t take effect until an admin approves it. '
                  'You\'ll be notified either way.',
                  style: TextStyle(
                    color: scheme.onPrimaryContainer,
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
                onPressed: busy ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        widget.isEdit ? 'Save changes' : 'Submit for approval',
                      ),
              ),
              if (widget.isEdit) ...[
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: busy ? null : _withdraw,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scheme.error,
                    side: BorderSide(color: scheme.error),
                  ),
                  child: _withdrawing
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.error,
                          ),
                        )
                      : const Text('Withdraw request'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
