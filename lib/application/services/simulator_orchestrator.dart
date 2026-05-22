import 'dart:async';

import 'package:test_jaguar/application/dto/scale_payload_dto.dart';
import 'package:test_jaguar/application/dto/simulator_status_dto.dart';
import 'package:test_jaguar/core/extensions/stream_subscription_extensions.dart';
import 'package:test_jaguar/domain/entities/ble_peripheral_status.dart';
import 'package:test_jaguar/domain/repositories/ble_peripheral_repository.dart';
import 'package:test_jaguar/domain/repositories/scale_simulation_repository.dart';

class SimulatorOrchestrator {
  SimulatorOrchestrator({
    required BlePeripheralRepository bleRepository,
    required ScaleSimulationRepository simulationRepository,
  })  : _bleRepository = bleRepository,
        _simulationRepository = simulationRepository {
    _bindSources();
  }

  final BlePeripheralRepository _bleRepository;
  final ScaleSimulationRepository _simulationRepository;

  final StreamController<SimulatorStatusDto> _statusController =
      StreamController<SimulatorStatusDto>.broadcast();

  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];

  SimulatorStatusDto _current = SimulatorStatusDto.initial;

  Stream<SimulatorStatusDto> watchStatus() => _statusController.stream;

  Future<void> start() async {
    await _bleRepository.startAdvertising();
    await _simulationRepository.start();
    _pushLog('Simulacion iniciada');
  }

  Future<void> stop() async {
    await _simulationRepository.stop();
    await _bleRepository.stopAdvertising();
    _pushLog('Simulacion detenida');
  }

  Future<void> dispose() async {
    await _subscriptions.cancelAll();
    await _simulationRepository.dispose();
    await _bleRepository.dispose();
    await _statusController.close();
  }

  void _bindSources() {
    _subscriptions.add(
      _bleRepository.watchStatus().listen((status) {
        final List<String> logs = _logsForBleStatusChange(
          previous: _current.bleStatus,
          next: status,
        );
        _emit(
          _current.copyWith(
            bleStatus: status,
            logs: logs.isEmpty
                ? _current.logs
                : <String>[...logs, ..._current.logs].take(100).toList(),
          ),
        );
      }),
    );

    _subscriptions.add(
      _simulationRepository.watchRunning().listen((running) {
        _emit(_current.copyWith(running: running));
      }),
    );

    _subscriptions.add(
      _simulationRepository.watchPhase().listen((phase) {
        _emit(_current.copyWith(phase: phase));
      }),
    );

    _subscriptions.add(
      _simulationRepository.watchMeasurements().listen((measurement) async {
        final String json =
            ScalePayloadDto(measurement: measurement).toJsonUtf8String();
        try {
          await _bleRepository.notifyUtf8Json(json);
        } catch (error) {
          _pushLog('Error notify BLE: $error');
        }
        _emit(_current.copyWith(measurement: measurement, lastJson: json));
      }),
    );
  }

  List<String> _logsForBleStatusChange({
    required BlePeripheralStatus previous,
    required BlePeripheralStatus next,
  }) {
    final List<String> logs = <String>[];

    if (previous.adapterEnabled != next.adapterEnabled) {
      logs.add(next.adapterEnabled ? 'BLE habilitado' : 'BLE deshabilitado');
    }

    if (previous.advertising != next.advertising) {
      logs.add(next.advertising
          ? 'Advertising BLE iniciado'
          : 'Advertising BLE detenido');
    }

    if (previous.connected != next.connected) {
      logs.add(next.connected
          ? 'Central BLE conectada'
          : 'Central BLE desconectada');
    }

    if (previous.connectedDeviceId != next.connectedDeviceId &&
        next.connectedDeviceId != null) {
      logs.add('Central activa: ${next.connectedDeviceId}');
    }

    return logs;
  }

  void _pushLog(String line) {
    final List<String> updatedLogs = <String>[line, ..._current.logs];
    _emit(_current.copyWith(logs: updatedLogs.take(100).toList()));
  }

  void _emit(SimulatorStatusDto value) {
    _current = value;
    if (!_statusController.isClosed) {
      _statusController.add(value);
    }
  }
}
