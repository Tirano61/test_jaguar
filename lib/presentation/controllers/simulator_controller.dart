import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:test_jaguar/application/dto/simulator_status_dto.dart';
import 'package:test_jaguar/application/use_cases/send_guardar_event_use_case.dart';
import 'package:test_jaguar/application/use_cases/set_error_ecu_use_case.dart';
import 'package:test_jaguar/application/use_cases/set_manual_measurement_use_case.dart';
import 'package:test_jaguar/application/use_cases/observe_simulator_status_use_case.dart';
import 'package:test_jaguar/application/use_cases/set_humidity_use_case.dart';
import 'package:test_jaguar/application/use_cases/set_hydraulic_peso_use_case.dart';
import 'package:test_jaguar/application/use_cases/set_send_protocol_use_case.dart';
import 'package:test_jaguar/application/use_cases/set_st407_screen_use_case.dart';
import 'package:test_jaguar/application/use_cases/set_st567_options_use_case.dart';
import 'package:test_jaguar/application/use_cases/set_st567_screen_use_case.dart';
import 'package:test_jaguar/application/use_cases/set_toma_fuerza_rpm_use_case.dart';
import 'package:test_jaguar/application/use_cases/set_toma_fuerza_use_case.dart';
import 'package:test_jaguar/application/use_cases/start_simulation_use_case.dart';
import 'package:test_jaguar/application/use_cases/stop_simulation_use_case.dart';
import 'package:test_jaguar/core/constants/ble_constants.dart';
import 'package:test_jaguar/domain/entities/scale_measurement.dart';
import 'package:test_jaguar/domain/value_objects/send_protocol.dart';
import 'package:test_jaguar/protocols/st407_remote/st407_screen.dart';
import 'package:test_jaguar/protocols/st567/st567_screen.dart';
import 'package:test_jaguar/protocols/st567/st567_state.dart';
import 'package:test_jaguar/domain/value_objects/simulation_phase.dart';
import 'package:test_jaguar/presentation/state/simulator_view_state.dart';

class SimulatorController extends ChangeNotifier {
  SimulatorController({
    required StartSimulationUseCase startSimulationUseCase,
    required StopSimulationUseCase stopSimulationUseCase,
    required ObserveSimulatorStatusUseCase observeStatusUseCase,
    required SetHumidityUseCase setHumidityUseCase,
    required SetSendProtocolUseCase setSendProtocolUseCase,
    required SetSt407ScreenUseCase setSt407ScreenUseCase,
    required SetManualMeasurementUseCase setManualMeasurementUseCase,
    required SetTomaFuerzaUseCase setTomaFuerzaUseCase,
    required SetTomaFuerzaRpmUseCase setTomaFuerzaRpmUseCase,
    required SetErrorEcuUseCase setErrorEcuUseCase,
    required SendGuardarEventUseCase sendGuardarEventUseCase,
    required SetHydraulicPesoUseCase setHydraulicPesoUseCase,
    required SetSt567ScreenUseCase setSt567ScreenUseCase,
    required SetSt567OptionsUseCase setSt567OptionsUseCase,
  })  : _startSimulationUseCase = startSimulationUseCase,
        _stopSimulationUseCase = stopSimulationUseCase,
        _observeStatusUseCase = observeStatusUseCase,
        _setHumidityUseCase = setHumidityUseCase,
        _setSendProtocolUseCase = setSendProtocolUseCase,
      _setSt407ScreenUseCase = setSt407ScreenUseCase,
        _setManualMeasurementUseCase = setManualMeasurementUseCase,
        _setTomaFuerzaUseCase = setTomaFuerzaUseCase,
        _setTomaFuerzaRpmUseCase = setTomaFuerzaRpmUseCase,
        _setErrorEcuUseCase = setErrorEcuUseCase,
        _sendGuardarEventUseCase = sendGuardarEventUseCase,
        _setHydraulicPesoUseCase = setHydraulicPesoUseCase,
        _setSt567ScreenUseCase = setSt567ScreenUseCase,
        _setSt567OptionsUseCase = setSt567OptionsUseCase {
    _bind();
  }

  final StartSimulationUseCase _startSimulationUseCase;
  final StopSimulationUseCase _stopSimulationUseCase;
  final ObserveSimulatorStatusUseCase _observeStatusUseCase;
  final SetHumidityUseCase _setHumidityUseCase;
  final SetSendProtocolUseCase _setSendProtocolUseCase;
  final SetSt407ScreenUseCase _setSt407ScreenUseCase;
  final SetManualMeasurementUseCase _setManualMeasurementUseCase;
  final SetTomaFuerzaUseCase _setTomaFuerzaUseCase;
  final SetTomaFuerzaRpmUseCase _setTomaFuerzaRpmUseCase;
  final SetErrorEcuUseCase _setErrorEcuUseCase;
  final SendGuardarEventUseCase _sendGuardarEventUseCase;
  final SetHydraulicPesoUseCase _setHydraulicPesoUseCase;
  final SetSt567ScreenUseCase _setSt567ScreenUseCase;
  final SetSt567OptionsUseCase _setSt567OptionsUseCase;

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

    Future<void> selectSt407Screen(St407Screen screen) =>
      _setSt407ScreenUseCase(screen);

  Future<void> setTomaFuerza(int value) => _setTomaFuerzaUseCase(value);

  Future<void> setTomaFuerzaRpm(int value) =>
      _setTomaFuerzaRpmUseCase(value);

  Future<void> setErrorEcu(String value) => _setErrorEcuUseCase(value);

  Future<void> sendGuardarEvent() => _sendGuardarEventUseCase();

  Future<void> setHydraulicPeso(int value) => _setHydraulicPesoUseCase(value);

  Future<void> selectSt567Screen(St567Screen screen) =>
      _setSt567ScreenUseCase(screen);

  Future<void> setSt567Options(St567Options options) =>
      _setSt567OptionsUseCase(options);

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
      estBalanza: nextHold == 1 ? 3 : _state.manual.estBalanza,
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
        // El perfil lo decide el protocolo activo; acá sólo se muestra.
        serviceUuid: status.bleUuids.serviceUuid,
        characteristicUuid: status.bleUuids.notifyUuid,
        serviceWriteUuid: status.bleUuids.writeServiceUuid,
        characteristicWriteUuid: status.bleUuids.writeUuid,
        st407Screen: status.st407Screen,
        phaseName: status.phase.label,
        weight: status.measurement.peso,
        sensorInduc: status.measurement.sensorInduc,
        estBalanza: status.measurement.estBalanza,
        weightHoldSecondsRemaining: status.weightHoldSecondsRemaining,
        humidity: status.measurement.humedad,
        manual: status.manualMeasurement,
        lastJson: status.lastJson,
        logs: status.logs,
        hidraulico: status.hidraulico,
        st567: status.st567,
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
      tara: tara ?? _state.manual.tara,
      hold: hold ?? _state.manual.hold,
      vbat: vbat ?? _state.manual.vbat,
      peso: weight ?? _state.manual.peso,
      estBalanza: estBalanza ?? _state.manual.estBalanza,
      humedad: humidity ?? _state.manual.humedad,
      sensorInduc: sensorInduc ?? _state.manual.sensorInduc,
    );
    return _setManualMeasurementUseCase(next);
  }
}
