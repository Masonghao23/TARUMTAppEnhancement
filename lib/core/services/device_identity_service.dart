import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceIdentity {
  const DeviceIdentity({required this.identifier, required this.model});

  final String identifier;
  final String model;
}

class DeviceIdentityService {
  static const _fallbackIdKey = 'device_identity_fallback_id';

  /// Returns the current device’s identifier and platform details.
  Future<DeviceIdentity> getDeviceIdentity() async {
    final plugin = DeviceInfoPlugin();

    if (!kIsWeb && Platform.isAndroid) {
      final info = await plugin.androidInfo;
      return DeviceIdentity(
        identifier: info.id,
        model: '${info.manufacturer} ${info.model}',
      );
    }

    if (!kIsWeb && Platform.isIOS) {
      final info = await plugin.iosInfo;
      return DeviceIdentity(
        identifier: info.identifierForVendor ?? await _fallbackId(),
        model: info.utsname.machine,
      );
    }

    final identifier = await _fallbackId();
    return DeviceIdentity(identifier: identifier, model: 'This device');
  }

  /// Returns a persistent fallback identifier for the device.
  Future<String> _fallbackId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_fallbackIdKey);
    if (existing != null) return existing;

    final generated = const Uuid().v4();
    await prefs.setString(_fallbackIdKey, generated);
    return generated;
  }
}
