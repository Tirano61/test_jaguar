import 'package:test_jaguar/domain/value_objects/simulation_phase.dart';

class SimulationState {
  const SimulationState({
    required this.phase,
    required this.tickInPhase,
    required this.cycle,
    required this.currentWeight,
    required this.phaseStartWeight,
    required this.phaseTargetWeight,
  });

  final SimulationPhase phase;
  final int tickInPhase;
  final int cycle;
  final int currentWeight;
  final int phaseStartWeight;
  final int phaseTargetWeight;

  SimulationState copyWith({
    SimulationPhase? phase,
    int? tickInPhase,
    int? cycle,
    int? currentWeight,
    int? phaseStartWeight,
    int? phaseTargetWeight,
  }) {
    return SimulationState(
      phase: phase ?? this.phase,
      tickInPhase: tickInPhase ?? this.tickInPhase,
      cycle: cycle ?? this.cycle,
      currentWeight: currentWeight ?? this.currentWeight,
      phaseStartWeight: phaseStartWeight ?? this.phaseStartWeight,
      phaseTargetWeight: phaseTargetWeight ?? this.phaseTargetWeight,
    );
  }
}
