import 'package:test_jaguar/application/services/simulator_orchestrator.dart';
import 'package:test_jaguar/protocols/st407_remote/st407_screen.dart';

class SetSt407ScreenUseCase {
  const SetSt407ScreenUseCase(this._orchestrator);

  final SimulatorOrchestrator _orchestrator;

  Future<void> call(St407Screen screen) => _orchestrator.setSt407Screen(screen);
}
