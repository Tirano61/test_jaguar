import 'package:test_jaguar/application/services/simulator_orchestrator.dart';
import 'package:test_jaguar/protocols/st456web/st456web_state.dart';

class SetSt456webOptionsUseCase {
  const SetSt456webOptionsUseCase(this._orchestrator);

  final SimulatorOrchestrator _orchestrator;

  Future<void> call(St456webOptions options) =>
      _orchestrator.setSt456webOptions(options);
}
