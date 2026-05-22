import 'package:test_jaguar/application/services/simulator_orchestrator.dart';

class StartSimulationUseCase {
  const StartSimulationUseCase(this._orchestrator);

  final SimulatorOrchestrator _orchestrator;

  Future<void> call() => _orchestrator.start();
}
