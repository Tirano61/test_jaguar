import 'package:test_jaguar/application/services/simulator_orchestrator.dart';

class SetHydraulicPesoUseCase {
  const SetHydraulicPesoUseCase(this._orchestrator);

  final SimulatorOrchestrator _orchestrator;

  Future<void> call(int value) => _orchestrator.setHydraulicPeso(value);
}
