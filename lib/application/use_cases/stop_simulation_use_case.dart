import 'package:test_jaguar/application/services/simulator_orchestrator.dart';

class StopSimulationUseCase {
  const StopSimulationUseCase(this._orchestrator);

  final SimulatorOrchestrator _orchestrator;

  Future<void> call() => _orchestrator.stop();
}
