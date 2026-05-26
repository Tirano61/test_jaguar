import 'package:test_jaguar/application/services/simulator_orchestrator.dart';
import 'package:test_jaguar/domain/value_objects/send_protocol.dart';

class SetSendProtocolUseCase {
  const SetSendProtocolUseCase(this._orchestrator);

  final SimulatorOrchestrator _orchestrator;

  Future<void> call(SendProtocol protocol) =>
      _orchestrator.setSendProtocol(protocol);
}
