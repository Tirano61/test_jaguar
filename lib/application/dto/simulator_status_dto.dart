import 'package:test_jaguar/domain/entities/ble_peripheral_status.dart';
import 'package:test_jaguar/domain/entities/scale_measurement.dart';
import 'package:test_jaguar/domain/value_objects/simulation_phase.dart';

class SimulatorStatusDto {
  const SimulatorStatusDto({
    required this.bleStatus,
    required this.running,
    required this.phase,
    required this.measurement,
    required this.weightHoldSecondsRemaining,
    required this.lastJson,
    required this.logs,
  });

  final BlePeripheralStatus bleStatus;
  final bool running;
  final SimulationPhase phase;
  final ScaleMeasurement measurement;
  final int weightHoldSecondsRemaining;
  final String lastJson;
  final List<String> logs;

  static const SimulatorStatusDto initial = SimulatorStatusDto(
    bleStatus: BlePeripheralStatus.initial,
    running: false,
    phase: SimulationPhase.loadedWaiting,
    measurement: ScaleMeasurement.baseline,
    weightHoldSecondsRemaining: 0,
    lastJson: '{}',
    logs: <String>[],
  );

  SimulatorStatusDto copyWith({
    BlePeripheralStatus? bleStatus,
    bool? running,
    SimulationPhase? phase,
    ScaleMeasurement? measurement,
    int? weightHoldSecondsRemaining,
    String? lastJson,
    List<String>? logs,
  }) {
    return SimulatorStatusDto(
      bleStatus: bleStatus ?? this.bleStatus,
      running: running ?? this.running,
      phase: phase ?? this.phase,
      measurement: measurement ?? this.measurement,
      weightHoldSecondsRemaining:
          weightHoldSecondsRemaining ?? this.weightHoldSecondsRemaining,
      lastJson: lastJson ?? this.lastJson,
      logs: logs ?? this.logs,
    );
  }
}
