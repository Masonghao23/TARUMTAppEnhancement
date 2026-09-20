enum SessionStatus { active, ended }

/// Converts a stored session status to its enum value.
SessionStatus _sessionStatusFromString(String value) {
  return value == 'ended' ? SessionStatus.ended : SessionStatus.active;
}

class Course {
  const Course({
    required this.id,
    required this.courseCode,
    required this.courseName,
  });

  /// Creates course data from a database row.
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

  /// Returns the display label for this value.
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

  /// Creates facility data from a database row.
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

  /// Returns the display label for this value.
  String get label =>
      buildingName == null ? roomName : '$buildingName · $roomName';
}

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

  /// Creates class session data from a database row.
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

enum AttendanceStatus { present, late, absent, leave, pending }

/// Converts a stored attendance status to its enum value.
AttendanceStatus attendanceStatusFromString(String value) {
  switch (value) {
    case 'late':
      return AttendanceStatus.late;
    case 'absent':
      return AttendanceStatus.absent;
    case 'leave':
      return AttendanceStatus.leave;
    case 'pending':
      return AttendanceStatus.pending;
    default:
      return AttendanceStatus.present;
  }
}

extension AttendanceStatusLabel on AttendanceStatus {
  /// Returns the value used to store this status.
  String get wireValue => name;

  /// Returns the display label for this value.
  String get label {
    switch (this) {
      case AttendanceStatus.present:
        return 'Present';
      case AttendanceStatus.late:
        return 'Late';
      case AttendanceStatus.absent:
        return 'Absent';
      case AttendanceStatus.leave:
        return 'Leave';
      case AttendanceStatus.pending:
        return 'Pending';
    }
  }
}

class RosterEntry {
  const RosterEntry({
    required this.studentId,
    required this.studentName,
    required this.status,
    required this.isManual,
    this.recordedAt,
  });

  /// Creates roster entry data from a database row.
  factory RosterEntry.fromMap(Map<String, dynamic> map) {
    return RosterEntry(
      studentId: map['student_id'] as String,
      studentName: map['student_name'] as String? ?? '',
      status: attendanceStatusFromString(
        map['status'] as String? ?? 'pending',
      ),
      isManual: map['method'] == 'manual',
      recordedAt: map['recorded_at'] != null
          ? DateTime.parse(map['recorded_at'] as String)
          : null,
    );
  }

  final String studentId;
  final String studentName;
  final AttendanceStatus status;
  final bool isManual;
  final DateTime? recordedAt;
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

  /// Creates attendance record data from a database row.
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

class AttendanceHistoryEntry {
  const AttendanceHistoryEntry({
    required this.record,
    required this.courseName,
    this.sessionStartTime,
  });

  /// Creates attendance history entry data from a database row.
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

class AttendanceResult {
  const AttendanceResult({
    required this.success,
    this.reason,
    this.alreadyCheckedIn = false,
    this.distanceMeters,
  });

  /// Creates attendance result data from a database row.
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

enum SessionSlotType { lecture, tutorial, practical }

/// Converts a stored session type to its enum value.
SessionSlotType _slotTypeFromString(String value) {
  switch (value) {
    case 'tutorial':
      return SessionSlotType.tutorial;
    case 'practical':
      return SessionSlotType.practical;
    default:
      return SessionSlotType.lecture;
  }
}

enum TimetableOccurrenceStatus { normal, cancelled, movedAway, movedIn, added }

/// Converts a stored timetable status to its enum value.
TimetableOccurrenceStatus _occurrenceStatusFromString(String value) {
  switch (value) {
    case 'cancelled':
      return TimetableOccurrenceStatus.cancelled;
    case 'moved_away':
      return TimetableOccurrenceStatus.movedAway;
    case 'moved_in':
      return TimetableOccurrenceStatus.movedIn;
    case 'added':
      return TimetableOccurrenceStatus.added;
    default:
      return TimetableOccurrenceStatus.normal;
  }
}

class WallClockTime {
  const WallClockTime(this.hour, this.minute);

