import 'package:test_jaguar/application/services/simulator_orchestrator.dart';

class SendGuardarEventUseCase {
  const SendGuardarEventUseCase(this._orchestrator);

  final SimulatorOrchestrator _orchestrator;

  Future<void> call() => _orchestrator.sendGuardarEvent();
}
