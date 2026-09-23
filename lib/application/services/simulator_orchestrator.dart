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
import 'package:test_jaguar/protocols/manual/manual_protocol.dart';
import 'package:test_jaguar/protocols/protocol_registry.dart';
import 'package:test_jaguar/protocols/shared/scale_automatisms.dart';
import 'package:test_jaguar/protocols/simulator_protocol.dart';
import 'package:test_jaguar/protocols/st407_remote/st407_remote_protocol.dart';
import 'package:test_jaguar/protocols/st407_remote/st407_screen.dart';
import 'package:test_jaguar/protocols/st567/st567_protocol.dart';
import 'package:test_jaguar/protocols/st567/st567_screen.dart';

class SimulatorOrchestrator {
  SimulatorOrchestrator({
    required BlePeripheralRepository bleRepository,
    required ScaleSimulationRepository simulationRepository,
    this.actuatorTickInterval = const Duration(seconds: 1),
  })  : _bleRepository = bleRepository,
        _simulationRepository = simulationRepository {
    _bindSources();
  }

  /// Cada cuánto avanzan el tubo y la guillotina del modo Hidráulico. Se puede
  /// bajar en los tests para no esperar los 6 o 15 segundos reales.
  final Duration actuatorTickInterval;

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

  /// El módulo Remoto ST567. Como el ST407, la pantalla se puede elegir desde
  /// la UI con otro protocolo activo.
  St567Protocol get _st567 =>
      _registry.of(SendProtocol.st567) as St567Protocol;

  /// Congelado de peso y estabilidad. Una sola instancia compartida: el peso
  /// que congela sale del último emitido globalmente, no del protocolo activo.
  final ScaleAutomatisms _automatisms = ScaleAutomatisms(
    sensorInduc: SimulatorStatusDto.initial.measurement.sensorInduc,
  );

