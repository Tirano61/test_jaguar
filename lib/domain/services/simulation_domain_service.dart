import 'package:test_jaguar/domain/entities/scale_measurement.dart';
import 'package:test_jaguar/domain/entities/simulation_state.dart';
import 'package:test_jaguar/domain/value_objects/simulation_phase.dart';
import 'package:test_jaguar/domain/value_objects/simulation_timing.dart';
import 'package:test_jaguar/domain/value_objects/weight_range.dart';

class SimulationDomainService {
  const SimulationDomainService({
    this.timing = SimulationTiming.oneMinutePerPhase,
  });

  final SimulationTiming timing;

  static const WeightRange loadedRange = WeightRange(min: 12500, max: 14600);
  static const WeightRange emptyRange = WeightRange(min: 1500, max: 3500);

  SimulationState initialState({int? initialLoadedWeight}) {
    final int startWeight =
        loadedRange.clamp(initialLoadedWeight ?? loadedRange.midpoint());

    return SimulationState(
      phase: SimulationPhase.loadedWaiting,
      tickInPhase: 0,
      cycle: 1,
      currentWeight: startWeight,
      phaseStartWeight: startWeight,
      phaseTargetWeight: startWeight,
    );
  }

  SimulationPhase phaseAfter(SimulationPhase phase) {
    switch (phase) {
      case SimulationPhase.loadedWaiting:
        return SimulationPhase.unloading;
      case SimulationPhase.unloading:
        return SimulationPhase.emptyWaiting;
      case SimulationPhase.emptyWaiting:
        return SimulationPhase.loading;
      case SimulationPhase.loading:
        return SimulationPhase.loadedWaiting;
    }
  }

  int sensorInducForPhase(SimulationPhase phase) {
    if (phase == SimulationPhase.unloading) {
      return 1;
    }
    return 0;
  }

  ScaleMeasurement measurementFrom({
    required int weight,
    required SimulationPhase phase,
  }) {
    return ScaleMeasurement(
      tara: 0,
      hold: 1,
      vbat: 3.9,
      peso: weight,
      estBalanza: 3,
      humedad: 10.0,
      sensorInduc: sensorInducForPhase(phase),
    );
  }
}
