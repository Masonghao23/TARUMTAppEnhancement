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
    final rows = await _client
        .from('courses')
        .select()
        .order('course_code');
    return rows.map(Course.fromMap).toList();
  }

  Future<List<Facility>> fetchFacilities() async {
    final rows = await _client
        .from('facilities')
        .select('*, buildings(building_name)')
        .order('room_name');
    return rows.map(Facility.fromMap).toList();
  }

  Future<ClassSession> createSession({
    required String lecturerId,
    required String courseId,
    required String roomId,
  }) async {
    final row = await _client
        .from('class_sessions')
        .insert({
          'lecturer_id': lecturerId,
          'course_id': courseId,
          'room_id': roomId,
        })
        .select(_sessionColumns)
        .single();
    return ClassSession.fromMap(row);
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

  Stream<List<AttendanceRecord>> watchRoster(String sessionId) {
    return _client
        .from('attendance_records')
        .stream(primaryKey: ['id'])
        .eq('session_id', sessionId)
        .order('scan_timestamp')
        .map((rows) => rows.map(AttendanceRecord.fromMap).toList());
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

  Future<double> fetchAttendancePercentage({
    required String studentId,
    required String courseId,
  }) async {
    final response = await _client.rpc(
      'calculate_attendance_percentage',
      params: {'p_student_id': studentId, 'p_course_id': courseId},
    );
    return (response as num).toDouble();
  }
}
