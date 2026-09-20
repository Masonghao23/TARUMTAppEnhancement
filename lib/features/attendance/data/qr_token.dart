import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Generates an HMAC attendance token for a session seed and time window.
String computeQrToken({required String seed, required int windowIndex}) {
  final hmac = Hmac(sha256, utf8.encode(seed));
  return hmac.convert(utf8.encode(windowIndex.toString())).toString();
}

/// Calculates the current QR token time window.
int currentWindowIndex(int intervalSeconds) {
  final epochSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
  return epochSeconds ~/ intervalSeconds;
}
