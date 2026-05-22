import 'package:test_jaguar/domain/entities/scale_measurement.dart';
import 'package:test_jaguar/domain/repositories/scale_simulation_repository.dart';
import 'package:test_jaguar/domain/value_objects/simulation_phase.dart';
import 'package:test_jaguar/infrastructure/simulator/scale_simulator_engine.dart';

class ScaleSimulationRepositoryImpl implements ScaleSimulationRepository {
  ScaleSimulationRepositoryImpl(this._engine);

  final ScaleSimulatorEngine _engine;

  @override
  Stream<bool> watchRunning() => _engine.watchRunning();

  @override
  Stream<SimulationPhase> watchPhase() => _engine.watchPhase();

  @override
  Stream<ScaleMeasurement> watchMeasurements() => _engine.watchMeasurements();

  @override
  Future<void> start() => _engine.start();

  @override
  Future<void> stop() => _engine.stop();

  @override
  Future<void> dispose() => _engine.dispose();
}
