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

  SimulationState advance({
    required SimulationState current,
    required int nextWeight,
  }) {
    final int nextTick = current.tickInPhase + 1;
    if (nextTick < timing.ticksPerPhase()) {
      return current.copyWith(
        tickInPhase: nextTick,
        currentWeight: nextWeight,
      );
    }

    final SimulationPhase nextPhase = phaseAfter(current.phase);
    final int nextCycle =
        nextPhase == SimulationPhase.loadedWaiting ? current.cycle + 1 : current.cycle;

    return current.copyWith(
      phase: nextPhase,
      tickInPhase: 0,
      cycle: nextCycle,
      currentWeight: nextWeight,
      phaseStartWeight: nextWeight,
      phaseTargetWeight: targetWeightForPhase(nextPhase, nextWeight),
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

  int targetWeightForPhase(SimulationPhase phase, int currentWeight) {
    switch (phase) {
      case SimulationPhase.loadedWaiting:
        return loadedRange.clamp(currentWeight);
      case SimulationPhase.unloading:
        return emptyRange.midpoint();
      case SimulationPhase.emptyWaiting:
        return emptyRange.clamp(currentWeight);
      case SimulationPhase.loading:
        return loadedRange.midpoint();
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
