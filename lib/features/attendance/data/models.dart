enum SessionStatus { active, ended }

SessionStatus _sessionStatusFromString(String value) {
  return value == 'ended' ? SessionStatus.ended : SessionStatus.active;
}

class Course {
  const Course({
    required this.id,
    required this.courseCode,
    required this.courseName,
  });

  factory Course.fromMap(Map<String, dynamic> map) {
    return Course(
      id: map['id'] as String,
      courseCode: map['course_code'] as String? ?? '',
      courseName: map['course_name'] as String? ?? '',
    );
  }

  final String id;
  final String courseCode;
  final String courseName;

  String get label => '$courseCode — $courseName';
}

class Facility {
  const Facility({
    required this.id,
    required this.roomName,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    this.buildingName,
  });

  factory Facility.fromMap(Map<String, dynamic> map) {
    final building = map['buildings'] as Map<String, dynamic>?;
    return Facility(
      id: map['id'] as String,
      roomName: map['room_name'] as String? ?? '',
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      radiusMeters: map['radius_meters'] as int? ?? 50,
      buildingName: building?['building_name'] as String?,
    );
  }

  final String id;
  final String roomName;
  final double latitude;
  final double longitude;
  final int radiusMeters;
  final String? buildingName;

  String get label =>
      buildingName == null ? roomName : '$buildingName · $roomName';
}

/// A live/ended class session. [courseName]/[roomName] are only populated
/// when fetched through a query that embeds `courses`/`facilities` — plain
/// insert/update responses leave them null.
class ClassSession {
  const ClassSession({
    required this.id,
    required this.courseId,
    required this.roomId,
    required this.lecturerId,
    required this.qrIntervalSeconds,
    required this.status,
    required this.startTime,
    this.endTime,
    this.courseName,
    this.roomName,
  });

  factory ClassSession.fromMap(Map<String, dynamic> map) {
    final course = map['courses'] as Map<String, dynamic>?;
    final facility = map['facilities'] as Map<String, dynamic>?;
    return ClassSession(
      id: map['id'] as String,
      courseId: map['course_id'] as String,
      roomId: map['room_id'] as String,
      lecturerId: map['lecturer_id'] as String,
      qrIntervalSeconds: map['qr_interval_seconds'] as int? ?? 20,
      status: _sessionStatusFromString(map['status'] as String? ?? 'active'),
      startTime: DateTime.parse(map['start_time'] as String),
      endTime: map['end_time'] != null
          ? DateTime.parse(map['end_time'] as String)
          : null,
      courseName: course?['course_name'] as String?,
      roomName: facility?['room_name'] as String?,
    );
  }

  final String id;
  final String courseId;
  final String roomId;
  final String lecturerId;
  final int qrIntervalSeconds;
  final SessionStatus status;
  final DateTime startTime;
  final DateTime? endTime;
  final String? courseName;
  final String? roomName;
}

class AttendanceRecord {
  const AttendanceRecord({
    required this.id,
    required this.sessionId,
    required this.studentId,
    required this.scanTimestamp,
    required this.status,
    required this.deviceIdentifier,
    this.distanceMeters,
  });

  factory AttendanceRecord.fromMap(Map<String, dynamic> map) {
    return AttendanceRecord(
      id: map['id'] as String,
      sessionId: map['session_id'] as String,
      studentId: map['student_id'] as String,
      scanTimestamp: DateTime.parse(map['scan_timestamp'] as String),
      status: map['status'] as String? ?? 'present',
      deviceIdentifier: map['device_identifier'] as String? ?? '',
      distanceMeters: map['distance_meters'] != null
          ? (map['distance_meters'] as num).toDouble()
          : null,
    );
  }

  final String id;
  final String sessionId;
  final String studentId;
  final DateTime scanTimestamp;
  final String status;
  final String deviceIdentifier;
  final double? distanceMeters;
}

/// One row of a student's attendance history, joined with the module name
/// and start time of the session it belongs to.
class AttendanceHistoryEntry {
  const AttendanceHistoryEntry({
    required this.record,
    required this.courseName,
    this.sessionStartTime,
  });

  factory AttendanceHistoryEntry.fromMap(Map<String, dynamic> map) {
    final session = map['class_sessions'] as Map<String, dynamic>?;
    final course = session?['courses'] as Map<String, dynamic>?;
    return AttendanceHistoryEntry(
      record: AttendanceRecord.fromMap(map),
      courseName: course?['course_name'] as String? ?? 'Unknown course',
      sessionStartTime: session?['start_time'] != null
          ? DateTime.parse(session!['start_time'] as String)
          : null,
    );
  }

  final AttendanceRecord record;
  final String courseName;
  final DateTime? sessionStartTime;
}

/// Decoded response of the `submit_attendance` RPC — every check-in rule
/// (enrollment, token freshness, geofence, device binding) is enforced
/// server-side, so the client only ever renders whatever comes back here.
class AttendanceResult {
  const AttendanceResult({
    required this.success,
    this.reason,
    this.alreadyCheckedIn = false,
    this.distanceMeters,
  });

  factory AttendanceResult.fromMap(Map<String, dynamic> map) {
    return AttendanceResult(
      success: map['success'] as bool? ?? false,
      reason: map['reason'] as String?,
      alreadyCheckedIn: map['already_checked_in'] as bool? ?? false,
      distanceMeters: map['distance_meters'] != null
          ? (map['distance_meters'] as num).toDouble()
          : null,
    );
  }

  final bool success;
  final String? reason;
  final bool alreadyCheckedIn;
  final double? distanceMeters;
}

/// Decoded {session_id, token} payload from a scanned QR code.
class ScannedSessionToken {
  const ScannedSessionToken({required this.sessionId, required this.token});

  static ScannedSessionToken? tryParse(String raw) {
    final parts = raw.split('|');
    if (parts.length != 2) return null;
    return ScannedSessionToken(sessionId: parts[0], token: parts[1]);
  }

  final String sessionId;
  final String token;

  String encode() => '$sessionId|$token';
}
