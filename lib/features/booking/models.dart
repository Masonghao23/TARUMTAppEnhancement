class BookableFacility {
  const BookableFacility({
    required this.id,
    required this.roomName,
    required this.type,
    required this.status,
    required this.capacity,
    required this.buildingName,
  });

  /// Creates bookable facility data from a database row.
  factory BookableFacility.fromMap(Map<String, dynamic> map) {
    final building = map['buildings'] as Map<String, dynamic>?;
    return BookableFacility(
      id: map['id'] as String,
      roomName: map['room_name'] as String? ?? '?',
      type: map['type'] as String?,
      status: map['status'] as String? ?? 'available',
      capacity: map['capacity'] as int?,
      buildingName: building?['building_name'] as String?,
    );
  }

  final String id;
  final String roomName;
  final String? type;
  final String status;
  final int? capacity;
  final String? buildingName;

  /// Returns whether the facility is available for booking.
  bool get isAvailable => status == 'available';
}

class Booking {
  const Booking({
    required this.id,
    required this.facilityId,
    required this.roomName,
    required this.facilityType,
    required this.buildingName,
    required this.bookingDate,
    required this.startTime,
    required this.endTime,
    required this.pax,
    required this.status,
    required this.createdAt,
  });

  /// Creates booking data from a database row.
  factory Booking.fromMap(Map<String, dynamic> map) {
    return Booking(
      id: map['id'] as String,
      facilityId: map['facility_id'] as String,
      roomName: map['room_name'] as String? ?? '?',
      facilityType: map['facility_type'] as String?,
      buildingName: map['building_name'] as String?,
      bookingDate: DateTime.parse(map['booking_date'] as String),
      startTime: map['start_time'] as String,
      endTime: map['end_time'] as String,
      pax: map['pax'] as int?,
      status: map['status'] as String,
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
    );
  }

  final String id;
  final String facilityId;
  final String roomName;
  final String? facilityType;
  final String? buildingName;
  final DateTime bookingDate;
  final String startTime;
  final String endTime;
  final int? pax;
  final String status;
  final DateTime createdAt;
}

class BookingActionResult {
  const BookingActionResult({required this.success, this.reason, this.data});

  /// Creates booking action result data from a database row.
  factory BookingActionResult.fromMap(Map<String, dynamic> map) {
    return BookingActionResult(
      success: map['success'] as bool? ?? false,
      reason: map['reason'] as String?,
      data: map,
    );
  }

  final bool success;
  final String? reason;
  final Map<String, dynamic>? data;
}
