import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/device_identity_service.dart';
import '../auth/providers.dart';
import 'data/admin_repository.dart';
import 'data/models.dart';
import 'data/profile_repository.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.watch(supabaseClientProvider));
});

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return AdminRepository(ref.watch(supabaseClientProvider));
});

final deviceIdentityServiceProvider = Provider<DeviceIdentityService>((ref) {
  return DeviceIdentityService();
});

final currentUserIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authStateChangesProvider).value;
  return authState?.session?.user.id ??
      ref.watch(supabaseClientProvider).auth.currentUser?.id;
});

final currentProfileProvider = FutureProvider<Profile?>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;
  return ref.watch(profileRepositoryProvider).fetchProfile(userId);
});

final currentDeviceProvider = FutureProvider<UserDevice?>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;
  return ref.watch(profileRepositoryProvider).fetchActiveDevice(userId);
});

final userSearchProvider = FutureProvider.family<List<Profile>, String>((
  ref,
  keyword,
) {
  return ref.watch(profileRepositoryProvider).searchProfiles(keyword);
});
