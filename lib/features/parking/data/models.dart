class ParkingSlot {
  const ParkingSlot({
    required this.id,
    required this.slotNumber,
    required this.posX,
    required this.posY,
    required this.isReservable,
    required this.isOccupied,
  });

  factory ParkingSlot.fromMap(Map<String, dynamic> map) {
    return ParkingSlot(
      id: map['id'] as String,
      slotNumber: map['slot_number'] as String? ?? '?',
      posX: (map['pos_x'] as num).toDouble(),
      posY: (map['pos_y'] as num).toDouble(),
      isReservable: map['is_reservable'] as bool? ?? true,
      isOccupied: map['is_occupied'] as bool? ?? false,
    );
  }

  final String id;
  final String slotNumber;
  final double posX;
  final double posY;
  final bool isReservable;
  final bool isOccupied;
}

class RegisteredVehicle {
  const RegisteredVehicle({
    required this.plateNum,
    required this.userId,
    this.vehicleModel,
  });

  factory RegisteredVehicle.fromMap(Map<String, dynamic> map) {
    return RegisteredVehicle(
      plateNum: map['plate_num'] as String,
      userId: map['user_id'] as String,
      vehicleModel: map['vehicle_model'] as String?,
    );
  }

  final String plateNum;
  final String userId;
  final String? vehicleModel;

  String get label => vehicleModel == null || vehicleModel!.isEmpty
      ? plateNum
      : '$plateNum — $vehicleModel';
}

enum ParkingReservationStatus { reserved, completed, cancelled }

ParkingReservationStatus _statusFromString(String value) {
  switch (value) {
    case 'completed':
      return ParkingReservationStatus.completed;
    case 'cancelled':
      return ParkingReservationStatus.cancelled;
    default:
      return ParkingReservationStatus.reserved;
  }
}

class ParkingReservation {
  const ParkingReservation({
    required this.id,
    required this.slotId,
    required this.slotNumber,
    required this.plateNum,
    required this.startTime,
    required this.endTime,
    required this.totalFee,
    required this.status,
    this.transactionRef,
  });

  factory ParkingReservation.fromMap(Map<String, dynamic> map) {
    return ParkingReservation(
      id: map['id'] as String,
      slotId: map['slot_id'] as String,
      slotNumber: map['slot_number'] as String? ?? '?',
      plateNum: map['plate_num'] as String? ?? '',
      // .toLocal() up front so every screen reading .day/.hour or feeding
      // this into TimeOfDay.fromDateTime() gets the device's local time —
      // otherwise those read the raw UTC components straight off the
      // parsed (UTC-offset) string instead of Malaysia local time.
      startTime: DateTime.parse(map['start_time'] as String).toLocal(),
      endTime: DateTime.parse(map['end_time'] as String).toLocal(),
      totalFee: (map['total_fee'] as num?)?.toDouble() ?? 0,
      status: _statusFromString(map['status'] as String? ?? 'reserved'),
      transactionRef: map['transaction_ref'] as String?,
    );
  }

  final String id;
  final String slotId;
  final String slotNumber;
  final String plateNum;
  final DateTime startTime;
  final DateTime endTime;
  final double totalFee;
  final ParkingReservationStatus status;
  final String? transactionRef;

  Duration get remaining {
    final left = endTime.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  bool get isActiveNow {
    if (status != ParkingReservationStatus.reserved) return false;
    final now = DateTime.now();
    // Bookings are always for a future day, so a reservation is only
    // "active" once that day has actually arrived — not merely because it
    // hasn't ended yet (a reservation starting tomorrow would otherwise
    // read as active today). Deliberately NOT also requiring
    // now.isBefore(endTime): a reservation that's run past its scheduled
    // end without ever being Finished (an overstay) must still show up
    // here rather than disappearing into a gap between this and
    // [isUpcoming] — that's exactly the state ActiveSessionScreen already
    // handles gracefully ("Time's up" + a working Finish button), and the
    // one place the student can actually clear it to free up their
    // one-reservation cap slot.
    return !now.isBefore(startTime);
  }

  /// A reservation that hasn't started yet — still extendable/cancellable,
  /// just not "active" (no live countdown, nothing to finish early).
  bool get isUpcoming =>
      status == ParkingReservationStatus.reserved &&
      DateTime.now().isBefore(startTime);
}

/// Decoded {success, reason?, ...} jsonb response shared by every parking
/// RPC (book/extend/finish/cancel/set-reservable) — every rule (overlap,
/// ownership, staff-only) is enforced server-side, so the client only ever
/// renders whatever comes back here.
class ParkingActionResult {
  const ParkingActionResult({required this.success, this.reason, this.data});

  factory ParkingActionResult.fromMap(Map<String, dynamic> map) {
    return ParkingActionResult(
      success: map['success'] as bool? ?? false,
      reason: map['reason'] as String?,
      data: map,
    );
  }

  final bool success;
  final String? reason;
  final Map<String, dynamic>? data;
}
