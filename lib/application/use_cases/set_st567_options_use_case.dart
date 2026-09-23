import 'package:test_jaguar/application/services/simulator_orchestrator.dart';
import 'package:test_jaguar/protocols/st567/st567_state.dart';

class SetSt567OptionsUseCase {
  const SetSt567OptionsUseCase(this._orchestrator);

  final SimulatorOrchestrator _orchestrator;

  Future<void> call(St567Options options) =>
      _orchestrator.setSt567Options(options);
}
