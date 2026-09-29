import 'package:test_jaguar/application/services/simulator_orchestrator.dart';
import 'package:test_jaguar/protocols/st456web/st456web_screen.dart';

class SetSt456webScreenUseCase {
  const SetSt456webScreenUseCase(this._orchestrator);

  final SimulatorOrchestrator _orchestrator;

  Future<void> call(St456webScreen screen) =>
      _orchestrator.setSt456webScreen(screen);
}
