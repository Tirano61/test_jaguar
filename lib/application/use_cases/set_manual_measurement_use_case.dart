import 'package:test_jaguar/application/services/simulator_orchestrator.dart';
import 'package:test_jaguar/domain/entities/scale_measurement.dart';

class SetManualMeasurementUseCase {
  const SetManualMeasurementUseCase(this._orchestrator);

  final SimulatorOrchestrator _orchestrator;

  Future<void> call(ScaleMeasurement measurement) =>
      _orchestrator.setManualMeasurement(measurement);
}
