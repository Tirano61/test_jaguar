import 'package:test_jaguar/application/services/simulator_orchestrator.dart';

class SetErrorEcuUseCase {
  const SetErrorEcuUseCase(this._orchestrator);

  final SimulatorOrchestrator _orchestrator;

  Future<void> call(String value) => _orchestrator.setErrorEcu(value);
}