  /// Parses a stored time into hours and minutes.
  factory WallClockTime.parse(String raw) {
    final parts = raw.split(':');
    return WallClockTime(int.parse(parts[0]), int.parse(parts[1]));
  }

  final int hour;
  final int minute;

  /// Returns the time as a fractional number of hours.
  double get decimalHours => hour + minute / 60;
}

class TimetableOccurrence {
  const TimetableOccurrence({
    required this.occurrenceDate,
    required this.courseId,
    required this.courseCode,
    required this.courseName,
    required this.sessionType,
    required this.startTime,
    required this.endTime,
    required this.roomId,
    required this.roomName,
    this.buildingName,
    required this.status,
    this.movedToDate,
    this.movedToStartTime,
    this.movedToEndTime,
    this.movedToRoomId,
    this.movedToRoomName,
    this.movedToBuildingName,
    this.scheduleId,
    this.exceptionId,
  });

  /// Creates timetable occurrence data from a database row.
  factory TimetableOccurrence.fromMap(Map<String, dynamic> map) {
    return TimetableOccurrence(
      occurrenceDate: DateTime.parse(map['occurrence_date'] as String),
      courseId: map['course_id'] as String,
      courseCode: map['course_code'] as String? ?? '',
      courseName: map['course_name'] as String? ?? '',
      sessionType: _slotTypeFromString(
        map['session_type'] as String? ?? 'lecture',
      ),
      startTime: WallClockTime.parse(map['start_time'] as String),
      endTime: WallClockTime.parse(map['end_time'] as String),
      roomId: map['room_id'] as String,
      roomName: map['room_name'] as String? ?? '',
      buildingName: map['building_name'] as String?,
      status: _occurrenceStatusFromString(map['status'] as String? ?? 'normal'),
      movedToDate: map['moved_to_date'] != null
          ? DateTime.parse(map['moved_to_date'] as String)
          : null,
      movedToStartTime: map['moved_to_start_time'] != null
          ? WallClockTime.parse(map['moved_to_start_time'] as String)
          : null,
      movedToEndTime: map['moved_to_end_time'] != null
          ? WallClockTime.parse(map['moved_to_end_time'] as String)
          : null,
      movedToRoomId: map['moved_to_room_id'] as String?,
      movedToRoomName: map['moved_to_room_name'] as String?,
      movedToBuildingName: map['moved_to_building_name'] as String?,
      scheduleId: map['schedule_id'] as String?,
      exceptionId: map['exception_id'] as String?,
    );
  }

  final DateTime occurrenceDate;
  final String courseId;
  final String courseCode;
  final String courseName;
  final SessionSlotType sessionType;
  final WallClockTime startTime;
  final WallClockTime endTime;
  final String roomId;
  final String roomName;
  final String? buildingName;
  final TimetableOccurrenceStatus status;
  final DateTime? movedToDate;
  final WallClockTime? movedToStartTime;
  final WallClockTime? movedToEndTime;
  final String? movedToRoomId;
  final String? movedToRoomName;
  final String? movedToBuildingName;
  final String? scheduleId;
  final String? exceptionId;

  /// Returns the occurrence’s duration in hours.
  double get durationHours => endTime.decimalHours - startTime.decimalHours;

  /// Returns the room label with its building name when available.
  String get locationLabel =>
      buildingName == null ? roomName : '$buildingName · $roomName';
}

class TermInfo {
  const TermInfo({required this.effectiveFrom, required this.termWeeks});

  final DateTime effectiveFrom;
  final int termWeeks;
}

class LecturerSlot {
  const LecturerSlot({
    required this.scheduleId,
    required this.exceptionId,
    required this.courseId,
    required this.courseCode,
    required this.courseName,
    required this.sessionType,
    required this.startTime,
    required this.endTime,
    required this.roomId,
    required this.roomName,
    this.sessionId,
    this.sessionStatus,
  });

