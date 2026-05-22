import 'package:test_jaguar/domain/entities/scale_measurement.dart';
import 'package:test_jaguar/domain/value_objects/simulation_phase.dart';

abstract interface class ScaleSimulationRepository {
  Stream<bool> watchRunning();

  Stream<SimulationPhase> watchPhase();

  Stream<ScaleMeasurement> watchMeasurements();

  Future<void> start();

  Future<void> stop();

  Future<void> dispose();
}
