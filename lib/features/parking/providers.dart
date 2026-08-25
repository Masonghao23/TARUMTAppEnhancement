import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers.dart';
import 'data/models.dart';
import 'data/parking_repository.dart';

final parkingRepositoryProvider = Provider<ParkingRepository>((ref) {
  return ParkingRepository(ref.watch(supabaseClientProvider));
});

/// Ticks whenever any parking_reservations row changes, so the live
/// dashboard can refetch promptly instead of only on its polling timer
/// (NFR2: parking availability shall update within 5 seconds).
final parkingReservationsRealtimeProvider = StreamProvider.autoDispose<void>((
  ref,
) {
  final client = ref.watch(supabaseClientProvider);
  return client
      .from('parking_reservations')
      .stream(primaryKey: ['id'])
      .map((_) {});
});

/// Occupancy "right now" for the live dashboard/floor map.
final liveParkingSlotsProvider = FutureProvider.autoDispose<List<ParkingSlot>>((
  ref,
) {
  ref.watch(parkingReservationsRealtimeProvider);
  return ref.read(parkingRepositoryProvider).fetchSlots();
});

class ParkingWindow {
  const ParkingWindow(this.start, this.end);

  final DateTime start;
  final DateTime end;

  @override
  bool operator ==(Object other) =>
      other is ParkingWindow && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// Availability for a specific future date/time + duration the user is
/// choosing in the booking flow — separate from [liveParkingSlotsProvider]
/// since this is keyed by an explicit window, not "now".
final parkingAvailabilityProvider = FutureProvider.autoDispose
    .family<List<ParkingSlot>, ParkingWindow>((ref, window) {
      ref.watch(parkingReservationsRealtimeProvider);
      return ref
          .read(parkingRepositoryProvider)
          .fetchSlots(start: window.start, end: window.end);
    });

final myVehiclesProvider = FutureProvider.autoDispose<List<RegisteredVehicle>>((
  ref,
) {
  return ref.read(parkingRepositoryProvider).fetchMyVehicles();
});

final myParkingReservationsProvider =
    FutureProvider.autoDispose<List<ParkingReservation>>((ref) {
      ref.watch(parkingReservationsRealtimeProvider);
      return ref.read(parkingRepositoryProvider).fetchMyReservations();
    });
