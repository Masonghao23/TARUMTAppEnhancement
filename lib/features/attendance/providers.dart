import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/location_service.dart';
import '../auth/providers.dart';
import '../user_management/providers.dart';
import 'data/attendance_repository.dart';
import 'data/models.dart';

final attendanceRepositoryProvider = Provider<AttendanceRepository>((ref) {
  return AttendanceRepository(ref.watch(supabaseClientProvider));
});

final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});

final coursesProvider = FutureProvider.autoDispose<List<Course>>((ref) {
  return ref.watch(attendanceRepositoryProvider).fetchCourses();
});

final facilitiesProvider = FutureProvider.autoDispose<List<Facility>>((ref) {
  return ref.watch(attendanceRepositoryProvider).fetchFacilities();
});

final mySessionsProvider = FutureProvider.autoDispose
    .family<List<ClassSession>, String>((ref, lecturerId) {
      return ref
          .watch(attendanceRepositoryProvider)
          .fetchMySessions(lecturerId);
    });

final activeSessionsProvider = FutureProvider.autoDispose
    .family<List<ClassSession>, String>((ref, lecturerId) {
      return ref
          .watch(attendanceRepositoryProvider)
          .fetchActiveSessions(lecturerId);
    });

final rosterProvider = StreamProvider.autoDispose
    .family<List<AttendanceRecord>, String>((ref, sessionId) {
      return ref.watch(attendanceRepositoryProvider).watchRoster(sessionId);
    });

final sessionRosterProvider = FutureProvider.autoDispose
    .family<List<RosterEntry>, String>((ref, sessionId) {
      return ref
          .watch(attendanceRepositoryProvider)
          .fetchSessionRoster(sessionId);
    });

final attendanceHistoryProvider = FutureProvider.autoDispose
    .family<List<AttendanceHistoryEntry>, String>((ref, userId) {
      return ref.watch(attendanceRepositoryProvider).fetchMyHistory(userId);
    });

final myEnrolledCoursesProvider = FutureProvider.autoDispose
    .family<List<Course>, String>((ref, studentId) {
      return ref
          .watch(attendanceRepositoryProvider)
          .fetchMyEnrolledCourses(studentId);
    });

final courseAttendanceHoursProvider = FutureProvider.autoDispose
    .family<CourseAttendanceHours, ({String studentId, String courseId})>((
      ref,
      args,
    ) {
      return ref
          .watch(attendanceRepositoryProvider)
          .fetchCourseAttendanceHours(
            studentId: args.studentId,
            courseId: args.courseId,
          );
    });

final overallAttendanceHoursProvider = FutureProvider.autoDispose
    .family<CourseAttendanceHours?, String>((ref, studentId) async {
      final courses = await ref.watch(
        myEnrolledCoursesProvider(studentId).future,
      );
      if (courses.isEmpty) return null;
      final repo = ref.watch(attendanceRepositoryProvider);
      final results = await Future.wait([
        for (final course in courses)
          repo.fetchCourseAttendanceHours(
            studentId: studentId,
            courseId: course.id,
          ),
      ]);
      final attended = results.fold<double>(
        0,
        (sum, r) => sum + r.attendedHours,
      );
      final total = results.fold<double>(0, (sum, r) => sum + r.totalHours);
      return CourseAttendanceHours(attendedHours: attended, totalHours: total);
    });

final lecturerScheduleForDateProvider = FutureProvider.autoDispose
    .family<List<LecturerSlot>, DateTime>((ref, date) {
      final lecturerId = ref.watch(currentUserIdProvider);
      if (lecturerId == null) return Future.value(const <LecturerSlot>[]);
      return ref
          .watch(attendanceRepositoryProvider)
          .fetchLecturerScheduleForDate(lecturerId: lecturerId, date: date);
    });

final myTimetableWeekProvider = FutureProvider.autoDispose
    .family<List<TimetableOccurrence>, DateTime>((ref, weekStart) {
      final studentId = ref.watch(currentUserIdProvider);
      if (studentId == null) return Future.value(const <TimetableOccurrence>[]);
      return ref
          .watch(attendanceRepositoryProvider)
          .fetchMyTimetableWeek(studentId: studentId, weekStart: weekStart);
    });

final termInfoProvider = FutureProvider.autoDispose<TermInfo>((ref) {
  return ref.watch(attendanceRepositoryProvider).fetchTermInfo();
});

final myLecturerTimetableWeekProvider = FutureProvider.autoDispose
    .family<List<TimetableOccurrence>, DateTime>((ref, weekStart) {
      final lecturerId = ref.watch(currentUserIdProvider);
      if (lecturerId == null) return Future.value(const <TimetableOccurrence>[]);
      return ref
          .watch(attendanceRepositoryProvider)
          .fetchLecturerOccurrences(
            lecturerId: lecturerId,
            courseIds: const [],
            from: weekStart,
            to: weekStart.add(const Duration(days: 6)),
          );
    });

final lecturerOccurrencesForMonthProvider = FutureProvider.autoDispose
    .family<List<TimetableOccurrence>, ({String courseIdsKey, DateTime month})>(
      (ref, args) {
        final lecturerId = ref.watch(currentUserIdProvider);
        if (lecturerId == null) {
          return Future.value(const <TimetableOccurrence>[]);
        }
        final courseIds = args.courseIdsKey.isEmpty
            ? const <String>[]
            : args.courseIdsKey.split(',');
        final from = DateTime(args.month.year, args.month.month, 1);
        final to = DateTime(args.month.year, args.month.month + 1, 0);
        return ref
            .watch(attendanceRepositoryProvider)
            .fetchLecturerOccurrences(
              lecturerId: lecturerId,
              courseIds: courseIds,
              from: from,
              to: to,
            );
      },
    );

final rescheduleRequestsProvider = FutureProvider.autoDispose<
  List<RescheduleRequest>
>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(attendanceRepositoryProvider).fetchRescheduleRequests();
});

final pendingRescheduleRequestCountProvider = Provider.autoDispose<int>((
  ref,
) {
  final requests = ref.watch(rescheduleRequestsProvider).value ?? const [];
  return requests
      .where((r) => r.status == RescheduleRequestStatus.pending)
      .length;
});

final courseAttendanceSummaryProvider = FutureProvider.autoDispose<
  List<CourseAttendanceSummary>
>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(attendanceRepositoryProvider).fetchCourseAttendanceSummary();
});

final courseAttendanceTrendProvider = FutureProvider.autoDispose
    .family<List<AttendanceTrendPoint>, String>((ref, courseId) {
      ref.watch(currentUserIdProvider);
      return ref
          .watch(attendanceRepositoryProvider)
          .fetchCourseAttendanceTrend(courseId);
    });

final courseStudentAttendanceProvider = FutureProvider.autoDispose
    .family<List<CourseStudentAttendance>, String>((ref, courseId) {
      ref.watch(currentUserIdProvider);
      return ref
          .watch(attendanceRepositoryProvider)
          .fetchCourseStudentAttendance(courseId);
    });