  /// Creates lecturer slot data from a database row.
  factory LecturerSlot.fromMap(Map<String, dynamic> map) {
    return LecturerSlot(
      scheduleId: map['schedule_id'] as String?,
      exceptionId: map['exception_id'] as String?,
      courseId: map['course_id'] as String,
      courseCode: map['course_code'] as String? ?? '',
      courseName: map['course_name'] as String? ?? '',
      sessionType: _slotTypeFromString(
        map['session_type'] as String? ?? 'lecture',
      ),
      startTime: WallClockTime.parse(map['start_time'] as String),
      endTime: WallClockTime.parse(map['end_time'] as String),
      roomId: map['room_id'] as String,
      roomName: map['room_name'] as String? ?? '',
      sessionId: map['session_id'] as String?,
      sessionStatus: map['session_status'] as String?,
    );
  }

  final String? scheduleId;
  final String? exceptionId;
  final String courseId;
  final String courseCode;
  final String courseName;
  final SessionSlotType sessionType;
  final WallClockTime startTime;
  final WallClockTime endTime;
  final String roomId;
  final String roomName;
  final String? sessionId;
  final String? sessionStatus;

  /// Returns whether this timetable occurrence has a session.
  bool get isStarted => sessionId != null;
}

class StartSessionResult {
  const StartSessionResult({
    required this.success,
    this.sessionId,
    this.alreadyStarted = false,
    this.reason,
  });

  /// Creates start session result data from a database row.
  factory StartSessionResult.fromMap(Map<String, dynamic> map) {
    return StartSessionResult(
      success: map['success'] as bool? ?? false,
      sessionId: map['sessionId'] as String?,
      alreadyStarted: map['alreadyStarted'] as bool? ?? false,
      reason: map['reason'] as String?,
    );
  }

  final bool success;
  final String? sessionId;
  final bool alreadyStarted;
  final String? reason;
}

class CourseAttendanceHours {
  const CourseAttendanceHours({
    required this.attendedHours,
    required this.totalHours,
  });

  /// Creates course attendance hours data from a database row.
  factory CourseAttendanceHours.fromMap(Map<String, dynamic> map) {
    return CourseAttendanceHours(
      attendedHours: (map['attended_hours'] as num).toDouble(),
      totalHours: (map['total_hours'] as num).toDouble(),
    );
  }

  final double attendedHours;
  final double totalHours;

  /// Returns the attendance percentage, or null when no hours are scheduled.
  double? get percent =>
      totalHours <= 0 ? null : (attendedHours / totalHours) * 100;
}

class ScheduleSlot {
  const ScheduleSlot({
    required this.id,
    required this.courseId,
    required this.courseCode,
    required this.courseName,
    required this.sessionType,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.roomId,
    required this.roomName,
  });

  /// Creates schedule slot data from a database row.
  factory ScheduleSlot.fromMap(Map<String, dynamic> map) {
    final course = map['courses'] as Map<String, dynamic>?;
    final facility = map['facilities'] as Map<String, dynamic>?;
    return ScheduleSlot(
      id: map['id'] as String,
      courseId: map['course_id'] as String,
      courseCode: course?['course_code'] as String? ?? '',
      courseName: course?['course_name'] as String? ?? '',
      sessionType: _slotTypeFromString(
        map['session_type'] as String? ?? 'lecture',
      ),
      dayOfWeek: map['day_of_week'] as int,
      startTime: WallClockTime.parse(map['start_time'] as String),
      endTime: WallClockTime.parse(map['end_time'] as String),
      roomId: map['room_id'] as String,
      roomName: facility?['room_name'] as String? ?? '',
    );
  }

  final String id;
  final String courseId;
  final String courseCode;
  final String courseName;
  final SessionSlotType sessionType;
  final int dayOfWeek;
  final WallClockTime startTime;
  final WallClockTime endTime;
  final String roomId;
  final String roomName;
}

class ScheduleActionResult {
  const ScheduleActionResult({required this.success, this.reason, this.id});

