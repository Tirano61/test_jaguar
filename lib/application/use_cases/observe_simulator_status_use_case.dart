import 'package:test_jaguar/application/dto/simulator_status_dto.dart';
import 'package:test_jaguar/application/services/simulator_orchestrator.dart';

class ObserveSimulatorStatusUseCase {
  const ObserveSimulatorStatusUseCase(this._orchestrator);

  final SimulatorOrchestrator _orchestrator;

  Stream<SimulatorStatusDto> call() => _orchestrator.watchStatus();
}
