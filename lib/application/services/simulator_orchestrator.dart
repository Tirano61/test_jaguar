import 'dart:async';

import 'package:test_jaguar/application/dto/simulator_status_dto.dart';
import 'package:test_jaguar/core/extensions/stream_subscription_extensions.dart';
import 'package:test_jaguar/domain/entities/ble_peripheral_status.dart';
import 'package:test_jaguar/domain/entities/scale_measurement.dart';
import 'package:test_jaguar/domain/repositories/ble_peripheral_repository.dart';
import 'package:test_jaguar/domain/repositories/scale_simulation_repository.dart';
import 'package:test_jaguar/domain/value_objects/send_protocol.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_discharge_command.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_movement_command.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_protocol.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_state.dart';
import 'package:test_jaguar/protocols/manual/manual_protocol.dart';
import 'package:test_jaguar/protocols/protocol_registry.dart';
import 'package:test_jaguar/protocols/shared/scale_payload.dart';
import 'package:test_jaguar/protocols/simulator_protocol.dart';
import 'package:test_jaguar/protocols/st407_remote/st407_remote_protocol.dart';
import 'package:test_jaguar/protocols/st407_remote/st407_screen.dart';

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
  final ProtocolRegistry _registry = ProtocolRegistry.standard();

  /// Implementación del protocolo seleccionado. Es la que sabe qué perfil GATT
  /// anunciar y cómo enmarcar el payload, en vez de que lo decida un `if` acá.
  SimulatorProtocol get _protocol => _registry.of(_sendProtocol);

  /// El módulo Hidráulico BLE, que es dueño de su estado y de su máquina de
  /// descarga. Se accede aunque no sea el protocolo activo: su configuración
  /// (toma de fuerza, errorEcu) sigue viva entre cambios de modo.
  HydraulicProtocol get _hydraulic =>
      _registry.of(SendProtocol.hidraulicoBle) as HydraulicProtocol;

  /// El módulo Manual. También se accede con otro protocolo activo: `AT+RSTHOLD`
  /// no tiene guard y le llega igual.
  ManualProtocol get _manual =>
      _registry.of(SendProtocol.manual) as ManualProtocol;

  /// El módulo Remoto ST407. La pantalla seleccionada se puede cambiar desde la
  /// UI con otro protocolo activo, así que también se accede fuera de su modo.
  St407RemoteProtocol get _st407 =>
      _registry.of(SendProtocol.st407Remote) as St407RemoteProtocol;

  final StreamController<SimulatorStatusDto> _statusController =
      StreamController<SimulatorStatusDto>.broadcast();

  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];

  static const int _weightHoldTicksAfterSensorChange = 5;
  static const String _resetHoldCommand = 'AT+RSTHOLD';
  static const String _toggleTareCommand = 'AT+TARA';
  static const String _zeroWeightCommand = 'AT+CERO';
  static const String _stopDischargeCommand = 'AT+DETENER';
  static const String _resumeDischargeCommand = 'AT+REANUDAR';
  static const String _finishDischargeCommand = 'AT+FINALIZAR';

  SendProtocol _sendProtocol = SendProtocol.jaguarBle;
  double _selectedHumidity = 10.0;
  int _lastSensorInduc = SimulatorStatusDto.initial.measurement.sensorInduc;
  int _weightHoldTicksRemaining = 0;
  int? _heldWeight;
  SimulatorStatusDto _current = SimulatorStatusDto.initial;

  int _lastProcessedCommandSequence = -1;

  double get selectedHumidity => _selectedHumidity;

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

  Future<void> setSendProtocol(SendProtocol protocol) async {
    if (_sendProtocol == protocol) {
      return;
    }
    _sendProtocol = protocol;
    await _bleRepository.updateBleUuids(_protocol.bleUuids);
    _weightHoldTicksRemaining = 0;
    _heldWeight = null;
    _lastSensorInduc = _current.measurement.sensorInduc;

    // Limpiar estado ST407 si ya no estamos en ese protocolo
    if (_sendProtocol != SendProtocol.st407Remote) {
      _st407.resetRunState();
    }

    // Limpiar estado de ejecución hidráulico si ya no estamos en ese
    // protocolo (tomaFuerza/errorEcu se conservan, son configuración, no
    // estado de una corrida en curso).
    if (_sendProtocol != SendProtocol.hidraulicoBle) {
      _hydraulic.resetRunState();
    }

    _emit(_withHydraulicSnapshot(_current.copyWith(
      sendProtocol: _sendProtocol,
      bleUuids: _protocol.bleUuids,
    )));
    _pushLog('Protocolo seleccionado: ${protocol.label}');
    await _sendCurrentPayloadNow();
  }

  // La configuración del modo Hidráulico vive en su módulo; acá sólo se
  // publica el log que devuelve y se empuja el payload.

  Future<void> setHydraulicPeso(int value) =>
      _applyHydraulicConfig(_hydraulic.setPeso(value));

  Future<void> setTomaFuerza(int value) =>
      _applyHydraulicConfig(_hydraulic.setTomaFuerza(value));

  /// RPM simuladas de la toma de fuerza. Se pueden configurar en cualquier
  /// estado, pero el JSON solo las manda con la toma de fuerza encendida.
  Future<void> setTomaFuerzaRpm(int value) =>
      _applyHydraulicConfig(_hydraulic.setTomaFuerzaRpm(value));

  Future<void> setErrorEcu(String value) =>
      _applyHydraulicConfig(_hydraulic.setErrorEcu(value));

  /// [log] en null significa que el módulo no aplicó ningún cambio: no hay
  /// nada que loguear ni que reenviar.
  Future<void> _applyHydraulicConfig(String? log) async {
    if (log == null) {
      return;
    }
    _pushLog(log);
    await _sendCurrentPayloadNow();
  }

  /// Envía el evento `AT+GUARDAR` crudo por notify BLE. Lo usa el botón manual
  /// de la UI, que siempre manda el cierre clásico; el disparo automático al
  /// completar una descarga pasa igual por [_sendSaveEvent], pero manda
  /// `AT+GUARDARDOS` cuando la corrida se inició con modo 2.
  Future<void> sendGuardarEvent() =>
      _sendSaveEvent(HydraulicSaveEvent.guardar);

  /// Notifica uno de los eventos de guardado crudos. Centralizado para que el
  /// terminador `\r\n` no se pueda desincronizar entre los dos.
  Future<void> _sendSaveEvent(String event) async {
    try {
      await _bleRepository.notifyUtf8Json('$event\r\n');
    } catch (error) {
      _pushLog('Error enviando $event: $error');
      return;
    }
    _pushLog('$event enviado');
  }

  Future<void> setSt407Screen(St407Screen screen) async {
    if (!_st407.selectScreen(screen)) {
      return;
    }

    // La pantalla se cambia, se emite y se loguea aunque el protocolo activo
    // sea otro; sembrar sus contadores y reenviar sólo pasa si está activo.
    // Comportamiento heredado.
    _emit(_current.copyWith(st407Screen: _st407.screen));
    _pushLog('Pantalla ST407 seleccionada: ${screen.label}');

    if (_sendProtocol == SendProtocol.st407Remote) {
      _st407.seedScreenState(currentPeso: _current.measurement.peso);
      await _sendCurrentPayloadNow();
    }
  }

  Future<void> setManualMeasurement(ScaleMeasurement measurement) async {
    _manual.set(measurement);
    _emit(_current.copyWith(manualMeasurement: _manual.measurement));

    if (_sendProtocol == SendProtocol.manual) {
      await _sendCurrentPayloadNow();
    }
  }

  /// Publica el resultado de un comando del modo Manual. [log] en null
  /// significa que el módulo no cambió nada: ni emisión, ni log, ni reenvío.
  ///
  /// El orden importa: primero se emite la medición y recién después el log,
  /// igual que antes, porque `_pushLog` también emite.
  Future<void> _applyManualCommand(String? log) async {
    if (log == null) {
      return;
    }
    _emit(_current.copyWith(manualMeasurement: _manual.measurement));
    _pushLog(log);
    await _sendCurrentPayloadNow();
  }

  Future<void> setHumidity(double value) async {
    _selectedHumidity = _normalizeHumidity(value);
    final updatedMeasurement =
        _current.measurement.copyWith(humedad: _selectedHumidity);
    _emit(_current.copyWith(measurement: updatedMeasurement));
    await _sendCurrentPayloadNow();
    _pushLog('Humedad configurada: ${_selectedHumidity.toStringAsFixed(1)}');
  }

  Future<void> dispose() async {
    await _subscriptions.cancelAll();
    await _simulationRepository.dispose();
    await _bleRepository.dispose();
    await _statusController.close();
  }

  void _bindSources() {
    _subscriptions.add(
      _bleRepository.watchStatus().listen((status) async {
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

        // status.commandSequence sólo cambia con un write real; sin este
        // guard, cualquier emisión de watchStatus() no relacionada
        // (adapter on/off, conexión de central, etc.) reprocesaría el mismo
        // último comando recibido, lo cual es inaceptable para AT+INICIO
        // (reiniciaría la descarga simulada) y AT+GUARDAR (se reenviaría).
        if (status.commandSequence != _lastProcessedCommandSequence) {
          _lastProcessedCommandSequence = status.commandSequence;
          await _applyIncomingCommandIfNeeded(status.lastReceivedCommand);
        }
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
        final ScaleMeasurement outgoingMeasurement =
            _measurementForCurrentProtocol(measurement);
        await _notifyAndEmitMeasurement(
          outgoingMeasurement,
          weightHoldSecondsRemaining:
              _sendProtocol == SendProtocol.manual
                  ? 0
                  : _weightHoldTicksRemaining,
        );

        // Se drena DESPUÉS de notificar el payload del tick, para que la app
        // vea la tolva en su peso final antes de que le pidan guardar. El
        // módulo lo entrega una sola vez, así que un AT+INICIO que se
        // intercale no puede pisar el evento de la corrida que está cerrando.
        final String? saveEvent = _hydraulic.takeCompletedSaveEvent();
        if (saveEvent != null) {
          final bool dosDescargas =
              saveEvent == HydraulicSaveEvent.guardarDos;
          _pushLog(
            'Descarga hidráulica completada (peso objetivo alcanzado): '
            'enviando $saveEvent'
            '${dosDescargas ? ' (modo dos descargas: la app debe mandar un '
                'segundo AT+INICIO en modo 1)' : ''}',
          );
          await _sendSaveEvent(saveEvent);
        }
      }),
    );
  }


  Future<void> _sendCurrentPayloadNow() async {
    // El peso del modo hidráulico no pasa por el motor de simulación: leer
    // _current.measurement acá lo dejaba desactualizado hasta el próximo tick
    // (y con la simulación detenida, para siempre), así que cada envío fuera
    // del tick mandaba el peso viejo.
    final ScaleMeasurement measurement;
    if (_sendProtocol == SendProtocol.manual) {
      measurement = _manual.measurement;
    } else if (_sendProtocol == SendProtocol.hidraulicoBle) {
      measurement = _hydraulic.measurement(humidity: _selectedHumidity);
    } else {
      measurement = _current.measurement.copyWith(humedad: _selectedHumidity);
    }
    await _notifyAndEmitMeasurement(
      measurement,
      weightHoldSecondsRemaining:
          _sendProtocol == SendProtocol.manual ? 0 : _weightHoldTicksRemaining,
    );
  }

  Future<void> _notifyAndEmitMeasurement(
    ScaleMeasurement measurement, {
    required int weightHoldSecondsRemaining,
  }) async {
    final String payload = _payloadForCurrentProtocol(measurement);
    try {
      await _bleRepository.notifyUtf8Json(payload);
    } catch (error) {
      _pushLog('Error notify BLE: $error');
    }

    _emit(
      _withHydraulicSnapshot(
        _current.copyWith(
          measurement: measurement,
          sendProtocol: _sendProtocol,
          bleUuids: _protocol.bleUuids,
          st407Screen: _st407.screen,
          manualMeasurement: _manual.measurement,
          weightHoldSecondsRemaining: weightHoldSecondsRemaining,
          lastJson: payload,
        ),
      ),
    );
  }

  /// Proyecta el estado del módulo Hidráulico en el DTO.
  ///
  /// Sigue aplanando los campos porque el DTO todavía los tiene sueltos; al
  /// partirlo en sub-objetos por protocolo esto pasa a ser `hidraulico: state`.
  SimulatorStatusDto _withHydraulicSnapshot(SimulatorStatusDto value) {
    final HydraulicState state = _hydraulic.state;
    return value.copyWith(
      tomaFuerza: state.tomaFuerza,
      tomaFuerzaRpm: state.tomaFuerzaRpm,
      errorEcu: state.errorEcu,
      tuboPosicion: state.tuboPosicion,
      guillotinaPosicion: state.guillotinaPosicion,
      hydraulicDischargeActive: state.dischargeActive,
      hydraulicDischargePaused: state.dischargePaused,
      hydraulicInitialPeso: state.initialPeso,
      hydraulicTargetPeso: state.targetPeso,
      lastHydraulicInicio: state.lastInicio,
      lastHydraulicMovimiento: state.lastMovimiento,
    );
  }

  String _payloadForCurrentProtocol(ScaleMeasurement measurement) {
    if (_sendProtocol == SendProtocol.hidraulicoBle) {
      return _hydraulic.encodePayload(measurement);
    }

    if (_sendProtocol == SendProtocol.st407Remote) {
      return _st407.encodePayload(measurement);
    }

    return ScalePayloadDto(measurement: measurement).toJsonUtf8String();
  }

  ScaleMeasurement _measurementForCurrentProtocol(ScaleMeasurement measurement) {
    if (_sendProtocol == SendProtocol.manual) {
      return _manual.measurement;
    }

    // Hidráulico BLE no usa el motor de simulación automático (measurement,
    // el tick de fases carga/descarga): el peso queda fijo salvo que el
    // tester lo edite a mano o haya una descarga activa por AT+INICIO, y
    // sensorInduc nunca cambia (la app conectada maneja la transición
    // carga/descarga por comando, no por sensor).
    if (_sendProtocol == SendProtocol.hidraulicoBle) {
      // Sólo una descarga en curso y no pausada por AT+DETENER baja el peso
      // en este tick: pausada, queda donde estaba y la corrida sigue viva
      return _hydraulic.advance(humidity: _selectedHumidity);
    }

    ScaleMeasurement base = measurement.copyWith(humedad: _selectedHumidity);

    // En las pantallas de carga el peso lo anima el propio protocolo, asi
    // que el que trae el motor se ignora.
    if (_sendProtocol == SendProtocol.st407Remote && _st407.isLoadingScreen) {
      return _st407.advanceLoading(base);
    }

    return _withScaleStateFromWeightChange(_withWeightHoldAfterSensorChange(base));
  }

  double _normalizeHumidity(double value) {
    final double clamped = value.clamp(0.0, 22.0);
    return double.parse(clamped.toStringAsFixed(1));
  }

  ScaleMeasurement _withWeightHoldAfterSensorChange(
    ScaleMeasurement measurement,
  ) {
    final int previousSensorInduc = _lastSensorInduc;
    if (measurement.sensorInduc != previousSensorInduc) {
      _lastSensorInduc = measurement.sensorInduc;
      _weightHoldTicksRemaining = _weightHoldTicksAfterSensorChange;
      _heldWeight = _current.measurement.peso;
      _pushLog(
        'Cambio sensorInduc $previousSensorInduc -> ${measurement.sensorInduc}: peso congelado 5s',
      );
    }

    if (_weightHoldTicksRemaining > 0 && _heldWeight != null) {
      _weightHoldTicksRemaining -= 1;
      return measurement.copyWith(peso: _heldWeight);
    }

    return measurement;
  }

  ScaleMeasurement _withScaleStateFromWeightChange(
    ScaleMeasurement measurement,
  ) {
    final bool weightChanged = measurement.peso != _current.measurement.peso;
    return measurement.copyWith(estBalanza: weightChanged ? 0 : 1);
  }

  Future<void> _applyIncomingCommandIfNeeded(String? command) async {
    if (command == null || command.isEmpty) {
      return;
    }

    final String normalizedCommand = _normalizeIncomingCommand(command);
    if (normalizedCommand.isEmpty) {
      return;
    }

    // AT+RSTHOLD es el único comando sin guard de protocolo: se aplica al modo
    // Manual aunque el activo sea otro, y entonces reenvía un payload del
    // protocolo activo, no uno manual. Comportamiento heredado, fijado por
    // `at_command_routing_test.dart`.
    if (_isResetHoldCommand(normalizedCommand)) {
      await _applyManualCommand(_manual.applyResetHold());
      return;
    }

    if (_isToggleTareCommand(normalizedCommand)) {
      if (_sendProtocol != SendProtocol.manual) {
        return;
      }
      await _applyManualCommand(_manual.applyToggleTare());
      return;
    }

    if (_isZeroWeightCommand(normalizedCommand)) {
      if (_sendProtocol == SendProtocol.manual) {
        await _applyManualCommand(_manual.applyZeroWeight());
        return;
      }

      final ScaleMeasurement currentMeasurement = _current.measurement;
      if (currentMeasurement.tara > 0 || currentMeasurement.peso == 0) {
        return;
      }

      final ScaleMeasurement zeroedMeasurement =
          currentMeasurement.copyWith(peso: 0);
      _pushLog('Comando aplicado: AT+CERO -> peso=0 (jaguar)');
      await _notifyAndEmitMeasurement(
        zeroedMeasurement,
        weightHoldSecondsRemaining: _weightHoldTicksRemaining,
      );
      return;
    }

    if (_isStopDischargeCommand(normalizedCommand)) {
      if (_sendProtocol == SendProtocol.hidraulicoBle) {
        await _applyHydraulicCommand(_hydraulic.applyDetener());
      } else {
        _pushLog(
          'AT+DETENER recibido pero se ignora: seleccioná "Hidráulico BLE" '
          'para procesarlo.',
        );
      }
      return;
    }

    if (_isResumeDischargeCommand(normalizedCommand)) {
      if (_sendProtocol == SendProtocol.hidraulicoBle) {
        await _applyHydraulicCommand(_hydraulic.applyReanudar());
      } else {
        _pushLog(
          'AT+REANUDAR recibido pero se ignora: seleccioná "Hidráulico BLE" '
          'para procesarlo.',
        );
      }
      return;
    }

    if (_isFinishDischargeCommand(normalizedCommand)) {
      if (_sendProtocol == SendProtocol.hidraulicoBle) {
        await _applyHydraulicCommand(_hydraulic.applyFinalizar());
      } else {
        _pushLog(
          'AT+FINALIZAR recibido pero se ignora: seleccioná "Hidráulico BLE" '
          'para procesarlo.',
        );
      }
      return;
    }

    final HydraulicDischargeCommand? inicio =
        HydraulicDischargeCommand.tryParse(normalizedCommand);
    if (inicio != null) {
      if (_sendProtocol == SendProtocol.hidraulicoBle) {
        await _applyHydraulicCommand(_hydraulic.applyInicio(inicio));
      } else {
        _pushLog(
          'AT+INICIO recibido pero se ignora: seleccioná "Hidráulico BLE" '
          'para procesarlo (${inicio.summary}).',
        );
      }
      return;
    }

    final HydraulicMovementCommand? movimiento =
        HydraulicMovementCommand.tryParse(normalizedCommand);
    if (movimiento != null) {
      if (_sendProtocol == SendProtocol.hidraulicoBle) {
        await _applyHydraulicCommand(
            _hydraulic.applyMovimiento(movimiento));
      } else {
        _pushLog(
          'AT+MOVIMIENTO recibido pero se ignora: seleccioná "Hidráulico BLE" '
          'para procesarlo (${movimiento.label}).',
        );
      }
      return;
    }
  }

  /// Publica el log que devolvió un comando hidráulico y empuja el payload.
  /// Todos los comandos del modo hacen las dos cosas, incluidos los que no
  /// cambian nada (por ejemplo `AT+DETENER` sin descarga en curso).
  Future<void> _applyHydraulicCommand(String log) async {
    _pushLog(log);
    await _sendCurrentPayloadNow();
  }


  String _normalizeIncomingCommand(String command) {
    return command
        .toUpperCase()
        .replaceAll(RegExp(r'\\[RNS]'), '')
        .replaceAll(RegExp(r'\\X[0-9A-F]{2}'), '')
        .replaceAll(RegExp(r'[\r\n\t\s]'), '')
        .replaceAll(r'\', '')
        .trim();
  }

  bool _isResetHoldCommand(String normalizedCommand) =>
      normalizedCommand == _resetHoldCommand;

  bool _isToggleTareCommand(String normalizedCommand) =>
      normalizedCommand == _toggleTareCommand || normalizedCommand == 'TARA';

  bool _isZeroWeightCommand(String normalizedCommand) =>
      normalizedCommand == _zeroWeightCommand || normalizedCommand == 'CERO';

  // Comandos sin parámetros: se aceptan pelados y también con el `=` del nuevo
  // formato del protocolo hidráulico, por si la app los manda igual que el
  // resto (AT+DETENER=, AT+REANUDAR=, AT+FINALIZAR=).
  bool _isStopDischargeCommand(String normalizedCommand) =>
      normalizedCommand == _stopDischargeCommand ||
      normalizedCommand == '$_stopDischargeCommand=';

  bool _isResumeDischargeCommand(String normalizedCommand) =>
      normalizedCommand == _resumeDischargeCommand ||
      normalizedCommand == '$_resumeDischargeCommand=';

  bool _isFinishDischargeCommand(String normalizedCommand) =>
      normalizedCommand == _finishDischargeCommand ||
      normalizedCommand == '$_finishDischargeCommand=';

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

    if (previous.lastReceivedCommand != next.lastReceivedCommand &&
        next.lastReceivedCommand != null &&
        next.lastReceivedCommand!.isNotEmpty) {
      logs.add('Comando recibido: ${next.lastReceivedCommand}');
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
