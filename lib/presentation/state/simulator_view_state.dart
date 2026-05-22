class SimulatorViewState {
  const SimulatorViewState({
    required this.bleEnabled,
    required this.advertising,
    required this.connected,
    required this.running,
    required this.phaseName,
    required this.weight,
    required this.sensorInduc,
    required this.serviceUuid,
    required this.characteristicUuid,
    required this.lastJson,
    required this.logs,
  });

  final bool bleEnabled;
  final bool advertising;
  final bool connected;
  final bool running;
  final String phaseName;
  final int weight;
  final int sensorInduc;
  final String serviceUuid;
  final String characteristicUuid;
  final String lastJson;
  final List<String> logs;

  static const SimulatorViewState initial = SimulatorViewState(
    bleEnabled: false,
    advertising: false,
    connected: false,
    running: false,
    phaseName: 'loadedWaiting',
    weight: 0,
    sensorInduc: 0,
    serviceUuid: '',
    characteristicUuid: '',
    lastJson: '{}',
    logs: <String>[],
  );

  SimulatorViewState copyWith({
    bool? bleEnabled,
    bool? advertising,
    bool? connected,
    bool? running,
    String? phaseName,
    int? weight,
    int? sensorInduc,
    String? serviceUuid,
    String? characteristicUuid,
    String? lastJson,
    List<String>? logs,
  }) {
    return SimulatorViewState(
      bleEnabled: bleEnabled ?? this.bleEnabled,
      advertising: advertising ?? this.advertising,
      connected: connected ?? this.connected,
      running: running ?? this.running,
      phaseName: phaseName ?? this.phaseName,
      weight: weight ?? this.weight,
      sensorInduc: sensorInduc ?? this.sensorInduc,
      serviceUuid: serviceUuid ?? this.serviceUuid,
      characteristicUuid: characteristicUuid ?? this.characteristicUuid,
      lastJson: lastJson ?? this.lastJson,
      logs: logs ?? this.logs,
    );
  }
}
