import 'dart:convert';

import 'package:crypto/crypto.dart';

/// HMAC(seed, time_window) — must stay in lockstep with the Postgres
/// `submit_attendance` function, which recomputes the same value to verify
/// a scanned token. Computed purely locally so the lecturer's QR can
/// refresh every [intervalSeconds] with no network round trip.
String computeQrToken({
  required String seed,
  required int windowIndex,
}) {
  final hmac = Hmac(sha256, utf8.encode(seed));
  return hmac.convert(utf8.encode(windowIndex.toString())).toString();
}

int currentWindowIndex(int intervalSeconds) {
  final epochSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
  return epochSeconds ~/ intervalSeconds;
}
