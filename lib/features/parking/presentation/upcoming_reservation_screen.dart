import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../providers.dart';
import 'extend_duration_dialog.dart';

/// FR05 — a reservation that hasn't started yet is still extendable, same
/// as an active one; extend_parking_reservation only checks the reservation
/// is still 'reserved', not that it's already in progress. No live
/// countdown or "Finish" here, since there's nothing running yet to end.
class UpcomingReservationScreen extends ConsumerStatefulWidget {
  const UpcomingReservationScreen({super.key, required this.reservation});

  final ParkingReservation reservation;

  @override
  ConsumerState<UpcomingReservationScreen> createState() =>
      _UpcomingReservationScreenState();
}

class _UpcomingReservationScreenState
    extends ConsumerState<UpcomingReservationScreen> {
  late ParkingReservation _reservation;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reservation = widget.reservation;
  }

  Future<void> _extend() async {
    final additionalHours = await showExtendHoursDialog(context);
    if (additionalHours == null) return;

    setState(() => _busy = true);
    try {
      final result = await ref
          .read(parkingRepositoryProvider)
          .extendReservation(
            reservationId: _reservation.id,
            additionalSeconds: additionalHours * 3600,
          );
      if (!mounted) return;
      if (!result.success) {
        // Extension only succeeds if the server's conditions are met — no
        // overlap with another reservation on the slot, and it can't push
        // past 12:00 AM. Whichever one failed, its reason is shown as-is.
        _showMessage(result.reason ?? 'Could not extend reservation.');
        return;
      }
      final newEnd = DateTime.parse(
        result.data!['newEndTime'] as String,
      ).toLocal();
      setState(() {
        _reservation = ParkingReservation(
          id: _reservation.id,
          slotId: _reservation.slotId,
          slotNumber: _reservation.slotNumber,
          plateNum: _reservation.plateNum,
          startTime: _reservation.startTime,
          endTime: newEnd,
          totalFee:
              _reservation.totalFee +
              ((result.data!['additionalFee'] as num).toDouble()),
          status: _reservation.status,
          transactionRef: result.data!['transactionRef'] as String?,
        );
      });
      ref.invalidate(myParkingReservationsProvider);
      _showMessage(
        'Extended by ${additionalHours == 1 ? '1 hour' : '$additionalHours hours'}.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel reservation?'),
        content: Text(
          'This cancels your booking for slot ${_reservation.slotNumber} on '
          '${_fmtDate(_reservation.startTime)}. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep reservation'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cancel reservation'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      final result = await ref
          .read(parkingRepositoryProvider)
          .cancelReservation(_reservation.id);
      if (!mounted) return;
      if (!result.success) {
        // Only succeeds while the reservation is still upcoming — the
        // server rejects it once the start time has already passed (an
        // active session uses Finish instead), with that reason shown here.
        _showMessage(result.reason ?? 'Could not cancel reservation.');
        return;
      }
      ref.invalidate(liveParkingSlotsProvider);
      ref.invalidate(myParkingReservationsProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

  String _fmtTime(DateTime d) => TimeOfDay.fromDateTime(d).format(context);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Upcoming reservation')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.event_available_outlined,
                size: 64,
                color: scheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'PARKING ${_reservation.slotNumber}',
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '${_fmtDate(_reservation.startTime)}, '
                '${_fmtTime(_reservation.startTime)} – '
                '${_fmtTime(_reservation.endTime)}',
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'Vehicle: ${_reservation.plateNum}',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'Total fee: RM${_reservation.totalFee.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _busy ? null : _extend,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Extend'),
              ),
              const SizedBox(height: 8),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: scheme.error),
                onPressed: _busy ? null : _cancel,
                child: const Text('Cancel reservation'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
