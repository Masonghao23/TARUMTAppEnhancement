import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

class AttendanceRepository {
  AttendanceRepository(this._client);

  final SupabaseClient _client;

  static const _sessionColumns =
      'id, course_id, room_id, lecturer_id, qr_interval_seconds, '
      'status, start_time, end_time';

  /// Fetches the available courses.
  Future<List<Course>> fetchCourses() async {
    final rows = await _client.from('courses').select().order('course_code');
    return rows.map(Course.fromMap).toList();
  }

  /// Fetches facilities and their building information.
  Future<List<Facility>> fetchFacilities() async {
    final rows = await _client
        .from('facilities')
        .select('*, buildings(building_name)')
        .order('room_name');
    return rows.map(Facility.fromMap).toList();
  }

  /// Fetches the lecturer’s startable timetable slots for a date.
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

  /// Starts a scheduled class or returns its existing session.
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

  /// Formats a date for database requests.
  static String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// Formats a wall-clock time for database requests.
  static String _timeOnly(WallClockTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  /// Creates or updates a recurring timetable slot.
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

  /// Moves, cancels, or adds a timetable occurrence.
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

  /// Removes a timetable exception to undo a schedule change.
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

  /// Submits a class reschedule or cancellation request for approval.
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

  /// Updates the requester’s pending reschedule request.
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

  /// Withdraws the requester’s pending reschedule request.
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

  /// Approves or rejects a reschedule request.
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

  /// Fetches reschedule requests visible to the current user.
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

  /// Fetches the session’s QR signing seed.
  Future<String> fetchSessionSeed(String sessionId) async {
    final response = await _client.rpc(
      'get_session_seed',
      params: {'p_session_id': sessionId},
    );
    return response as String;
  }

  /// Marks a class session as ended.
  Future<void> endSession(String sessionId) async {
    await _client
        .from('class_sessions')
        .update({
          'status': 'ended',
          'end_time': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', sessionId);
  }

  /// Fetches the lecturer’s recent class sessions.
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

  /// Fetches the lecturer’s active class sessions.
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

  /// Fetches a page of ended sessions filtered by course and date.
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

  /// Streams present and late attendance records for a session.
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

  /// Fetches every enrolled student’s attendance status for a session.
  Future<List<RosterEntry>> fetchSessionRoster(String sessionId) async {
    final rows = await _client.rpc(
      'get_session_roster',
      params: {'p_session_id': sessionId},
    );
    return (rows as List)
        .map((row) => RosterEntry.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Sets a student’s attendance status for a session.
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

  /// Submits an attendance check-in for server validation.
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

  /// Fetches display names for the supplied user IDs.
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

  /// Fetches the student’s attendance history.
  Future<List<AttendanceHistoryEntry>> fetchMyHistory(String studentId) async {
    final rows = await _client
        .from('attendance_records')
        .select('*, class_sessions(start_time, courses(course_name))')
        .eq('student_id', studentId)
        .order('scan_timestamp', ascending: false)
        .limit(100);
    return rows.map(AttendanceHistoryEntry.fromMap).toList();
  }

  /// Fetches the courses the student is enrolled in.
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

  /// Fetches timetable occurrences for the selected week.
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

  /// Fetches the lecturer’s timetable occurrences within a date range.
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

  /// Fetches the shared term dates or returns default term information.
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

  /// Fetches the student’s attended and scheduled course hours.
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

  /// Fetches attendance summaries for courses visible to the caller.
  Future<List<CourseAttendanceSummary>> fetchCourseAttendanceSummary() async {
    final rows = await _client.rpc('get_staff_course_attendance');
    return (rows as List)
        .map((r) => CourseAttendanceSummary.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// Fetches attendance trend points for a course.
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

  /// Fetches each student’s attendance standing in a course.
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
