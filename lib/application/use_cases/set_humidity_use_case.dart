import 'package:test_jaguar/application/services/simulator_orchestrator.dart';

class SetHumidityUseCase {
  const SetHumidityUseCase(this._orchestrator);

  final SimulatorOrchestrator _orchestrator;

  Future<void> call(double value) => _orchestrator.setHumidity(value);
}
