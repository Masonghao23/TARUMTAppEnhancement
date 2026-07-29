import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/device_identity_service.dart';
import 'device_binding_exceptions.dart';
import 'models.dart';

class ProfileRepository {
  ProfileRepository(this._client);

  final SupabaseClient _client;

  Future<Profile> fetchProfile(String userId) async {
    final row = await _client
        .from('profiles')
        .select()
        .eq('id', userId)
        .single();
    return Profile.fromMap(row);
  }

  /// FR04: staff can search/filter user accounts by name or campus ID.
  Future<List<Profile>> searchProfiles(String keyword) async {
    if (keyword.trim().isEmpty) {
      final rows = await _client
          .from('profiles')
          .select()
          .order('name')
          .limit(50);
      return rows.map(Profile.fromMap).toList();
    }

    final rows = await _client
        .from('profiles')
        .select()
        .or('name.ilike.%$keyword%,campus_id.ilike.%$keyword%')
        .order('name')
        .limit(50);
    return rows.map(Profile.fromMap).toList();
  }

  Future<UserDevice?> fetchActiveDevice(String userId) async {
    final rows = await _client
        .from('user_devices')
        .select()
        .eq('user_id', userId)
        .eq('status', 'active')
        .order('bind_date', ascending: false)
        .limit(1);
    if (rows.isEmpty) return null;
    return UserDevice.fromMap(rows.first);
  }

  /// FR09/FR10 + Table 4.2 use case: bind a device to the account, blocking
  /// a rebind within 7 days and rejecting a device already bound elsewhere
  /// unless [force] is set (the "Change ID Binding to Current Device" alt
  /// flow A1).
  Future<void> bindDevice({
    required String userId,
    required DeviceIdentity identity,
    bool force = false,
  }) async {
    final currentDevice = await fetchActiveDevice(userId);
    if (currentDevice != null) {
      final remaining = currentDevice.cooldownRemaining;
      if (remaining > Duration.zero) {
        throw DeviceBindCooldownException(remaining);
      }
    }

    if (force) {
      await _client.rpc(
        'release_device_from_other_users',
        params: {
          'p_device_identifier': identity.identifier,
          'p_new_user_id': userId,
        },
      );
    } else {
      final boundElsewhere = await _client.rpc(
        'is_device_bound_to_other_user',
        params: {
          'p_device_identifier': identity.identifier,
          'p_user_id': userId,
        },
      );
      if (boundElsewhere == true) {
        throw const DeviceAlreadyBoundException();
      }
    }

    if (currentDevice != null) {
      await _client
          .from('user_devices')
          .update({'status': 'replaced'})
          .eq('device_id', currentDevice.deviceId);
    }

    await _client.from('user_devices').insert({
      'user_id': userId,
      'device_identifier': identity.identifier,
      'device_model': identity.model,
      'status': 'active',
    });
  }
}
