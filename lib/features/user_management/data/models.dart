enum UserRole { student, staff, admin }

UserRole userRoleFromString(String value) {
  return UserRole.values.firstWhere(
    (role) => role.name == value,
    orElse: () => UserRole.student,
  );
}

class Profile {
  const Profile({
    required this.id,
    required this.campusId,
    required this.name,
    required this.email,
    required this.role,
    this.rfidUid,
  });

  factory Profile.fromMap(Map<String, dynamic> map) {
    return Profile(
      id: map['id'] as String,
      campusId: map['campus_id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      email: map['email'] as String? ?? '',
      role: userRoleFromString(map['role'] as String? ?? 'student'),
      rfidUid: map['rfid_uid'] as String?,
    );
  }

  final String id;
  final String campusId;
  final String name;
  final String email;
  final UserRole role;
  final String? rfidUid;
}

enum DeviceStatus { active, replaced }

class UserDevice {
  const UserDevice({
    required this.deviceId,
    required this.userId,
    required this.deviceIdentifier,
    required this.deviceModel,
    required this.status,
    required this.bindDate,
  });

  factory UserDevice.fromMap(Map<String, dynamic> map) {
    return UserDevice(
      deviceId: map['device_id'] as String,
      userId: map['user_id'] as String,
      deviceIdentifier: map['device_identifier'] as String,
      deviceModel: map['device_model'] as String? ?? 'Unknown device',
      status: (map['status'] as String? ?? 'active') == 'active'
          ? DeviceStatus.active
          : DeviceStatus.replaced,
      bindDate: DateTime.parse(map['bind_date'] as String),
    );
  }

  final String deviceId;
  final String userId;
  final String deviceIdentifier;
  final String deviceModel;
  final DeviceStatus status;
  final DateTime bindDate;

  Duration get cooldownRemaining {
    final unlockAt = bindDate.add(const Duration(days: 7));
    final remaining = unlockAt.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }
}
