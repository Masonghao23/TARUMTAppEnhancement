import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

class ParkingRepository {
  ParkingRepository(this._client);

  final SupabaseClient _client;

  /// Fetches parking slot availability for the requested time window.
  Future<List<ParkingSlot>> fetchSlots({DateTime? start, DateTime? end}) async {
    final params = <String, dynamic>{};
    if (start != null) params['p_start'] = start.toUtc().toIso8601String();
    if (end != null) params['p_end'] = end.toUtc().toIso8601String();

    final rows = await _client.rpc('get_parking_slots', params: params);
    return (rows as List)
        .map((row) => ParkingSlot.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Creates a parking reservation for the selected slot and time.
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

  /// Extends the parking reservation by the requested hours.
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

  /// Ends the current parking reservation.
  Future<ParkingActionResult> finishReservation(String reservationId) async {
    final response = await _client.rpc(
      'finish_parking_reservation',
      params: {'p_reservation_id': reservationId},
    );
    return ParkingActionResult.fromMap(
      Map<String, dynamic>.from(response as Map),
    );
  }

  /// Cancels an upcoming parking reservation.
  Future<ParkingActionResult> cancelReservation(String reservationId) async {
    final response = await _client.rpc(
      'cancel_parking_reservation',
      params: {'p_reservation_id': reservationId},
    );
    return ParkingActionResult.fromMap(
      Map<String, dynamic>.from(response as Map),
    );
  }

  /// Enables or disables reservations for a parking slot.
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

  /// Fetches the user’s parking reservations.
  Future<List<ParkingReservation>> fetchMyReservations() async {
    final rows = await _client.rpc('get_my_parking_reservations');
    return (rows as List)
        .map((row) => ParkingReservation.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Fetches the user’s registered vehicles.
  Future<List<RegisteredVehicle>> fetchMyVehicles() async {
    final rows = await _client
        .from('registered_vehicles')
        .select()
        .order('plate_num');
    return rows.map(RegisteredVehicle.fromMap).toList();
  }

  /// Registers a vehicle for the current user.
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

  /// Removes a registered vehicle.
  Future<void> removeVehicle(String plateNum) async {
    await _client
        .from('registered_vehicles')
        .delete()
        .eq('plate_num', plateNum);
  }

  /// Estimates the parking fee for the selected duration.
  static double previewFee(Duration duration) {
    const ratePerHour = 2.00;
    return double.parse(
      (duration.inSeconds / 3600 * ratePerHour).toStringAsFixed(2),
    );
  }
}
