class ParkingSlot {
  const ParkingSlot({
    required this.id,
    required this.slotNumber,
    required this.posX,
    required this.posY,
    required this.isReservable,
    required this.isOccupied,
  });

  /// Creates parking slot data from a database row.
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

  /// Creates registered vehicle data from a database row.
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

  /// Returns the display label for this value.
  String get label => vehicleModel == null || vehicleModel!.isEmpty
      ? plateNum
      : '$plateNum — $vehicleModel';
}

enum ParkingReservationStatus { reserved, completed, cancelled }

/// Converts a stored parking status to its enum value.
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

  /// Creates parking reservation data from a database row.
  factory ParkingReservation.fromMap(Map<String, dynamic> map) {
    return ParkingReservation(
      id: map['id'] as String,
      slotId: map['slot_id'] as String,
      slotNumber: map['slot_number'] as String? ?? '?',
      plateNum: map['plate_num'] as String? ?? '',
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

  /// Returns the time remaining before the reservation ends.
  Duration get remaining {
    final left = endTime.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  /// Checks whether the parking reservation is currently active.
  bool get isActiveNow {
    if (status != ParkingReservationStatus.reserved) return false;
    final now = DateTime.now();
    return !now.isBefore(startTime);
  }

  /// Returns whether the reservation is reserved and has not started.
  bool get isUpcoming =>
      status == ParkingReservationStatus.reserved &&
      DateTime.now().isBefore(startTime);
}

class ParkingActionResult {
  const ParkingActionResult({required this.success, this.reason, this.data});

  /// Creates parking action result data from a database row.
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
