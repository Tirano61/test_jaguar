import 'package:test_jaguar/application/services/simulator_orchestrator.dart';

class SetTomaFuerzaRpmUseCase {
  const SetTomaFuerzaRpmUseCase(this._orchestrator);

  final SimulatorOrchestrator _orchestrator;

  Future<void> call(int value) => _orchestrator.setTomaFuerzaRpm(value);
}
