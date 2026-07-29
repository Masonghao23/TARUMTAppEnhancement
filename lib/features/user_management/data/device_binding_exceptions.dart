class DeviceAlreadyBoundException implements Exception {
  const DeviceAlreadyBoundException();
}

class DeviceBindCooldownException implements Exception {
  const DeviceBindCooldownException(this.remaining);

  final Duration remaining;
}
