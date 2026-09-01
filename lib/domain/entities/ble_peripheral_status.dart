class BlePeripheralStatus {
  const BlePeripheralStatus({
    required this.adapterEnabled,
    required this.advertising,
    required this.connected,
    this.connectedDeviceId,
    this.lastReceivedCommand,
    this.commandSequence = 0,
  });

  final bool adapterEnabled;
  final bool advertising;
  final bool connected;
  final String? connectedDeviceId;
  final String? lastReceivedCommand;

  /// Se incrementa cada vez que llega un characteristic write real, para que
  /// los suscriptores puedan distinguir un comando nuevo de una emisión de
  /// estado no relacionada (adapter on/off, conexión de central, etc.) que
  /// repite el mismo `lastReceivedCommand` anterior.
  final int commandSequence;

  BlePeripheralStatus copyWith({
    bool? adapterEnabled,
    bool? advertising,
    bool? connected,
    String? connectedDeviceId,
    String? lastReceivedCommand,
    int? commandSequence,
  }) {
    return BlePeripheralStatus(
      adapterEnabled: adapterEnabled ?? this.adapterEnabled,
      advertising: advertising ?? this.advertising,
      connected: connected ?? this.connected,
      connectedDeviceId: connectedDeviceId ?? this.connectedDeviceId,
      lastReceivedCommand: lastReceivedCommand ?? this.lastReceivedCommand,
      commandSequence: commandSequence ?? this.commandSequence,
    );
  }

  static const BlePeripheralStatus initial = BlePeripheralStatus(
    adapterEnabled: false,
    advertising: false,
    connected: false,
  );
}
