import 'package:test_jaguar/application/services/simulator_orchestrator.dart';
import 'package:test_jaguar/domain/value_objects/st456_screen.dart';

class SetSt456ScreenUseCase {
  const SetSt456ScreenUseCase(this._orchestrator);

  final SimulatorOrchestrator _orchestrator;

  Future<void> call(St456Screen screen) => _orchestrator.setSt456Screen(screen);
}