  /// Creates schedule action result data from a database row.
  factory ScheduleActionResult.fromMap(Map<String, dynamic> map) {
    return ScheduleActionResult(
      success: map['success'] as bool? ?? false,
      reason: map['reason'] as String?,
      id: (map['scheduleId'] ?? map['exceptionId'] ?? map['requestId']) as String?,
    );
  }

  final bool success;
  final String? reason;
  final String? id;
}

class ScannedSessionToken {
  const ScannedSessionToken({required this.sessionId, required this.token});

  /// Decodes a scanned attendance payload, returning null if invalid.
  static ScannedSessionToken? tryParse(String raw) {
    final parts = raw.split('|');
    if (parts.length != 2) return null;
    return ScannedSessionToken(sessionId: parts[0], token: parts[1]);
  }

  final String sessionId;
  final String token;

  /// Encodes the session ID and token as a QR payload.
  String encode() => '$sessionId|$token';
}

enum RescheduleRequestStatus { pending, approved, rejected, withdrawn }

/// Converts a stored request status to its enum value.
RescheduleRequestStatus _requestStatusFromString(String value) {
  switch (value) {
    case 'approved':
      return RescheduleRequestStatus.approved;
    case 'rejected':
      return RescheduleRequestStatus.rejected;
    case 'withdrawn':
      return RescheduleRequestStatus.withdrawn;
    default:
      return RescheduleRequestStatus.pending;
  }
}

class RescheduleRequest {
  const RescheduleRequest({
    required this.id,
    required this.scheduleId,
    required this.originalDate,
    required this.courseId,
    required this.courseName,
    required this.sessionType,
    required this.exceptionType,
    required this.originalStartTime,
    required this.originalEndTime,
    required this.originalRoomName,
    required this.reason,
    required this.requestedBy,
    required this.requesterName,
    required this.status,
    required this.createdAt,
    this.newDate,
    this.newStartTime,
    this.newEndTime,
    this.newRoomId,
    this.newRoomName,
    this.reviewComment,
  });

