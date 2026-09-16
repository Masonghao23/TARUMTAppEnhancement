import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

class AttendanceRepository {
  AttendanceRepository(this._client);

  final SupabaseClient _client;

  // class_sessions only grants column-level SELECT on these columns —
  // dynamic_qr_seed is deliberately excluded (see attendance_schema.sql).
  // Requesting `*` against a column-restricted grant fails the whole
  // query, so every read of this table must list columns explicitly.
  static const _sessionColumns =
      'id, course_id, room_id, lecturer_id, qr_interval_seconds, '
      'status, start_time, end_time';

  Future<List<Course>> fetchCourses() async {
    final rows = await _client.from('courses').select().order('course_code');
    return rows.map(Course.fromMap).toList();
  }

  Future<List<Facility>> fetchFacilities() async {
    final rows = await _client
        .from('facilities')
        .select('*, buildings(building_name)')
        .order('room_name');
    return rows.map(Facility.fromMap).toList();
  }

  /// This week's/today's real timetable slots this lecturer can start a
  /// session for — "starting a session" means starting one of these, never
  /// a freehand course+room pick (see start_scheduled_session below).
  Future<List<LecturerSlot>> fetchLecturerScheduleForDate({
    required String lecturerId,
    required DateTime date,
  }) async {
    final rows = await _client.rpc(
      'get_lecturer_schedule_for_date',
      params: {'p_lecturer_id': lecturerId, 'p_date': _dateOnly(date)},
    );
    return (rows as List)
        .map((row) => LecturerSlot.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Idempotent — calling this again for a slot that's already been
  /// started returns that same session (alreadyStarted: true) rather than
  /// creating a duplicate or erroring.
  Future<StartSessionResult> startScheduledSession({
    String? scheduleId,
    String? exceptionId,
    required DateTime occurrenceDate,
  }) async {
    final response = await _client.rpc(
      'start_scheduled_session',
      params: {
        'p_schedule_id': scheduleId,
        'p_exception_id': exceptionId,
        'p_occurrence_date': _dateOnly(occurrenceDate),
      },
    );
    return StartSessionResult.fromMap(
      Map<String, dynamic>.from(response as Map),
    );
  }

  static String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static String _timeOnly(WallClockTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  /// [id] null creates a new recurring slot; non-null edits that slot.
  Future<ScheduleActionResult> upsertClassSchedule({
    String? id,
    required String courseId,
    required SessionSlotType sessionType,
    required String roomId,
    required int dayOfWeek,
    required WallClockTime startTime,
    required WallClockTime endTime,
  }) async {
    final response = await _client.rpc(
      'upsert_class_schedule',
      params: {
        'p_id': id,
        'p_course_id': courseId,
        'p_session_type': sessionType.name,
        'p_room_id': roomId,
        'p_day_of_week': dayOfWeek,
        'p_start_time': _timeOnly(startTime),
        'p_end_time': _timeOnly(endTime),
      },
    );
    return ScheduleActionResult.fromMap(
      Map<String, dynamic>.from(response as Map),
    );
  }

  /// [exceptionType] is 'move', 'cancel', or 'add' — see
  /// timetable_stage3_schema.sql for which fields each one needs.
  Future<ScheduleActionResult> createScheduleException({
    required String exceptionType,
    String? scheduleId,
    DateTime? originalDate,
    String? courseId,
    SessionSlotType? sessionType,
    String? roomId,
    DateTime? occurrenceDate,
    WallClockTime? startTime,
    WallClockTime? endTime,
  }) async {
    final response = await _client.rpc(
      'create_schedule_exception',
      params: {
        'p_exception_type': exceptionType,
        'p_schedule_id': scheduleId,
        'p_original_date': originalDate == null
            ? null
            : _dateOnly(originalDate),
        'p_course_id': courseId,
        'p_session_type': sessionType?.name,
        'p_room_id': roomId,
        'p_occurrence_date': occurrenceDate == null
            ? null
            : _dateOnly(occurrenceDate),
        'p_start_time': startTime == null ? null : _timeOnly(startTime),
        'p_end_time': endTime == null ? null : _timeOnly(endTime),
      },
    );
    return ScheduleActionResult.fromMap(
      Map<String, dynamic>.from(response as Map),
    );
  }

  /// Reverts a move/cancel back to the normal recurring occurrence, or
  /// removes a standalone 'add' — the "Undo" action.
  Future<ScheduleActionResult> removeScheduleException(
    String exceptionId,
  ) async {
    final response = await _client.rpc(
      'remove_schedule_exception',
      params: {'p_exception_id': exceptionId},
    );
    return ScheduleActionResult.fromMap(
      Map<String, dynamic>.from(response as Map),
    );
  }

  /// Staff-only — submits a reschedule/cancel as a pending request instead
  /// of writing the exception directly (admin still reschedules instantly
  /// via createScheduleException above; see request_class_reschedule for
  /// the ownership/role check that enforces this split).
  Future<ScheduleActionResult> requestClassReschedule({
    required String scheduleId,
    required DateTime originalDate,
    required String exceptionType,
    DateTime? occurrenceDate,
    WallClockTime? startTime,
    WallClockTime? endTime,
    String? roomId,
    required String reason,
  }) async {
    final response = await _client.rpc(
      'request_class_reschedule',
      params: {
        'p_schedule_id': scheduleId,
        'p_original_date': _dateOnly(originalDate),
        'p_exception_type': exceptionType,
        'p_occurrence_date': occurrenceDate == null
            ? null
            : _dateOnly(occurrenceDate),
        'p_start_time': startTime == null ? null : _timeOnly(startTime),
        'p_end_time': endTime == null ? null : _timeOnly(endTime),
        'p_room_id': roomId,
        'p_reason': reason,
      },
    );
    return ScheduleActionResult.fromMap(
      Map<String, dynamic>.from(response as Map),
    );
  }

  /// The requester changes their own still-pending request.
  Future<ScheduleActionResult> updateRescheduleRequest({
    required String requestId,
    required String exceptionType,
    DateTime? occurrenceDate,
    WallClockTime? startTime,
    WallClockTime? endTime,
    String? roomId,
    required String reason,
  }) async {
    final response = await _client.rpc(
      'update_reschedule_request',
      params: {
        'p_request_id': requestId,
        'p_exception_type': exceptionType,
        'p_occurrence_date': occurrenceDate == null
            ? null
            : _dateOnly(occurrenceDate),
        'p_start_time': startTime == null ? null : _timeOnly(startTime),
        'p_end_time': endTime == null ? null : _timeOnly(endTime),
        'p_room_id': roomId,
        'p_reason': reason,
      },
    );
    return ScheduleActionResult.fromMap(
      Map<String, dynamic>.from(response as Map),
    );
  }

  /// The requester withdraws their own still-pending request.
  Future<ScheduleActionResult> withdrawRescheduleRequest(
    String requestId,
  ) async {
    final response = await _client.rpc(
      'withdraw_reschedule_request',
      params: {'p_request_id': requestId},
    );
    return ScheduleActionResult.fromMap(
      Map<String, dynamic>.from(response as Map),
    );
  }

  /// Admin-only — approving actually applies the change via
  /// create_schedule_exception server-side; rejecting leaves the timetable
  /// untouched. [comment] is optional either way, shown to the requester.
  Future<ScheduleActionResult> reviewRescheduleRequest({
    required String requestId,
    required String decision,
    String? comment,
  }) async {
    final response = await _client.rpc(
      'review_reschedule_request',
      params: {
        'p_request_id': requestId,
        'p_decision': decision,
        'p_comment': comment,
      },
    );
    return ScheduleActionResult.fromMap(
      Map<String, dynamic>.from(response as Map),
    );
  }

  /// RLS scopes this to the caller's own requests, or every request if
  /// they're admin — see reschedule_requests_schema.sql.
  Future<List<RescheduleRequest>> fetchRescheduleRequests() async {
    final rows = await _client
        .from('reschedule_requests')
        .select(
          '*, courses(course_name), '
          'class_schedule(start_time, end_time, facilities(room_name)), '
          'new_room:facilities!reschedule_requests_room_id_fkey(room_name), '
          'requester:profiles!reschedule_requests_requested_by_fkey(name)',
        )
        .order('created_at', ascending: false);
    return rows.map(RescheduleRequest.fromMap).toList();
  }

  /// The QR seed is only ever readable through this RPC (see
  /// attendance_schema.sql) so that no student can read it straight off the
  /// class_sessions row and fabricate a token without scanning a live QR.
  Future<String> fetchSessionSeed(String sessionId) async {
    final response = await _client.rpc(
      'get_session_seed',
      params: {'p_session_id': sessionId},
    );
    return response as String;
  }

  Future<void> endSession(String sessionId) async {
    await _client
        .from('class_sessions')
        .update({
          'status': 'ended',
          'end_time': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', sessionId);
  }

  Future<List<ClassSession>> fetchMySessions(String lecturerId) async {
    final rows = await _client
        .from('class_sessions')
        .select(
          '$_sessionColumns, courses(course_name, course_code), facilities(room_name)',
        )
        .eq('lecturer_id', lecturerId)
        .order('start_time', ascending: false)
        .limit(50);
    return rows.map(ClassSession.fromMap).toList();
  }

  /// Only this lecturer's currently-active sessions — powers the "Live now"
  /// list on the main Attendance tab. Unbounded on purpose: unlike the full
  /// history, there will only ever be a small handful of sessions truly
  /// active at once, so a 50-row cap shared with history isn't the right
  /// fit here — a session could in principle be excluded by 50+ more
  /// recent *ended* sessions even though it's still live.
  Future<List<ClassSession>> fetchActiveSessions(String lecturerId) async {
    final rows = await _client
        .from('class_sessions')
        .select(
          '$_sessionColumns, courses(course_name, course_code), facilities(room_name)',
        )
        .eq('lecturer_id', lecturerId)
        .eq('status', 'active')
        .order('start_time', ascending: false);
    return rows.map(ClassSession.fromMap).toList();
  }

  /// One page of this lecturer's ended sessions, filtered server-side by
  /// course/date — unlike [fetchMySessions], this doesn't filter a capped
  /// client-side snapshot (which can only ever "see" the 50 most recent
  /// sessions overall, silently hiding older ones from any filter no
  /// matter how narrow). Call again with an increasing [offset] — equal to
  /// how many rows have been loaded so far — for "load more"; [limit] rows
  /// returned means there may be another page.
  Future<List<ClassSession>> fetchSessionHistoryPage({
    required String lecturerId,
    String? courseId,
    DateTime? date,
    required int offset,
    int limit = 20,
  }) async {
    var query = _client
        .from('class_sessions')
        .select(
          '$_sessionColumns, courses(course_name, course_code), facilities(room_name)',
        )
        .eq('lecturer_id', lecturerId)
        .eq('status', 'ended');
    if (courseId != null) {
      query = query.eq('course_id', courseId);
    }
    if (date != null) {
      final dayStart = DateTime(date.year, date.month, date.day);
      final dayEnd = dayStart.add(const Duration(days: 1));
      query = query
          .gte('start_time', dayStart.toUtc().toIso8601String())
          .lt('start_time', dayEnd.toUtc().toIso8601String());
    }
    final rows = await query
        .order('start_time', ascending: false)
        .range(offset, offset + limit - 1);
    return rows.map(ClassSession.fromMap).toList();
  }

  /// The live "Checked in" list — real scans only. The realtime stream API
  /// only supports the one equality filter, so 'absent'/'leave' rows (which
  /// only exist from a lecturer's manual override, see [setAttendanceStatus])
  /// are filtered out client-side rather than in the query itself.
  Stream<List<AttendanceRecord>> watchRoster(String sessionId) {
    return _client
        .from('attendance_records')
        .stream(primaryKey: ['id'])
        .eq('session_id', sessionId)
        .order('scan_timestamp')
        .map(
          (rows) => rows
              .map(AttendanceRecord.fromMap)
              .where((r) => r.status == 'present' || r.status == 'late')
              .toList(),
        );
  }

  /// Every student enrolled in this session's course with their current
  /// attendance status — includes students who never scanned (shown as
  /// 'absent'/'pending', not stored as a real row until overridden). Powers
  /// the lecturer's "Manage attendance" screen.
  Future<List<RosterEntry>> fetchSessionRoster(String sessionId) async {
    final rows = await _client.rpc(
      'get_session_roster',
      params: {'p_session_id': sessionId},
    );
    return (rows as List)
        .map((row) => RosterEntry.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Lecturer override of one student's status for a session — works for a
  /// live session or one that's already ended.
  Future<ScheduleActionResult> setAttendanceStatus({
    required String sessionId,
    required String studentId,
    required AttendanceStatus status,
  }) async {
    final response = await _client.rpc(
      'set_attendance_status',
      params: {
        'p_session_id': sessionId,
        'p_student_id': studentId,
        'p_status': status.wireValue,
      },
    );
    return ScheduleActionResult.fromMap(
      Map<String, dynamic>.from(response as Map),
    );
  }

  Future<AttendanceResult> submitAttendance({
    required String sessionId,
    required String token,
    required String deviceIdentifier,
    required double latitude,
    required double longitude,
  }) async {
    final response = await _client.rpc(
      'submit_attendance',
      params: {
        'p_session_id': sessionId,
        'p_token': token,
        'p_device_identifier': deviceIdentifier,
        'p_latitude': latitude,
        'p_longitude': longitude,
      },
    );
    return AttendanceResult.fromMap(Map<String, dynamic>.from(response as Map));
  }

  /// Batch-resolves display names for a live roster, which only streams
  /// raw attendance_records rows (Supabase realtime `.stream()` cannot
  /// embed a join to `profiles`).
  Future<Map<String, String>> fetchNamesByIds(List<String> userIds) async {
    if (userIds.isEmpty) return {};
    final rows = await _client
        .from('profiles')
        .select('id, name')
        .inFilter('id', userIds);
    return {
      for (final row in rows) row['id'] as String: row['name'] as String? ?? '',
    };
  }

  Future<List<AttendanceHistoryEntry>> fetchMyHistory(String studentId) async {
    final rows = await _client
        .from('attendance_records')
        .select('*, class_sessions(start_time, courses(course_name))')
        .eq('student_id', studentId)
        .order('scan_timestamp', ascending: false)
        .limit(100);
    return rows.map(AttendanceHistoryEntry.fromMap).toList();
  }

  Future<List<Course>> fetchMyEnrolledCourses(String studentId) async {
    final rows = await _client
        .from('course_enrollments')
        .select('courses(id, course_code, course_name)')
        .eq('student_id', studentId);
    return rows
        .map((row) => row['courses'] as Map<String, dynamic>?)
        .whereType<Map<String, dynamic>>()
        .map(Course.fromMap)
        .toList();
  }

  Future<List<TimetableOccurrence>> fetchMyTimetableWeek({
    required String studentId,
    required DateTime weekStart,
  }) async {
    final weekStartDate =
        '${weekStart.year.toString().padLeft(4, '0')}-'
        '${weekStart.month.toString().padLeft(2, '0')}-'
        '${weekStart.day.toString().padLeft(2, '0')}';
    final rows = await _client.rpc(
      'get_my_timetable_week',
      params: {'p_student_id': studentId, 'p_week_start': weekStartDate},
    );
    return (rows as List)
        .map((row) => TimetableOccurrence.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// A lecturer's own occurrences across an arbitrary date range (a
  /// calendar month, for the Manage Timetable flow), optionally narrowed
  /// to a set of courses. Null/empty [courseIds] means "every course".
  Future<List<TimetableOccurrence>> fetchLecturerOccurrences({
    required String lecturerId,
    required List<String> courseIds,
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await _client.rpc(
      'get_lecturer_occurrences',
      params: {
        'p_lecturer_id': lecturerId,
        'p_course_ids': courseIds.isEmpty ? null : courseIds,
        'p_from': _dateOnly(from),
        'p_to': _dateOnly(to),
      },
    );
    return (rows as List)
        .map((row) => TimetableOccurrence.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Every class_schedule row currently shares one effective_from/
  /// term_weeks (one shared university-wide term, not per-course), so the
  /// first row is representative — falls back to "this Monday, 12 weeks"
  /// if the timetable hasn't been seeded yet.
  Future<TermInfo> fetchTermInfo() async {
    final rows = await _client
        .from('class_schedule')
        .select('effective_from, term_weeks')
        .limit(1);
    if (rows.isEmpty) {
      final today = DateTime.now();
      final monday = DateTime(
        today.year,
        today.month,
        today.day,
      ).subtract(Duration(days: today.weekday - 1));
      return TermInfo(effectiveFrom: monday, termWeeks: 12);
    }
    final row = rows.first;
    return TermInfo(
      effectiveFrom: DateTime.parse(row['effective_from'] as String),
      termWeeks: row['term_weeks'] as int,
    );
  }

  Future<CourseAttendanceHours> fetchCourseAttendanceHours({
    required String studentId,
    required String courseId,
  }) async {
    final rows = await _client.rpc(
      'calculate_course_attendance_hours',
      params: {'p_student_id': studentId, 'p_course_id': courseId},
    );
    return CourseAttendanceHours.fromMap(
      (rows as List).first as Map<String, dynamic>,
    );
  }

  /// Staff analytics — each of these is scoped server-side to the courses
  /// the caller actually teaches (admin sees all), so there's no course
  /// filter to pass and nothing useful comes back for a student.
  Future<List<CourseAttendanceSummary>> fetchCourseAttendanceSummary() async {
    final rows = await _client.rpc('get_staff_course_attendance');
    return (rows as List)
        .map((r) => CourseAttendanceSummary.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<AttendanceTrendPoint>> fetchCourseAttendanceTrend(
    String courseId,
  ) async {
    final rows = await _client.rpc(
      'get_course_attendance_trend',
      params: {'p_course_id': courseId},
    );
    return (rows as List)
        .map((r) => AttendanceTrendPoint.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<CourseStudentAttendance>> fetchCourseStudentAttendance(
    String courseId,
  ) async {
    final rows = await _client.rpc(
      'get_course_student_attendance',
      params: {'p_course_id': courseId},
    );
    return (rows as List)
        .map((r) => CourseStudentAttendance.fromMap(r as Map<String, dynamic>))
        .toList();
  }
}
