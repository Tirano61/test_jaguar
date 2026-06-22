import 'package:test_jaguar/domain/entities/ble_peripheral_status.dart';
import 'package:test_jaguar/domain/entities/scale_measurement.dart';
import 'package:test_jaguar/domain/value_objects/send_protocol.dart';
import 'package:test_jaguar/domain/value_objects/st456_screen.dart';
import 'package:test_jaguar/domain/value_objects/simulation_phase.dart';

class SimulatorStatusDto {
  const SimulatorStatusDto({
    required this.bleStatus,
    required this.running,
    required this.sendProtocol,
    required this.st456Screen,
    required this.phase,
    required this.measurement,
    required this.manualMeasurement,
    required this.weightHoldSecondsRemaining,
    required this.lastJson,
    required this.logs,
  });

  final BlePeripheralStatus bleStatus;
  final bool running;
  final SendProtocol sendProtocol;
  final St456Screen st456Screen;
  final SimulationPhase phase;
  final ScaleMeasurement measurement;
  final ScaleMeasurement manualMeasurement;
  final int weightHoldSecondsRemaining;
  final String lastJson;
  final List<String> logs;

  static const SimulatorStatusDto initial = SimulatorStatusDto(
    bleStatus: BlePeripheralStatus.initial,
    running: false,
    sendProtocol: SendProtocol.jaguarBle,
    st456Screen: St456Screen.main,
    phase: SimulationPhase.loadedWaiting,
    measurement: ScaleMeasurement.baseline,
    manualMeasurement: ScaleMeasurement.baseline,
    weightHoldSecondsRemaining: 0,
    lastJson: '{}',
    logs: <String>[],
  );

  SimulatorStatusDto copyWith({
    BlePeripheralStatus? bleStatus,
    bool? running,
    SendProtocol? sendProtocol,
    St456Screen? st456Screen,
    SimulationPhase? phase,
    ScaleMeasurement? measurement,
    ScaleMeasurement? manualMeasurement,
    int? weightHoldSecondsRemaining,
    String? lastJson,
    List<String>? logs,
  }) {
    return SimulatorStatusDto(
      bleStatus: bleStatus ?? this.bleStatus,
      running: running ?? this.running,
      sendProtocol: sendProtocol ?? this.sendProtocol,
      st456Screen: st456Screen ?? this.st456Screen,
      phase: phase ?? this.phase,
      measurement: measurement ?? this.measurement,
      manualMeasurement: manualMeasurement ?? this.manualMeasurement,
      weightHoldSecondsRemaining:
          weightHoldSecondsRemaining ?? this.weightHoldSecondsRemaining,
      lastJson: lastJson ?? this.lastJson,
      logs: logs ?? this.logs,
    );
  }
}
