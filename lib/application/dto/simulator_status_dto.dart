import 'package:test_jaguar/core/constants/ble_constants.dart';
import 'package:test_jaguar/domain/entities/ble_peripheral_status.dart';
import 'package:test_jaguar/domain/entities/scale_measurement.dart';
import 'package:test_jaguar/domain/value_objects/send_protocol.dart';
import 'package:test_jaguar/domain/value_objects/simulation_phase.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_state.dart';
import 'package:test_jaguar/protocols/st407_remote/st407_screen.dart';

/// Foto del simulador que el orquestador publica en cada emisión.
///
/// Los campos de arriba son comunes a todos los protocolos; abajo va un campo
/// por protocolo que tenga estado propio. Sumar un protocolo nuevo agrega un
/// campo, no veinte.
class SimulatorStatusDto {
  const SimulatorStatusDto({
    required this.bleStatus,
    required this.running,
    required this.sendProtocol,
    required this.bleUuids,
    required this.phase,
    required this.measurement,
    required this.weightHoldSecondsRemaining,
    required this.lastJson,
    required this.logs,
    required this.st407Screen,
    required this.manualMeasurement,
    required this.hidraulico,
  });

  // --- Comunes ---

  final BlePeripheralStatus bleStatus;
  final bool running;
  final SendProtocol sendProtocol;

  /// Perfil GATT que el protocolo activo pide anunciar. Lo decide el
  /// protocolo, así que la UI lo muestra en vez de volver a deducirlo.
  final BleUuids bleUuids;
  final SimulationPhase phase;

  /// Última medición emitida, sea cual sea el protocolo que la produjo.
  final ScaleMeasurement measurement;
  final int weightHoldSecondsRemaining;
  final String lastJson;
  final List<String> logs;

  // --- Por protocolo ---

  /// Remoto ST407: su estado visible es la pantalla seleccionada. Los
  /// contadores de carga y de mezclado son internos del módulo.
  final St407Screen st407Screen;

  /// Manual: los valores que el tester dejó en los sliders.
  final ScaleMeasurement manualMeasurement;

  /// Hidráulico BLE: configuración de la caja y estado de la descarga.
  final HydraulicState hidraulico;

  static const SimulatorStatusDto initial = SimulatorStatusDto(
    bleStatus: BlePeripheralStatus.initial,
    running: false,
    sendProtocol: SendProtocol.jaguarBle,
    bleUuids: BleConstants.jaguar,
    phase: SimulationPhase.loadedWaiting,
    measurement: ScaleMeasurement.baseline,
    weightHoldSecondsRemaining: 0,
    lastJson: '{}',
    logs: <String>[],
    st407Screen: St407Screen.main,
    manualMeasurement: ScaleMeasurement.baseline,
    hidraulico: HydraulicState.initial,
  );

  SimulatorStatusDto copyWith({
    BlePeripheralStatus? bleStatus,
    bool? running,
    SendProtocol? sendProtocol,
    BleUuids? bleUuids,
    SimulationPhase? phase,
    ScaleMeasurement? measurement,
    int? weightHoldSecondsRemaining,
    String? lastJson,
    List<String>? logs,
    St407Screen? st407Screen,
    ScaleMeasurement? manualMeasurement,
    HydraulicState? hidraulico,
  }) {
    return SimulatorStatusDto(
      bleStatus: bleStatus ?? this.bleStatus,
      running: running ?? this.running,
      sendProtocol: sendProtocol ?? this.sendProtocol,
      bleUuids: bleUuids ?? this.bleUuids,
      phase: phase ?? this.phase,
      measurement: measurement ?? this.measurement,
      weightHoldSecondsRemaining:
          weightHoldSecondsRemaining ?? this.weightHoldSecondsRemaining,
      lastJson: lastJson ?? this.lastJson,
      logs: logs ?? this.logs,
      st407Screen: st407Screen ?? this.st407Screen,
      manualMeasurement: manualMeasurement ?? this.manualMeasurement,
      hidraulico: hidraulico ?? this.hidraulico,
    );
  }
}
