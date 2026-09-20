import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

class BookingRepository {
  BookingRepository(this._client);
  final SupabaseClient _client;

  /// Fetches facilities and their building information.
  Future<List<BookableFacility>> fetchFacilities() async {
    final rows = await _client
        .from('facilities')
        .select('id, room_name, type, status, capacity, buildings(building_name)')
        .order('room_name');
    return (rows as List)
        .map((row) => BookableFacility.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Creates a facility booking through the backend.
  Future<BookingActionResult> createBooking({
    required String facilityId,
    required DateTime bookingDate,
    required String startTime,
    required String endTime,
    int? pax,
  }) async {
    final dateStr =
        '${bookingDate.year.toString().padLeft(4, '0')}-'
        '${bookingDate.month.toString().padLeft(2, '0')}-'
        '${bookingDate.day.toString().padLeft(2, '0')}';
    final response = await _client.rpc(
      'create_booking',
      params: {
        'p_facility_id': facilityId,
        'p_booking_date': dateStr,
        'p_start_time': startTime,
        'p_end_time': endTime,
        'p_pax': pax,
      },
    );
    return BookingActionResult.fromMap(Map<String, dynamic>.from(response as Map));
  }

  /// Fetches the signed-in user’s facility bookings.
  Future<List<Booking>> fetchMyBookings() async {
    final rows = await _client.rpc('get_my_bookings');
    return (rows as List)
        .map((row) => Booking.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Checks in a booking using the scanned NFC card.
  Future<BookingActionResult> processNfcCheckin(String rfidUid) async {
    final response = await _client.rpc(
      'process_nfc_checkin',
      params: {'p_rfid_uid': rfidUid},
    );
    return BookingActionResult.fromMap(Map<String, dynamic>.from(response as Map));
  }
}
