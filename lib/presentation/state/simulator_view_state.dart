import 'package:test_jaguar/domain/entities/scale_measurement.dart';
import 'package:test_jaguar/domain/value_objects/send_protocol.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_state.dart';
import 'package:test_jaguar/protocols/st407_remote/st407_screen.dart';

/// Lo que la UI necesita para dibujarse.
///
/// Reusa las clases de estado de cada protocolo en vez de volver a aplanarlas:
/// son inmutables y no dependen de Flutter, así que el controller sólo las pasa
/// de largo. Lo único propio de la UI son los topes de los sliders del modo
/// Manual, que no viajan por BLE ni los conoce el protocolo.
class SimulatorViewState {
  const SimulatorViewState({
    required this.bleEnabled,
    required this.advertising,
    required this.connected,
    required this.connectedDeviceId,
    required this.lastReceivedCommand,
    required this.running,
    required this.sendProtocol,
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
    required this.st407Screen,
    required this.manual,
    required this.manualTaraMax,
    required this.manualWeightMax,
    required this.hidraulico,
  });

  // --- Comunes ---

  final bool bleEnabled;
  final bool advertising;
  final bool connected;
  final String? connectedDeviceId;
  final String? lastReceivedCommand;
  final bool running;
  final SendProtocol sendProtocol;
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

  // --- Por protocolo ---

  final St407Screen st407Screen;

  /// Valores del modo Manual.
  final ScaleMeasurement manual;

  /// Topes de los sliders del modo Manual. Son sólo de la UI.
  final int manualTaraMax;
  final int manualWeightMax;

  final HydraulicState hidraulico;

  static const SimulatorViewState initial = SimulatorViewState(
    bleEnabled: false,
    advertising: false,
    connected: false,
    connectedDeviceId: null,
    lastReceivedCommand: null,
    running: false,
    sendProtocol: SendProtocol.jaguarBle,
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
    st407Screen: St407Screen.main,
    manual: ScaleMeasurement.baseline,
    manualTaraMax: 22000,
    manualWeightMax: 22000,
    hidraulico: HydraulicState.initial,
  );

  SimulatorViewState copyWith({
    bool? bleEnabled,
    bool? advertising,
    bool? connected,
    String? connectedDeviceId,
    String? lastReceivedCommand,
    bool? running,
    SendProtocol? sendProtocol,
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
    St407Screen? st407Screen,
    ScaleMeasurement? manual,
    int? manualTaraMax,
    int? manualWeightMax,
    HydraulicState? hidraulico,
  }) {
    return SimulatorViewState(
      bleEnabled: bleEnabled ?? this.bleEnabled,
      advertising: advertising ?? this.advertising,
      connected: connected ?? this.connected,
      connectedDeviceId: connectedDeviceId ?? this.connectedDeviceId,
      lastReceivedCommand: lastReceivedCommand ?? this.lastReceivedCommand,
      running: running ?? this.running,
      sendProtocol: sendProtocol ?? this.sendProtocol,
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
      st407Screen: st407Screen ?? this.st407Screen,
      manual: manual ?? this.manual,
      manualTaraMax: manualTaraMax ?? this.manualTaraMax,
      manualWeightMax: manualWeightMax ?? this.manualWeightMax,
      hidraulico: hidraulico ?? this.hidraulico,
    );
  }
}
