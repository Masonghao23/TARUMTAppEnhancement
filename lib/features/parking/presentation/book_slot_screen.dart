import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../data/models.dart';
import '../data/parking_repository.dart';
import '../providers.dart';
import 'add_vehicle_dialog.dart';
import 'parking_floor_map.dart';

class BookSlotScreen extends ConsumerStatefulWidget {
  const BookSlotScreen({super.key});

  /// Creates the mutable state for this widget.
  @override
  ConsumerState<BookSlotScreen> createState() => _BookSlotScreenState();
}

class _BookSlotScreenState extends ConsumerState<BookSlotScreen> {
  late DateTime _date;
  late int _startHour;
  int _durationHours = 1;
  String? _selectedSlotId;
  String? _selectedPlate;
  bool _isBooking = false;

  static const _openingHour = 6;
  static const _closingHour = 24;

  late final DateTime _earliestDate;

  /// Initializes state and starts this component’s setup.
  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _earliestDate = DateTime(
      today.year,
      today.month,
      today.day,
    ).add(const Duration(days: 1));
    _date = _earliestDate;
    _startHour = _openingHour;
  }

  /// Calculates the selected parking reservation’s start time.
  DateTime get _start =>
      DateTime(_date.year, _date.month, _date.day, _startHour);

  /// Calculates the selected parking reservation’s end time.
  DateTime get _end => _start.add(Duration(hours: _durationHours));

  /// Formats an hour as a parking time label.
  String _formatHour(int hour) =>
      TimeOfDay(hour: hour, minute: 0).format(context);

  /// Checks whether the selected duration ends by closing time.
  bool _fitsBeforeMidnight(int hours) => _startHour + hours <= _closingHour;

  /// Opens a date picker and updates the selected date.
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: _earliestDate,
      lastDate: _earliestDate.add(const Duration(days: 30)),
    );
    if (picked != null) {
      setState(() {
        _date = picked;
        _selectedSlotId = null;
      });
    }
  }

  /// Increases the selected parking duration within allowed limits.
  void _incrementDuration() {
    if (!_fitsBeforeMidnight(_durationHours + 1)) return;
    setState(() {
      _durationHours++;
      _selectedSlotId = null;
    });
  }

  /// Decreases the selected parking duration within allowed limits.
  void _decrementDuration() {
    if (_durationHours <= 1) return;
    setState(() {
      _durationHours--;
      _selectedSlotId = null;
    });
  }

  /// Validates and confirms the selected parking reservation.
  Future<void> _confirm() async {
    final slotId = _selectedSlotId;
    final plate = _selectedPlate;
    if (slotId == null) {
      _showMessage('Choose a parking slot on the map.');
      return;
    }
    if (plate == null) {
      _showMessage('Choose or add a vehicle.');
      return;
    }
    if (!_fitsBeforeMidnight(_durationHours)) {
      _showMessage(
        'That duration runs past 12:00 AM — pick a shorter duration or an '
        'earlier start time.',
      );
      return;
    }

    setState(() => _isBooking = true);
    try {
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const PopScope(
            canPop: false,
            child: AlertDialog(
              content: Row(
                children: [
                  CircularProgressIndicator(strokeWidth: 2),
                  SizedBox(width: 20),
                  Text('Processing payment...'),
                ],
              ),
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (mounted) Navigator.of(context).pop();

      final result = await ref
          .read(parkingRepositoryProvider)
          .bookSlot(slotId: slotId, plateNum: plate, start: _start, end: _end);

      if (!mounted) return;
      if (!result.success) {
        _showMessage(result.reason ?? 'Booking failed.');
        ref.invalidate(parkingAvailabilityProvider);
        return;
      }

      ref.invalidate(liveParkingSlotsProvider);
      ref.invalidate(myParkingReservationsProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Parking reserved for ${_date.day}/${_date.month}/${_date.year} '
            '${_formatHour(_startHour)} — RM${result.data?['fee']}',
          ),
        ),
      );
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _isBooking = false);
    }
  }

  /// Displays a feedback message to the user.
  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Returns the selected parking slot’s display number.
  String? _selectedSlotNumber(List<ParkingSlot>? slots) {
    if (_selectedSlotId == null || slots == null) return null;
    for (final slot in slots) {
      if (slot.id == _selectedSlotId) return slot.slotNumber;
    }
    return null;
  }

  /// Builds the book slot screen interface.
  @override
  Widget build(BuildContext context) {
    final vehiclesAsync = ref.watch(myVehiclesProvider);
    final availabilityAsync = ref.watch(
      parkingAvailabilityProvider(ParkingWindow(_start, _end)),
    );
    final fee = ParkingRepository.previewFee(Duration(hours: _durationHours));

    return Scaffold(
      appBar: AppBar(title: const Text('Reserve parking')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Parking must be reserved at least 1 day in advance. '
                'Available 6:00 AM to 12:00 AM (midnight), on the hour — '
                'sessions cannot cross into the next day.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDate,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        textStyle: const TextStyle(fontSize: 12.5),
                      ),
                      icon: const Icon(Icons.calendar_today_outlined, size: 15),
                      label: Text('${_date.day}/${_date.month}/${_date.year}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _startHour,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.access_time_outlined, size: 15),
                        prefixIconConstraints: BoxConstraints(minWidth: 30),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                      ),
                      items:
                          [for (var h = _openingHour; h < _closingHour; h++) h]
                              .map(
                                (h) => DropdownMenuItem(
                                  value: h,
                                  child: Text(_formatHour(h)),
                                ),
                              )
                              .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _startHour = value;
                          _selectedSlotId = null;
                          final maxDuration = _closingHour - _startHour;
                          if (_durationHours > maxDuration) {
                            _durationHours = maxDuration;
                          }
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _durationHours > 1 ? _decrementDuration : null,
                      icon: const Icon(Icons.remove_circle_outline),
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(6),
                      constraints: const BoxConstraints(),
                    ),
                    Expanded(
                      child: Text(
                        _durationHours == 1
                            ? '1 hour'
                            : '$_durationHours hours',
                        textAlign: TextAlign.center,
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(fontSize: 14),
                      ),
                    ),
                    IconButton(
                      onPressed: _fitsBeforeMidnight(_durationHours + 1)
                          ? _incrementDuration
                          : null,
                      icon: const Icon(Icons.add_circle_outline),
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(6),
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              vehiclesAsync.when(
                data: (vehicles) {
                  if (_selectedPlate == null && vehicles.isNotEmpty) {
                    _selectedPlate = vehicles.first.plateNum;
                  }
                  return Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue:
                              vehicles.any((v) => v.plateNum == _selectedPlate)
                              ? _selectedPlate
                              : null,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                          ),
                          hint: const Text('Select vehicle'),
                          items: vehicles
                              .map(
                                (v) => DropdownMenuItem(
                                  value: v.plateNum,
                                  child: Text(v.label),
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              setState(() => _selectedPlate = value),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: () => showAddVehicleDialog(context, ref),
                        child: const Text(
                          'Add vehicle',
                          style: TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ],
                  );
                },
                loading: () => const LinearProgressIndicator(),
                error: (_, _) => TextButton(
                  onPressed: () => showAddVehicleDialog(context, ref),
                  child: const Text('Add a vehicle to continue'),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: availabilityAsync.when(
                  data: (slots) => ParkingFloorMap(
                    slots: slots,
                    selectedSlotId: _selectedSlotId,
                    onTapSlot: (slot) {
                      if (!slot.isReservable || slot.isOccupied) return;
                      setState(() => _selectedSlotId = slot.id);
                    },
                  ),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Center(
                    child: Text('Could not check availability: $error'),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _SummaryBar(
                slotNumber: _selectedSlotNumber(availabilityAsync.value),
                durationHours: _durationHours,
                fee: fee,
                busy: _isBooking,
                onConfirm: _selectedSlotId == null ? null : _confirm,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({
    required this.slotNumber,
    required this.durationHours,
    required this.fee,
    required this.busy,
    required this.onConfirm,
  });

  final String? slotNumber;
  final int durationHours;
  final double fee;
  final bool busy;
  final VoidCallback? onConfirm;

  /// Builds the summary bar interface.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.inverseSurface,
      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    slotNumber == null
                        ? 'Choose a slot on the map'
                        : 'PARKING $slotNumber',
                    style: TextStyle(
                      color: scheme.onInverseSurface,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$durationHours ${durationHours == 1 ? 'hour' : 'hours'} '
                    '· RM${fee.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: scheme.onInverseSurface.withValues(alpha: 0.7),
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: busy ? null : onConfirm,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
  }
}
