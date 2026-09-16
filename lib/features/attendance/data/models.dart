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

enum AttendanceStatus { present, late, absent, leave, pending }

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
  String get wireValue => name;

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

/// One enrolled student's attendance status for a specific session, as
/// returned by get_session_roster() — a real recorded row when
/// [recordedAt] is non-null, otherwise a value computed server-side
/// ('absent' once the session has ended and the student never scanned,
/// 'pending' while it's still live). [isManual] distinguishes a lecturer's
/// override from a genuine QR scan.
class RosterEntry {
  const RosterEntry({
    required this.studentId,
    required this.studentName,
    required this.status,
    required this.isManual,
    this.recordedAt,
  });

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

enum SessionSlotType { lecture, tutorial, practical }

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

/// An hour:minute wall-clock value, as returned by Postgres `time` columns
/// ("HH:MM:SS" over PostgREST) — deliberately not a DateTime, since these
/// are schedule-of-day values with no date attached.
class WallClockTime {
  const WallClockTime(this.hour, this.minute);

  factory WallClockTime.parse(String raw) {
    final parts = raw.split(':');
    return WallClockTime(int.parse(parts[0]), int.parse(parts[1]));
  }

  final int hour;
  final int minute;

  double get decimalHours => hour + minute / 60;
}

/// One occurrence of a scheduled class within a single Mon-Sun week, as
/// returned by get_my_timetable_week() — recurrence/exception handling all
/// happens server-side, so the client only ever renders whatever comes
/// back here.
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
      // Only present in get_lecturer_occurrences' management-facing
      // output — get_my_timetable_week (student-facing) doesn't return
      // these columns at all, so they parse to null there, which is
      // correct: students have no use for them.
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

  double get durationHours => endTime.decimalHours - startTime.decimalHours;

  /// "Building · Room", or just the room if the facility has no building
  /// (matches the shared facilities table's nullable building_id).
  String get locationLabel =>
      buildingName == null ? roomName : '$buildingName · $roomName';
}

/// The shared term window every class_schedule row currently uses —
/// effective_from is Monday-aligned (see timetable_seed.sql) so "Week N" in
/// the student-facing UI can be computed as a plain day-count from it,
/// without needing partial-week handling.
class TermInfo {
  const TermInfo({required this.effectiveFrom, required this.termWeeks});

  final DateTime effectiveFrom;
  final int termWeeks;
}

/// One of a lecturer's own timetable slots for a specific date, as returned
/// by get_lecturer_schedule_for_date() — already excludes anything that's
/// been moved away or cancelled for that date, so every row here is really
/// startable. [sessionId] is populated when a class_sessions row already
/// exists for it (tap should open that session instead of starting a new
/// one).
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

  bool get isStarted => sessionId != null;
}

/// Decoded response of the start_scheduled_session RPC.
class StartSessionResult {
  const StartSessionResult({
    required this.success,
    this.sessionId,
    this.alreadyStarted = false,
    this.reason,
  });

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

/// Hour-based attendance for one student/course, from
/// calculate_course_attendance_hours() — [totalHours] is the scheduled
/// hours of every occurrence that's already passed, [attendedHours] the
/// subset of those the student actually attended.
class CourseAttendanceHours {
  const CourseAttendanceHours({
    required this.attendedHours,
    required this.totalHours,
  });

  factory CourseAttendanceHours.fromMap(Map<String, dynamic> map) {
    return CourseAttendanceHours(
      attendedHours: (map['attended_hours'] as num).toDouble(),
      totalHours: (map['total_hours'] as num).toDouble(),
    );
  }

  final double attendedHours;
  final double totalHours;

  /// Null (rather than 0) when nothing has happened yet to have a
  /// percentage at all — callers should show a placeholder, not "0%".
  double? get percent =>
      totalHours <= 0 ? null : (attendedHours / totalHours) * 100;
}

/// One recurring weekly slot a lecturer owns, as edited on the Manage
/// Timetable screen — distinct from [LecturerSlot], which is a specific
/// day's occurrence rather than the recurring template itself.
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

/// Decoded response of upsert_class_schedule/create_schedule_exception.
class ScheduleActionResult {
  const ScheduleActionResult({required this.success, this.reason, this.id});

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

enum RescheduleRequestStatus { pending, approved, rejected, withdrawn }

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

/// A lecturer's request to move or cancel one occurrence of their own
/// recurring slot, awaiting admin approval — see
/// reschedule_requests_schema.sql. RLS already scopes what a caller can
/// see (their own requests, or everything if admin), so the same fetch —
/// and the same model — serves both "My Requests" (staff) and the review
/// queue (admin); the UI decides which actions to show based on role.
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

  /// 'move' or 'cancel'.
  final String exceptionType;
  final WallClockTime originalStartTime;
  final WallClockTime originalEndTime;
  final String originalRoomName;

  /// Only set when [exceptionType] is 'move'.
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

/// One course's roll-up for the staff Attendance charts screen — it names
/// the course in the picker and feeds the headline figures above it.
/// [attendancePercent] is hour-weighted across every enrolled student
/// (sum attended / sum total), so it agrees with the figure each student
/// sees for themselves and with the 80% notification threshold.
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

  /// Null when no hours have been scheduled yet — shown as "—", never 0%.
  final double? attendancePercent;
}

/// One point on a course's attendance trend — a single session that was
/// actually held. Within one session every student shares the same
/// duration, so this is plain attended/enrolled rather than hour-weighted.
class AttendanceTrendPoint {
  const AttendanceTrendPoint({
    required this.sessionId,
    required this.sessionDate,
    required this.sessionType,
    required this.enrolledCount,
    required this.attendedCount,
    required this.attendancePercent,
  });

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

  /// Null on sessions created before session_type existed on class_sessions.
  final String? sessionType;
  final int enrolledCount;
  final int attendedCount;
  final double? attendancePercent;
}

/// One enrolled student's standing in a single course — the unit behind
/// both the pass/at-risk pie and the detail list under it.
class CourseStudentAttendance {
  const CourseStudentAttendance({
    required this.studentId,
    required this.studentName,
    required this.attendedHours,
    required this.totalHours,
    required this.attendancePercent,
  });

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

  /// Null when the course has no scheduled hours yet — such a student
  /// counts as neither meeting nor missing the requirement.
  final double? attendancePercent;

  bool get meetsThreshold =>
      attendancePercent != null && attendancePercent! >= 80;

  bool get isBelowThreshold =>
      attendancePercent != null && attendancePercent! < 80;
}
