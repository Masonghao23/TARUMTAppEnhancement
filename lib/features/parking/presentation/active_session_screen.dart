import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../providers.dart';
import 'extend_duration_dialog.dart';

/// FR05 — extend an active parking session; also the mockup's "Finish"
/// action to end early. Extension payment is simulated the same way
/// booking is.
class ActiveSessionScreen extends ConsumerStatefulWidget {
  const ActiveSessionScreen({super.key, required this.reservation});

  final ParkingReservation reservation;

  @override
  ConsumerState<ActiveSessionScreen> createState() =>
      _ActiveSessionScreenState();
}

class _ActiveSessionScreenState extends ConsumerState<ActiveSessionScreen> {
  late ParkingReservation _reservation;
  Timer? _ticker;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reservation = widget.reservation;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Duration get _totalDuration =>
      _reservation.endTime.difference(_reservation.startTime);

  double get _progress {
    final total = _totalDuration.inSeconds;
    if (total <= 0) return 0;
    return (_reservation.remaining.inSeconds / total).clamp(0, 1);
  }

  Future<void> _finish() async {
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(parkingRepositoryProvider)
          .finishReservation(_reservation.id);
      if (!mounted) return;
      ref.invalidate(liveParkingSlotsProvider);
      ref.invalidate(myParkingReservationsProvider);
      if (result.success) {
        Navigator.of(context).pop();
      } else {
        _showMessage(result.reason ?? 'Could not finish session.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
        _showMessage(result.reason ?? 'Could not extend session.');
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
      ref.invalidate(liveParkingSlotsProvider);
      ref.invalidate(myParkingReservationsProvider);
      _showMessage(
        'Extended by ${additionalHours == 1 ? '1 hour' : '$additionalHours hours'}.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _fmt(Duration d) {
    final h = d.inHours.remainder(24).toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inDays > 0) {
      return '${d.inDays}d ${h}h ${m}m';
    }
    if (d.inHours > 0) {
      return '${d.inHours}h ${m}m ${s}s';
    }
    return '${m}m ${s}s';
  }

  String _fmtDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    if (minutes == 0) {
      return hours == 1 ? '1 hour' : '$hours hours';
    }
    return '${hours}h ${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final remaining = _reservation.remaining;
    final ended = remaining == Duration.zero;

    return Scaffold(
      appBar: AppBar(title: const Text('Parking session')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Remaining time',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: 220,
                height: 220,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 220,
                      height: 220,
                      child: CircularProgressIndicator(
                        value: _progress == 0 && !ended ? null : _progress,
                        strokeWidth: 10,
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.directions_car_filled,
                          color: scheme.primary,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          ended ? 'Time\'s up' : _fmt(remaining),
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'PARKING ${_reservation.slotNumber}, Duration '
                '${_fmtDuration(_totalDuration)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Total fee so far: RM${_reservation.totalFee.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _busy ? null : _finish,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Finish'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : _extend,
                child: const Text('Extend'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
