import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:test_jaguar/application/dto/simulator_status_dto.dart';
import 'package:test_jaguar/application/use_cases/observe_simulator_status_use_case.dart';
import 'package:test_jaguar/application/use_cases/start_simulation_use_case.dart';
import 'package:test_jaguar/application/use_cases/stop_simulation_use_case.dart';
import 'package:test_jaguar/core/constants/ble_constants.dart';
import 'package:test_jaguar/domain/value_objects/simulation_phase.dart';
import 'package:test_jaguar/presentation/state/simulator_view_state.dart';

class SimulatorController extends ChangeNotifier {
  SimulatorController({
    required StartSimulationUseCase startSimulationUseCase,
    required StopSimulationUseCase stopSimulationUseCase,
    required ObserveSimulatorStatusUseCase observeStatusUseCase,
  })  : _startSimulationUseCase = startSimulationUseCase,
        _stopSimulationUseCase = stopSimulationUseCase,
        _observeStatusUseCase = observeStatusUseCase {
    _bind();
  }

  final StartSimulationUseCase _startSimulationUseCase;
  final StopSimulationUseCase _stopSimulationUseCase;
  final ObserveSimulatorStatusUseCase _observeStatusUseCase;

  StreamSubscription<SimulatorStatusDto>? _statusSubscription;

  SimulatorViewState _state = SimulatorViewState.initial.copyWith(
    serviceUuid: BleConstants.serviceUuid,
    characteristicUuid: BleConstants.characteristicUuid,
    serviceWriteUuid: BleConstants.serviceWriteUuid,
    characteristicWriteUuid: BleConstants.characteristicWriteUuid,
  );

  SimulatorViewState get state => _state;

  Future<void> startSimulation() => _startSimulationUseCase();

  Future<void> stopSimulation() => _stopSimulationUseCase();

  @override
  void dispose() {
    _statusSubscription?.cancel();
    super.dispose();
  }

  void _bind() {
    _statusSubscription = _observeStatusUseCase().listen((status) {
      _state = _state.copyWith(
        bleEnabled: status.bleStatus.adapterEnabled,
        advertising: status.bleStatus.advertising,
        connected: status.bleStatus.connected,
        connectedDeviceId: status.bleStatus.connectedDeviceId,
        lastReceivedCommand: status.bleStatus.lastReceivedCommand,
        running: status.running,
        phaseName: status.phase.label,
        weight: status.measurement.peso,
        sensorInduc: status.measurement.sensorInduc,
        lastJson: status.lastJson,
        logs: status.logs,
      );
      notifyListeners();
    });
  }
}
