import 'package:test_jaguar/application/services/simulator_orchestrator.dart';
import 'package:test_jaguar/protocols/st567/st567_screen.dart';

class SetSt567ScreenUseCase {
  const SetSt567ScreenUseCase(this._orchestrator);

  final SimulatorOrchestrator _orchestrator;

  Future<void> call(St567Screen screen) => _orchestrator.setSt567Screen(screen);
}