  final StreamController<SimulatorStatusDto> _statusController =
      StreamController<SimulatorStatusDto>.broadcast();

  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];

  static const String _resetHoldCommand = 'AT+RSTHOLD';
  static const String _toggleTareCommand = 'AT+TARA';
  static const String _zeroWeightCommand = 'AT+CERO';
  static const String _stopDischargeCommand = 'AT+DETENER';
  static const String _resumeDischargeCommand = 'AT+REANUDAR';
  static const String _finishDischargeCommand = 'AT+FINALIZAR';

  SendProtocol _sendProtocol = SendProtocol.jaguarBle;
  double _selectedHumidity = 10.0;
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
    await _bleRepository.updateBleProfile(
      uuids: _protocol.bleUuids,
      framing: _protocol.framing,
    );
    _automatisms.reset(sensorInduc: _current.measurement.sensorInduc);

    // Limpiar estado ST407 si ya no estamos en ese protocolo
    if (_sendProtocol != SendProtocol.st407Remote) {
      _st407.resetRunState();
    }

    if (_sendProtocol != SendProtocol.st567) {
      _st567.resetRunState();
    }

    // Limpiar estado de ejecución hidráulico si ya no estamos en ese
    // protocolo (tomaFuerza/errorEcu se conservan, son configuración, no
    // estado de una corrida en curso).
    if (_sendProtocol != SendProtocol.hidraulicoBle) {
      _hydraulic.resetRunState();
    }

    _emit(_current.copyWith(
      sendProtocol: _sendProtocol,
      bleUuids: _protocol.bleUuids,
      hidraulico: _hydraulic.state,
      st567: _st567.state,
    ));
    _pushLog('Protocolo seleccionado: ${protocol.label}');
    await _sendCurrentPayloadNow();
    _syncActuatorTicker();
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

  Future<void> setSt567Screen(St567Screen screen) async {
    final String? log = _st567.goTo(screen);
    if (log == null) {
      return;
    }
    _emit(_current.copyWith(st567: _st567.state));
    _pushLog(log);

    if (_sendProtocol == SendProtocol.st567) {
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
    _actuatorTicker?.cancel();
    _actuatorTicker = null;
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
                  : _automatisms.holdSecondsRemaining,
        );

      }),
    );
  }

  // --- Reloj de actuadores del modo Hidráulico ---
  //
  // Es un segundo reloj, aparte del tick del motor de simulación, y corre
  // aunque la simulación esté detenida: el tubo y la guillotina de un equipo
  // real se mueven sin depender de que la balanza esté pesando. Sólo está vivo
  // mientras haya algo que animar.

  Timer? _actuatorTicker;

  void _syncActuatorTicker() {
    final bool needed = _sendProtocol == SendProtocol.hidraulicoBle &&
        _hydraulic.needsActuatorClock;

    if (needed && _actuatorTicker == null) {
      _actuatorTicker = Timer.periodic(
        actuatorTickInterval,
        (_) => unawaited(tickActuators()),
      );
    } else if (!needed && _actuatorTicker != null) {
      _actuatorTicker!.cancel();
      _actuatorTicker = null;
    }
  }

  /// Avanza el tubo y la guillotina un paso de [actuatorTickInterval], publica
  /// lo que haya que loguear y notifica el payload.
  ///
  /// Normalmente lo llama el timer interno una vez por segundo; los tests lo
  /// llaman directo para no esperar los 6 o 15 segundos del recorrido.
  Future<void> tickActuators() async {
    final HydraulicActuatorTick tick =
        _hydraulic.advanceActuators(actuatorTickInterval);

    for (final String line in tick.logs) {
      _pushLog(line);
    }

    // El payload sale primero para que la app vea la tolva en su peso final
    // antes de que le pidan guardar.
    await _sendCurrentPayloadNow();

    final String? saveEvent = tick.saveEvent;
    if (saveEvent != null) {
      if (saveEvent == HydraulicSaveEvent.guardarDos) {
        _pushLog(
          'Modo dos descargas: la app debe mandar un segundo AT+INICIO en '
          'modo 1',
        );
      }
      await _sendSaveEvent(saveEvent);
    }

    _syncActuatorTicker();
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
          _sendProtocol == SendProtocol.manual ? 0 : _automatisms.holdSecondsRemaining,
    );
  }

  Future<void> _notifyAndEmitMeasurement(
    ScaleMeasurement measurement, {
    required int weightHoldSecondsRemaining,
  }) async {
    final String payload = _protocol.encodePayload(measurement);
    try {
      await _bleRepository.notifyUtf8Json(payload);
    } catch (error) {
      _pushLog('Error notify BLE: $error');
    }

    _emit(
      _current.copyWith(
        measurement: measurement,
        sendProtocol: _sendProtocol,
        bleUuids: _protocol.bleUuids,
        st407Screen: _st407.screen,
        manualMeasurement: _manual.measurement,
        hidraulico: _hydraulic.state,
        st567: _st567.state,
        weightHoldSecondsRemaining: weightHoldSecondsRemaining,
        lastJson: payload,
      ),
    );
  }

  /// De dónde sale el peso en cada modo. Es la única tabla de despacho por
  /// protocolo que queda: cada rama delega en un módulo.
  ScaleMeasurement _measurementForCurrentProtocol(ScaleMeasurement engine) {
    // Manual ignora el motor: manda lo que el tester dejó en los sliders.
    if (_sendProtocol == SendProtocol.manual) {
      return _manual.measurement;
    }

    // Hidráulico tampoco usa el ciclo de fases: el peso sólo se mueve si hay
    // una descarga en curso, y el tick es su reloj.
    if (_sendProtocol == SendProtocol.hidraulicoBle) {
      return _hydraulic.advance(humidity: _selectedHumidity);
    }

    final ScaleMeasurement base = engine.copyWith(humedad: _selectedHumidity);

    // El ST567 no usa los automatismos de balanza: su pantalla principal
    // muestra el peso del motor tal cual, y la estabilidad la deduce el módulo.
    if (_sendProtocol == SendProtocol.st567) {
      return _st567.advance(base, log: _pushLog);
    }

    // En las pantallas de carga del ST407 el peso lo anima el protocolo.
    if (_sendProtocol == SendProtocol.st407Remote && _st407.isLoadingScreen) {
      return _st407.advanceLoading(base);
    }

    // Jaguar, y el ST407 fuera de las pantallas de carga: peso del motor con
    // los automatismos de balanza encima.
    return _automatisms.apply(
      base,
      lastEmitted: _current.measurement,
      log: _pushLog,
    );
  }

  double _normalizeHumidity(double value) {
    final double clamped = value.clamp(0.0, 22.0);
    return double.parse(clamped.toStringAsFixed(1));
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
        weightHoldSecondsRemaining: _automatisms.holdSecondsRemaining,
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
    // Un AT+INICIO o un AT+MOVIMIENTO pueden dejar actuadores en movimiento, y
    // un AT+FINALIZAR puede dejar de necesitar el reloj.
    _syncActuatorTicker();
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
