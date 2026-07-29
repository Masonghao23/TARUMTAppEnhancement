import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/location_service.dart';
import '../auth/providers.dart';
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
      return ref.watch(attendanceRepositoryProvider).fetchMySessions(lecturerId);
    });

final rosterProvider = StreamProvider.autoDispose
    .family<List<AttendanceRecord>, String>((ref, sessionId) {
      return ref.watch(attendanceRepositoryProvider).watchRoster(sessionId);
    });

final attendanceHistoryProvider = FutureProvider.autoDispose
    .family<List<AttendanceHistoryEntry>, String>((ref, userId) {
      return ref.watch(attendanceRepositoryProvider).fetchMyHistory(userId);
    });
