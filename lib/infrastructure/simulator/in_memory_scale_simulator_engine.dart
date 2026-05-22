import 'dart:async';

import 'package:test_jaguar/domain/entities/scale_measurement.dart';
import 'package:test_jaguar/domain/value_objects/simulation_phase.dart';
import 'package:test_jaguar/infrastructure/simulator/scale_simulator_engine.dart';

class InMemoryScaleSimulatorEngine implements ScaleSimulatorEngine {
  final StreamController<bool> _runningController =
      StreamController<bool>.broadcast();
  final StreamController<SimulationPhase> _phaseController =
      StreamController<SimulationPhase>.broadcast();
  final StreamController<ScaleMeasurement> _measurementController =
      StreamController<ScaleMeasurement>.broadcast();

  Timer? _ticker;
  bool _running = false;
  int _counter = 0;

  @override
  Stream<bool> watchRunning() async* {
    yield _running;
    yield* _runningController.stream;
  }

  @override
  Stream<SimulationPhase> watchPhase() async* {
    yield SimulationPhase.loadedWaiting;
    yield* _phaseController.stream;
  }

  @override
  Stream<ScaleMeasurement> watchMeasurements() async* {
    yield ScaleMeasurement.baseline;
    yield* _measurementController.stream;
  }

  @override
  Future<void> start() async {
    if (_running) return;
    _running = true;
    _runningController.add(true);
    _phaseController.add(SimulationPhase.loadedWaiting);

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _counter = (_counter + 1) % 80;
      final int weight = 13000 + (_counter - 40).abs();
      _measurementController.add(
        ScaleMeasurement(
          tara: 12,
          hold: 1,
          vbat: 3.9,
          peso: weight,
          estBalanza: 3,
          humedad: 60,
          sensorInduc: 0,
        ),
      );
    });
  }

  @override
  Future<void> stop() async {
    _ticker?.cancel();
    _ticker = null;
    _running = false;
    _runningController.add(false);
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _runningController.close();
    await _phaseController.close();
    await _measurementController.close();
  }
}
