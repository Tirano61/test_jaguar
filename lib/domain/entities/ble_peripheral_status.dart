class BlePeripheralStatus {
  const BlePeripheralStatus({
    required this.adapterEnabled,
    required this.advertising,
    required this.connected,
    this.connectedDeviceId,
  });

  final bool adapterEnabled;
  final bool advertising;
  final bool connected;
  final String? connectedDeviceId;

  BlePeripheralStatus copyWith({
    bool? adapterEnabled,
    bool? advertising,
    bool? connected,
    String? connectedDeviceId,
  }) {
    return BlePeripheralStatus(
      adapterEnabled: adapterEnabled ?? this.adapterEnabled,
      advertising: advertising ?? this.advertising,
      connected: connected ?? this.connected,
      connectedDeviceId: connectedDeviceId ?? this.connectedDeviceId,
    );
  }

  static const BlePeripheralStatus initial = BlePeripheralStatus(
    adapterEnabled: false,
    advertising: false,
    connected: false,
  );
}
