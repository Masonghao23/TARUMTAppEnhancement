import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

class ParkingRepository {
  ParkingRepository(this._client);

  final SupabaseClient _client;

  /// Live occupancy for every slot over [start, end) — defaults to "right
  /// now" for the dashboard, or pass a future date/duration window to check
  /// availability before booking. Every rule lives in get_parking_slots()
  /// server-side (see parking_schema.sql), never trusted/recomputed here.
  Future<List<ParkingSlot>> fetchSlots({DateTime? start, DateTime? end}) async {
    final params = <String, dynamic>{};
    if (start != null) params['p_start'] = start.toUtc().toIso8601String();
    if (end != null) params['p_end'] = end.toUtc().toIso8601String();

    final rows = await _client.rpc('get_parking_slots', params: params);
    return (rows as List)
        .map((row) => ParkingSlot.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  Future<ParkingActionResult> bookSlot({
    required String slotId,
    required String plateNum,
    required DateTime start,
    required DateTime end,
  }) async {
    final response = await _client.rpc(
      'book_parking_slot',
      params: {
        'p_slot_id': slotId,
        'p_plate_num': plateNum,
        'p_start': start.toUtc().toIso8601String(),
        'p_end': end.toUtc().toIso8601String(),
      },
    );
    return ParkingActionResult.fromMap(
      Map<String, dynamic>.from(response as Map),
    );
  }

  Future<ParkingActionResult> extendReservation({
    required String reservationId,
    required int additionalSeconds,
  }) async {
    final response = await _client.rpc(
      'extend_parking_reservation',
      params: {
        'p_reservation_id': reservationId,
        'p_additional_seconds': additionalSeconds,
      },
    );
    return ParkingActionResult.fromMap(
      Map<String, dynamic>.from(response as Map),
    );
  }

  Future<ParkingActionResult> finishReservation(String reservationId) async {
    final response = await _client.rpc(
      'finish_parking_reservation',
      params: {'p_reservation_id': reservationId},
    );
    return ParkingActionResult.fromMap(
      Map<String, dynamic>.from(response as Map),
    );
  }

  Future<ParkingActionResult> cancelReservation(String reservationId) async {
    final response = await _client.rpc(
      'cancel_parking_reservation',
      params: {'p_reservation_id': reservationId},
    );
    return ParkingActionResult.fromMap(
      Map<String, dynamic>.from(response as Map),
    );
  }

  /// FR08 — staff-only; enforced again server-side regardless of caller.
  Future<ParkingActionResult> setSlotReservable({
    required String slotId,
    required bool isReservable,
  }) async {
    final response = await _client.rpc(
      'set_parking_slot_reservable',
      params: {'p_slot_id': slotId, 'p_is_reservable': isReservable},
    );
    return ParkingActionResult.fromMap(
      Map<String, dynamic>.from(response as Map),
    );
  }

  Future<List<ParkingReservation>> fetchMyReservations() async {
    final rows = await _client.rpc('get_my_parking_reservations');
    return (rows as List)
        .map((row) => ParkingReservation.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  Future<List<RegisteredVehicle>> fetchMyVehicles() async {
    final rows = await _client
        .from('registered_vehicles')
        .select()
        .order('plate_num');
    return rows.map(RegisteredVehicle.fromMap).toList();
  }

  Future<void> addVehicle({
    required String plateNum,
    String? vehicleModel,
  }) async {
    final userId = _client.auth.currentUser!.id;
    await _client.from('registered_vehicles').insert({
      'plate_num': plateNum.trim().toUpperCase(),
      'user_id': userId,
      'vehicle_model': vehicleModel?.trim(),
    });
  }

  Future<void> removeVehicle(String plateNum) async {
    await _client
        .from('registered_vehicles')
        .delete()
        .eq('plate_num', plateNum);
  }

  /// Client-side preview only, for instant fee feedback while the user picks
  /// a duration — the authoritative fee always comes back from the
  /// book/extend RPC response, which is what actually gets recorded. Must
  /// be kept in sync with parking_rate_per_hour() in parking_schema.sql.
  static double previewFee(Duration duration) {
    const ratePerHour = 2.00;
    return double.parse(
      (duration.inSeconds / 3600 * ratePerHour).toStringAsFixed(2),
    );
  }
}
