import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../data/models.dart';
import '../providers.dart';
import 'upcoming_reservation_screen.dart';

/// Lists every upcoming (not yet started) reservation, soonest first — the
/// dashboard only ever surfaces the single soonest one as a banner, so this
/// is the place to see (and drill into) the rest.
class MyReservationsScreen extends ConsumerWidget {
  const MyReservationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reservationsAsync = ref.watch(myParkingReservationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Upcoming reservations')),
      body: SafeArea(
        child: reservationsAsync.when(
          data: (reservations) {
            final upcoming = reservations.where((r) => r.isUpcoming).toList()
              ..sort((a, b) => a.startTime.compareTo(b.startTime));
            if (upcoming.isEmpty) {
              return const Center(child: Text('No upcoming reservations.'));
            }
            return ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: upcoming.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) =>
                  _ReservationTile(reservation: upcoming[index]),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) =>
              Center(child: Text('Could not load reservations: $error')),
        ),
      ),
    );
  }
}

class _ReservationTile extends StatelessWidget {
  const _ReservationTile({required this.reservation});

  final ParkingReservation reservation;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final start = reservation.startTime;
    final end = reservation.endTime;
    final startTime = TimeOfDay.fromDateTime(start).format(context);
    final endTime = TimeOfDay.fromDateTime(end).format(context);

    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => UpcomingReservationScreen(reservation: reservation),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.event_available_outlined, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Slot ${reservation.slotNumber}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${start.day}/${start.month}/${start.year}, '
                      '$startTime – $endTime',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
