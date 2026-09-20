import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers.dart';
import 'booking_repository.dart';
import 'models.dart';

final bookingRepositoryProvider = Provider<BookingRepository>((ref) {
  return BookingRepository(ref.watch(supabaseClientProvider));
});

final bookableFacilitiesProvider = FutureProvider.autoDispose<List<BookableFacility>>((
  ref,
) {
  return ref.read(bookingRepositoryProvider).fetchFacilities();
});

final bookingsRealtimeProvider = StreamProvider.autoDispose<void>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client.from('bookings').stream(primaryKey: ['id']).map((_) {});
});

final myBookingsProvider = FutureProvider.autoDispose<List<Booking>>((ref) {
  ref.watch(bookingsRealtimeProvider);
  return ref.read(bookingRepositoryProvider).fetchMyBookings();
});
