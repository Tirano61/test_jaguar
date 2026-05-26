class SimulatorViewState {
  const SimulatorViewState({
    required this.bleEnabled,
    required this.advertising,
    required this.connected,
    required this.connectedDeviceId,
    required this.lastReceivedCommand,
    required this.running,
    required this.phaseName,
    required this.weight,
    required this.sensorInduc,
    required this.estBalanza,
    required this.weightHoldSecondsRemaining,
    required this.humidity,
    required this.serviceUuid,
    required this.characteristicUuid,
    required this.serviceWriteUuid,
    required this.characteristicWriteUuid,
    required this.lastJson,
    required this.logs,
  });

  final bool bleEnabled;
  final bool advertising;
  final bool connected;
  final String? connectedDeviceId;
  final String? lastReceivedCommand;
  final bool running;
  final String phaseName;
  final int weight;
  final int sensorInduc;
  final int estBalanza;
  final int weightHoldSecondsRemaining;
  final double humidity;
  final String serviceUuid;
  final String characteristicUuid;
  final String serviceWriteUuid;
  final String characteristicWriteUuid;
  final String lastJson;
  final List<String> logs;

  static const SimulatorViewState initial = SimulatorViewState(
    bleEnabled: false,
    advertising: false,
    connected: false,
    connectedDeviceId: null,
    lastReceivedCommand: null,
    running: false,
    phaseName: 'loadedWaiting',
    weight: 0,
    sensorInduc: 0,
    estBalanza: 1,
    weightHoldSecondsRemaining: 0,
    humidity: 10.0,
    serviceUuid: '',
    characteristicUuid: '',
    serviceWriteUuid: '',
    characteristicWriteUuid: '',
    lastJson: '{}',
    logs: <String>[],
  );

  SimulatorViewState copyWith({
    bool? bleEnabled,
    bool? advertising,
    bool? connected,
    String? connectedDeviceId,
    String? lastReceivedCommand,
    bool? running,
    String? phaseName,
    int? weight,
    int? sensorInduc,
    int? estBalanza,
    int? weightHoldSecondsRemaining,
    double? humidity,
    String? serviceUuid,
    String? characteristicUuid,
    String? serviceWriteUuid,
    String? characteristicWriteUuid,
    String? lastJson,
    List<String>? logs,
  }) {
    return SimulatorViewState(
      bleEnabled: bleEnabled ?? this.bleEnabled,
      advertising: advertising ?? this.advertising,
      connected: connected ?? this.connected,
      connectedDeviceId: connectedDeviceId ?? this.connectedDeviceId,
      lastReceivedCommand: lastReceivedCommand ?? this.lastReceivedCommand,
      running: running ?? this.running,
      phaseName: phaseName ?? this.phaseName,
      weight: weight ?? this.weight,
      sensorInduc: sensorInduc ?? this.sensorInduc,
      estBalanza: estBalanza ?? this.estBalanza,
      weightHoldSecondsRemaining:
          weightHoldSecondsRemaining ?? this.weightHoldSecondsRemaining,
      humidity: humidity ?? this.humidity,
      serviceUuid: serviceUuid ?? this.serviceUuid,
      characteristicUuid: characteristicUuid ?? this.characteristicUuid,
      serviceWriteUuid: serviceWriteUuid ?? this.serviceWriteUuid,
      characteristicWriteUuid:
          characteristicWriteUuid ?? this.characteristicWriteUuid,
      lastJson: lastJson ?? this.lastJson,
      logs: logs ?? this.logs,
    );
  }
}
