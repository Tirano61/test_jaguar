import 'package:test_jaguar/domain/value_objects/send_protocol.dart';
import 'package:test_jaguar/domain/value_objects/st456_screen.dart';

class SimulatorViewState {
  const SimulatorViewState({
    required this.bleEnabled,
    required this.advertising,
    required this.connected,
    required this.connectedDeviceId,
    required this.lastReceivedCommand,
    required this.running,
    required this.sendProtocol,
    required this.st456Screen,
    required this.phaseName,
    required this.weight,
    required this.sensorInduc,
    required this.estBalanza,
    required this.weightHoldSecondsRemaining,
    required this.humidity,
    required this.manualTara,
    required this.manualTaraMax,
    required this.manualHold,
    required this.manualVbat,
    required this.manualWeight,
    required this.manualWeightMax,
    required this.manualEstBalanza,
    required this.manualHumidity,
    required this.manualSensorInduc,
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
  final SendProtocol sendProtocol;
  final St456Screen st456Screen;
  final String phaseName;
  final int weight;
  final int sensorInduc;
  final int estBalanza;
  final int weightHoldSecondsRemaining;
  final double humidity;
  final int manualTara;
  final int manualTaraMax;
  final int manualHold;
  final double manualVbat;
  final int manualWeight;
  final int manualWeightMax;
  final int manualEstBalanza;
  final double manualHumidity;
  final int manualSensorInduc;
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
    sendProtocol: SendProtocol.jaguarBle,
    st456Screen: St456Screen.main,
    phaseName: 'loadedWaiting',
    weight: 0,
    sensorInduc: 0,
    estBalanza: 1,
    weightHoldSecondsRemaining: 0,
    humidity: 10.0,
    manualTara: 0,
    manualTaraMax: 22000,
    manualHold: 1,
    manualVbat: 3.9,
    manualWeight: 0,
    manualWeightMax: 22000,
    manualEstBalanza: 1,
    manualHumidity: 10.0,
    manualSensorInduc: 0,
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
    SendProtocol? sendProtocol,
    St456Screen? st456Screen,
    String? phaseName,
    int? weight,
    int? sensorInduc,
    int? estBalanza,
    int? weightHoldSecondsRemaining,
    double? humidity,
    int? manualTara,
    int? manualTaraMax,
    int? manualHold,
    double? manualVbat,
    int? manualWeight,
    int? manualWeightMax,
    int? manualEstBalanza,
    double? manualHumidity,
    int? manualSensorInduc,
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
      sendProtocol: sendProtocol ?? this.sendProtocol,
      st456Screen: st456Screen ?? this.st456Screen,
      phaseName: phaseName ?? this.phaseName,
      weight: weight ?? this.weight,
      sensorInduc: sensorInduc ?? this.sensorInduc,
      estBalanza: estBalanza ?? this.estBalanza,
      weightHoldSecondsRemaining:
          weightHoldSecondsRemaining ?? this.weightHoldSecondsRemaining,
      humidity: humidity ?? this.humidity,
      manualTara: manualTara ?? this.manualTara,
      manualTaraMax: manualTaraMax ?? this.manualTaraMax,
      manualHold: manualHold ?? this.manualHold,
      manualVbat: manualVbat ?? this.manualVbat,
      manualWeight: manualWeight ?? this.manualWeight,
      manualWeightMax: manualWeightMax ?? this.manualWeightMax,
      manualEstBalanza: manualEstBalanza ?? this.manualEstBalanza,
      manualHumidity: manualHumidity ?? this.manualHumidity,
      manualSensorInduc: manualSensorInduc ?? this.manualSensorInduc,
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
