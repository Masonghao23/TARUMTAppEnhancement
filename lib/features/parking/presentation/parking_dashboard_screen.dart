import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../user_management/data/models.dart';
import '../../user_management/providers.dart';
import '../data/models.dart';
import '../providers.dart';
import 'active_session_screen.dart';
import 'book_slot_screen.dart';
import 'my_reservations_screen.dart';
import 'parking_floor_map.dart';

class ParkingDashboardScreen extends ConsumerStatefulWidget {
  const ParkingDashboardScreen({super.key});

  @override
  ConsumerState<ParkingDashboardScreen> createState() =>
      _ParkingDashboardScreenState();
}

class _ParkingDashboardScreenState
    extends ConsumerState<ParkingDashboardScreen> {
  bool _manageMode = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    // NFR2: parking availability shall update within 5 seconds — realtime
    // catches other users' bookings instantly, this timer also catches a
    // reservation naturally expiring (no DB write happens when time simply
    // passes, so realtime alone wouldn't notice that).
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      try {
        ref.invalidate(liveParkingSlotsProvider);
        ref.invalidate(myParkingReservationsProvider);
      } catch (_) {
        // Defensive: the ProviderScope container can be torn down
        // independently of (and slightly before) this widget's own
        // disposal during abrupt teardown (most visible in integration
        // test harnesses) — mounted can still read true in that window.
        // Nothing to do if this timer tick lands in it.
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentProfileProvider).value;
    final isStaff =
        profile?.role == UserRole.staff || profile?.role == UserRole.admin;
    final slotsAsync = ref.watch(liveParkingSlotsProvider);
    final reservationsAsync = ref.watch(myParkingReservationsProvider);

    final activeReservation = reservationsAsync.value?.firstWhereOrNull(
      (r) => r.isActiveNow,
    );
    final upcomingReservations =
        (reservationsAsync.value?.where((r) => r.isUpcoming).toList() ?? [])
          ..sort((a, b) => a.startTime.compareTo(b.startTime));

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Parking',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  slotsAsync.when(
                    data: (slots) {
                      final available = slots
                          .where((s) => s.isReservable && !s.isOccupied)
                          .length;
                      return _AvailabilityPill(
                        available: available,
                        total: slots.length,
                      );
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (_, _) => const SizedBox.shrink(),
                  ),
                  if (isStaff) ...[
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: _manageMode
                          ? 'Exit manage mode'
                          : 'Manage slots',
                      onPressed: () =>
                          setState(() => _manageMode = !_manageMode),
                      icon: Icon(
                        _manageMode
                            ? Icons.close_rounded
                            : Icons.edit_location_alt_outlined,
                      ),
                    ),
                  ],
                ],
              ),
              if (_manageMode) ...[
                const SizedBox(height: 4),
                Text(
                  'Tap a slot to toggle reservable',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              if (!_manageMode) ...[
                const SizedBox(height: 4),
                Text(
                  'Today\'s status — view only. Drive in to find an open '
                  'spot, or reserve at least 1 day ahead below.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (activeReservation != null && !_manageMode) ...[
                const SizedBox(height: 14),
                _ActiveSessionBanner(reservation: activeReservation),
              ],
              if (upcomingReservations.isNotEmpty && !_manageMode) ...[
                const SizedBox(height: 10),
                _UpcomingReservationBanner(reservations: upcomingReservations),
              ],
              const SizedBox(height: 16),
              Expanded(
                child: slotsAsync.when(
                  data: (slots) => ParkingFloorMap(
                    slots: slots,
                    allowTapWhenBlocked: _manageMode,
                    onTapSlot: _manageMode
                        ? (slot) => _onTapSlot(context, slot)
                        : null,
                  ),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Center(
                    child: Text('Could not load parking slots: $error'),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (!_manageMode)
                ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const BookSlotScreen()),
                  ),
                  icon: const Icon(Icons.local_parking_outlined),
                  label: const Text('Reserve parking'),
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  /// Only ever called in manage mode — today's slots are view-only for
  /// everyone else (bookings must be made >=1 day ahead, via "Reserve
  /// parking" below, not by tapping a slot on today's live map).
  Future<void> _onTapSlot(BuildContext context, ParkingSlot slot) async {
    final makeReservable = !slot.isReservable;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Slot ${slot.slotNumber}'),
        content: Text(
          makeReservable
              ? 'Mark this slot as reservable again?'
              : 'Mark this slot as non-reservable? Students will not be able to book it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final result = await ref
        .read(parkingRepositoryProvider)
        .setSlotReservable(slotId: slot.id, isReservable: makeReservable);
    ref.invalidate(liveParkingSlotsProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.success
              ? 'Slot ${slot.slotNumber} updated.'
              : (result.reason ?? 'Could not update slot.'),
        ),
      ),
    );
  }
}

class _AvailabilityPill extends StatelessWidget {
  const _AvailabilityPill({required this.available, required this.total});

  final int available;
  final int total;

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.success(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.successContainer(context),
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            '$available / $total free',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveSessionBanner extends StatelessWidget {
  const _ActiveSessionBanner({required this.reservation});

  final ParkingReservation reservation;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer,
      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ActiveSessionScreen(reservation: reservation),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.timer_outlined, color: scheme.onPrimaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Active session at ${reservation.slotNumber} — tap to view',
                  style: TextStyle(color: scheme.onPrimaryContainer),
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onPrimaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpcomingReservationBanner extends StatelessWidget {
  const _UpcomingReservationBanner({required this.reservations});

  /// Soonest first — only the soonest is described in the banner text, but
  /// tapping it opens the full list, not just that one reservation.
  final List<ParkingReservation> reservations;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final soonest = reservations.first;
    final start = soonest.startTime;
    final time = TimeOfDay.fromDateTime(start).format(context);
    final label = reservations.length == 1
        ? 'Upcoming: ${soonest.slotNumber} on ${start.day}/${start.month} '
              '$time — tap to view'
        : '${reservations.length} upcoming reservations — next: '
              '${soonest.slotNumber} on ${start.day}/${start.month} $time';
    return Material(
      color: scheme.secondaryContainer,
      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const MyReservationsScreen())),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                Icons.event_available_outlined,
                color: scheme.onSecondaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: scheme.onSecondaryContainer),
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSecondaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}

extension _FirstWhereOrNull<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final item in this) {
      if (test(item)) return item;
    }
    return null;
  }
}