  /// Creates reschedule request data from a database row.
  factory RescheduleRequest.fromMap(Map<String, dynamic> map) {
    final course = map['courses'] as Map<String, dynamic>?;
    final schedule = map['class_schedule'] as Map<String, dynamic>?;
    final scheduleRoom = schedule?['facilities'] as Map<String, dynamic>?;
    final newRoom = map['new_room'] as Map<String, dynamic>?;
    final requester = map['requester'] as Map<String, dynamic>?;

    return RescheduleRequest(
      id: map['id'] as String,
      scheduleId: map['schedule_id'] as String,
      originalDate: DateTime.parse(map['original_date'] as String),
      courseId: map['course_id'] as String,
      courseName: course?['course_name'] as String? ?? '',
      sessionType: _slotTypeFromString(
        map['session_type'] as String? ?? 'lecture',
      ),
      exceptionType: map['exception_type'] as String? ?? 'move',
      originalStartTime: WallClockTime.parse(
        schedule?['start_time'] as String? ?? '00:00',
      ),
      originalEndTime: WallClockTime.parse(
        schedule?['end_time'] as String? ?? '00:00',
      ),
      originalRoomName: scheduleRoom?['room_name'] as String? ?? '',
      newDate: map['occurrence_date'] != null
          ? DateTime.parse(map['occurrence_date'] as String)
          : null,
      newStartTime: map['start_time'] != null
          ? WallClockTime.parse(map['start_time'] as String)
          : null,
      newEndTime: map['end_time'] != null
          ? WallClockTime.parse(map['end_time'] as String)
          : null,
      newRoomId: map['room_id'] as String?,
      newRoomName: newRoom?['room_name'] as String?,
      reason: map['reason'] as String? ?? '',
      requestedBy: map['requested_by'] as String,
      requesterName: requester?['name'] as String? ?? '',
      status: _requestStatusFromString(map['status'] as String? ?? 'pending'),
      reviewComment: map['review_comment'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  final String id;
  final String scheduleId;
  final DateTime originalDate;
  final String courseId;
  final String courseName;
  final SessionSlotType sessionType;

  final String exceptionType;
  final WallClockTime originalStartTime;
  final WallClockTime originalEndTime;
  final String originalRoomName;

  final DateTime? newDate;
  final WallClockTime? newStartTime;
  final WallClockTime? newEndTime;
  final String? newRoomId;
  final String? newRoomName;

  final String reason;
  final String requestedBy;
  final String requesterName;
  final RescheduleRequestStatus status;
  final String? reviewComment;
  final DateTime createdAt;
}

class CourseAttendanceSummary {
  const CourseAttendanceSummary({
    required this.courseId,
    required this.courseCode,
    required this.courseName,
    required this.studentCount,
    required this.attendedHours,
    required this.totalHours,
    required this.attendancePercent,
  });

  /// Creates course attendance summary data from a database row.
  factory CourseAttendanceSummary.fromMap(Map<String, dynamic> map) {
    return CourseAttendanceSummary(
      courseId: map['course_id'] as String,
      courseCode: map['course_code'] as String? ?? '',
      courseName: map['course_name'] as String? ?? '',
      studentCount: (map['student_count'] as num?)?.toInt() ?? 0,
      attendedHours: (map['attended_hours'] as num?)?.toDouble() ?? 0,
      totalHours: (map['total_hours'] as num?)?.toDouble() ?? 0,
      attendancePercent: (map['attendance_percent'] as num?)?.toDouble(),
    );
  }

  final String courseId;
  final String courseCode;
  final String courseName;
  final int studentCount;
  final double attendedHours;
  final double totalHours;

  final double? attendancePercent;
}

class AttendanceTrendPoint {
  const AttendanceTrendPoint({
    required this.sessionId,
    required this.sessionDate,
    required this.sessionType,
    required this.enrolledCount,
    required this.attendedCount,
    required this.attendancePercent,
  });

  /// Creates attendance trend point data from a database row.
  factory AttendanceTrendPoint.fromMap(Map<String, dynamic> map) {
    return AttendanceTrendPoint(
      sessionId: map['session_id'] as String,
      sessionDate: DateTime.parse(map['session_date'] as String),
      sessionType: map['session_type'] as String?,
      enrolledCount: (map['enrolled_count'] as num?)?.toInt() ?? 0,
      attendedCount: (map['attended_count'] as num?)?.toInt() ?? 0,
      attendancePercent: (map['attendance_percent'] as num?)?.toDouble(),
    );
  }

  final String sessionId;
  final DateTime sessionDate;

  final String? sessionType;
  final int enrolledCount;
  final int attendedCount;
  final double? attendancePercent;
}

class CourseStudentAttendance {
  const CourseStudentAttendance({
    required this.studentId,
    required this.studentName,
    required this.attendedHours,
    required this.totalHours,
    required this.attendancePercent,
  });

  /// Creates course student attendance data from a database row.
  factory CourseStudentAttendance.fromMap(Map<String, dynamic> map) {
    return CourseStudentAttendance(
      studentId: map['student_id'] as String,
      studentName: map['student_name'] as String? ?? '',
      attendedHours: (map['attended_hours'] as num?)?.toDouble() ?? 0,
      totalHours: (map['total_hours'] as num?)?.toDouble() ?? 0,
      attendancePercent: (map['attendance_percent'] as num?)?.toDouble(),
    );
  }

  final String studentId;
  final String studentName;
  final double attendedHours;
  final double totalHours;

  final double? attendancePercent;

  /// Returns whether attendance meets the required percentage.
  bool get meetsThreshold =>
      attendancePercent != null && attendancePercent! >= 80;

  /// Returns whether attendance falls below the required percentage.
  bool get isBelowThreshold =>
      attendancePercent != null && attendancePercent! < 80;
}
