import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers.dart';
import 'data/models.dart';
import 'data/parking_repository.dart';

final parkingRepositoryProvider = Provider<ParkingRepository>((ref) {
  return ParkingRepository(ref.watch(supabaseClientProvider));
});

final parkingReservationsRealtimeProvider = StreamProvider.autoDispose<void>((
  ref,
) {
  final client = ref.watch(supabaseClientProvider);
  return client
      .from('parking_reservations')
      .stream(primaryKey: ['id'])
      .map((_) {});
});

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

  /// Compares parking windows by their start and end times.
  @override
  bool operator ==(Object other) =>
      other is ParkingWindow && other.start == start && other.end == end;

  /// Computes a hash from the parking window’s start and end times.
  @override
  int get hashCode => Object.hash(start, end);
}

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
