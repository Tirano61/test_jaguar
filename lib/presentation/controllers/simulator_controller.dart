import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:test_jaguar/application/dto/simulator_status_dto.dart';
import 'package:test_jaguar/application/use_cases/set_manual_measurement_use_case.dart';
import 'package:test_jaguar/application/use_cases/observe_simulator_status_use_case.dart';
import 'package:test_jaguar/application/use_cases/set_humidity_use_case.dart';
import 'package:test_jaguar/application/use_cases/set_send_protocol_use_case.dart';
import 'package:test_jaguar/application/use_cases/set_st456_screen_use_case.dart';
import 'package:test_jaguar/application/use_cases/start_simulation_use_case.dart';
import 'package:test_jaguar/application/use_cases/stop_simulation_use_case.dart';
import 'package:test_jaguar/core/constants/ble_constants.dart';
import 'package:test_jaguar/domain/entities/scale_measurement.dart';
import 'package:test_jaguar/domain/value_objects/send_protocol.dart';
import 'package:test_jaguar/domain/value_objects/st456_screen.dart';
import 'package:test_jaguar/domain/value_objects/simulation_phase.dart';
import 'package:test_jaguar/presentation/state/simulator_view_state.dart';

class SimulatorController extends ChangeNotifier {
  SimulatorController({
    required StartSimulationUseCase startSimulationUseCase,
    required StopSimulationUseCase stopSimulationUseCase,
    required ObserveSimulatorStatusUseCase observeStatusUseCase,
    required SetHumidityUseCase setHumidityUseCase,
    required SetSendProtocolUseCase setSendProtocolUseCase,
    required SetSt456ScreenUseCase setSt456ScreenUseCase,
    required SetManualMeasurementUseCase setManualMeasurementUseCase,
  })  : _startSimulationUseCase = startSimulationUseCase,
        _stopSimulationUseCase = stopSimulationUseCase,
        _observeStatusUseCase = observeStatusUseCase,
        _setHumidityUseCase = setHumidityUseCase,
        _setSendProtocolUseCase = setSendProtocolUseCase,
      _setSt456ScreenUseCase = setSt456ScreenUseCase,
        _setManualMeasurementUseCase = setManualMeasurementUseCase {
    _bind();
  }

  final StartSimulationUseCase _startSimulationUseCase;
  final StopSimulationUseCase _stopSimulationUseCase;
  final ObserveSimulatorStatusUseCase _observeStatusUseCase;
  final SetHumidityUseCase _setHumidityUseCase;
  final SetSendProtocolUseCase _setSendProtocolUseCase;
  final SetSt456ScreenUseCase _setSt456ScreenUseCase;
  final SetManualMeasurementUseCase _setManualMeasurementUseCase;

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

  Future<void> setHumidity(double value) => _setHumidityUseCase(value);

  Future<void> selectSendProtocol(SendProtocol protocol) =>
      _setSendProtocolUseCase(protocol);

    Future<void> selectSt456Screen(St456Screen screen) =>
      _setSt456ScreenUseCase(screen);

  Future<void> setManualTara(double value) =>
      _updateManualMeasurement(tara: value.round().clamp(0, 22000));

  Future<void> setManualTaraMax(double value) {
    _state = _state.copyWith(manualTaraMax: value.round().clamp(1, 22000));
    notifyListeners();
    return Future<void>.value();
  }

  Future<void> setManualHold(double value) {
    final int nextHold = value.round().clamp(0, 1);
    return _updateManualMeasurement(
      hold: nextHold,
      estBalanza: nextHold == 1 ? 3 : _state.manualEstBalanza,
    );
  }

  Future<void> setManualVbat(double value) => _updateManualMeasurement(
      vbat: double.parse(value.clamp(0.0, 5.0).toStringAsFixed(1)),
    );

  Future<void> setManualWeight(double value) =>
      _updateManualMeasurement(weight: value.round().clamp(0, 22000));

  Future<void> setManualWeightMax(double value) {
    _state = _state.copyWith(manualWeightMax: value.round().clamp(1, 22000));
    notifyListeners();
    return Future<void>.value();
  }

  Future<void> setManualEstBalanza(double value) {
    final int nextEstBalanza = value.round().clamp(0, 5);
    return _updateManualMeasurement(
      estBalanza: nextEstBalanza,
      hold: nextEstBalanza == 3 ? 1 : 0,
    );
  }

  Future<void> setManualHumidity(double value) => _updateManualMeasurement(
      humidity: double.parse(value.clamp(0.0, 22.0).toStringAsFixed(1)),
    );

  Future<void> setManualSensorInduc(double value) =>
      _updateManualMeasurement(sensorInduc: value.round().clamp(0, 1));

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
        sendProtocol: status.sendProtocol,
        serviceUuid: status.sendProtocol == SendProtocol.st456Remote
          ? BleConstants.st456.serviceUuid
          : BleConstants.jaguar.serviceUuid,
        characteristicUuid: status.sendProtocol == SendProtocol.st456Remote
          ? BleConstants.st456.notifyUuid
          : BleConstants.jaguar.notifyUuid,
        serviceWriteUuid: status.sendProtocol == SendProtocol.st456Remote
          ? BleConstants.st456.writeServiceUuid
          : BleConstants.jaguar.writeServiceUuid,
        characteristicWriteUuid: status.sendProtocol == SendProtocol.st456Remote
          ? BleConstants.st456.writeUuid
          : BleConstants.jaguar.writeUuid,
        st456Screen: status.st456Screen,
        phaseName: status.phase.label,
        weight: status.measurement.peso,
        sensorInduc: status.measurement.sensorInduc,
        estBalanza: status.measurement.estBalanza,
        weightHoldSecondsRemaining: status.weightHoldSecondsRemaining,
        humidity: status.measurement.humedad,
        manualTara: status.manualMeasurement.tara,
        manualHold: status.manualMeasurement.hold,
        manualVbat: status.manualMeasurement.vbat,
        manualWeight: status.manualMeasurement.peso,
        manualEstBalanza: status.manualMeasurement.estBalanza,
        manualHumidity: status.manualMeasurement.humedad,
        manualSensorInduc: status.manualMeasurement.sensorInduc,
        lastJson: status.lastJson,
        logs: status.logs,
      );
      notifyListeners();
    });
  }

  Future<void> _updateManualMeasurement({
    int? tara,
    int? hold,
    double? vbat,
    int? weight,
    int? estBalanza,
    double? humidity,
    int? sensorInduc,
  }) {
    final ScaleMeasurement next = ScaleMeasurement(
      tara: tara ?? _state.manualTara,
      hold: hold ?? _state.manualHold,
      vbat: vbat ?? _state.manualVbat,
      peso: weight ?? _state.manualWeight,
      estBalanza: estBalanza ?? _state.manualEstBalanza,
      humedad: humidity ?? _state.manualHumidity,
      sensorInduc: sensorInduc ?? _state.manualSensorInduc,
    );
    return _setManualMeasurementUseCase(next);
  }
}
