import 'package:test_jaguar/application/services/simulator_orchestrator.dart';

class SetTomaFuerzaUseCase {
  const SetTomaFuerzaUseCase(this._orchestrator);

  final SimulatorOrchestrator _orchestrator;

  Future<void> call(int value) => _orchestrator.setTomaFuerza(value);
}
