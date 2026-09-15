import 'dart:async';

import 'package:test_jaguar/application/dto/scale_payload_dto.dart';
import 'package:test_jaguar/application/dto/simulator_status_dto.dart';
import 'package:test_jaguar/application/dto/st407_payload_dto.dart';
import 'package:test_jaguar/core/extensions/stream_subscription_extensions.dart';
import 'package:test_jaguar/domain/entities/ble_peripheral_status.dart';
import 'package:test_jaguar/domain/entities/scale_measurement.dart';
import 'package:test_jaguar/domain/repositories/ble_peripheral_repository.dart';
import 'package:test_jaguar/domain/repositories/scale_simulation_repository.dart';
import 'package:test_jaguar/domain/value_objects/send_protocol.dart';
import 'package:test_jaguar/domain/value_objects/st407_screen.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_discharge_command.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_movement_command.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_protocol.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_state.dart';
import 'package:test_jaguar/protocols/protocol_registry.dart';
import 'package:test_jaguar/protocols/simulator_protocol.dart';

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
  St407Screen _st407Screen = St407Screen.main;
  double _selectedHumidity = 10.0;
  ScaleMeasurement _manualMeasurement = ScaleMeasurement.baseline;
  // Estado para simulación de "kg a cargar" y parcial en pantallas ST407
  double? _st407InitialKgToLoad;
  // Peso actual mostrado en la pantalla de carga (disminuye lentamente)
  double _st407CurrentDisplayedPeso = 0.0;
  bool _st407LoadingActive = false;
  // decremento por tick aplicado al peso actual mostrado
  final double _st407DecrementPerTick = 1.0;
  // Estado de cuenta regresiva para pantalla 105 (mezclando): inicia en 4:30
  bool _st407MixingCountdownActive = false;
  int _st407MixingCurrentSeconds = 4 * 60 + 30;
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
      _st407LoadingActive = false;
      _st407InitialKgToLoad = null;
      _st407CurrentDisplayedPeso = 0.0;
      _st407MixingCountdownActive = false;
      _st407MixingCurrentSeconds = 4 * 60 + 30;
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
    if (_st407Screen == screen) {
      return;
    }

    _st407Screen = screen;
    _emit(_current.copyWith(st407Screen: _st407Screen));
    _pushLog('Pantalla ST407 seleccionada: ${screen.label}');

    if (_sendProtocol == SendProtocol.st407Remote) {
      // Inicializar estado de carga cuando se seleccionan pantallas de carga
      if (screen == St407Screen.loadingRecipe || screen == St407Screen.loadingManual) {
        _st407InitialKgToLoad = _current.measurement.peso.toDouble();
        // peso mostrado parte del peso actual y luego irá bajando
        _st407CurrentDisplayedPeso = _st407InitialKgToLoad ?? 0.0;
        _st407LoadingActive = true;
        _st407MixingCountdownActive = false;
        _st407MixingCurrentSeconds = 4 * 60 + 30;
      } else if (screen == St407Screen.mixing) {
        _st407LoadingActive = false;
        _st407InitialKgToLoad = null;
        _st407CurrentDisplayedPeso = 0.0;
        _st407MixingCountdownActive = true;
        _st407MixingCurrentSeconds = 4 * 60 + 30;
      } else {
        _st407LoadingActive = false;
        _st407InitialKgToLoad = null;
        _st407CurrentDisplayedPeso = 0.0;
        _st407MixingCountdownActive = false;
        _st407MixingCurrentSeconds = 4 * 60 + 30;
      }
      await _sendCurrentPayloadNow();
    }
  }

  Future<void> setManualMeasurement(ScaleMeasurement measurement) async {
    _manualMeasurement = _normalizeManualMeasurement(measurement);
    _emit(_current.copyWith(manualMeasurement: _manualMeasurement));

    if (_sendProtocol == SendProtocol.manual) {
      await _sendCurrentPayloadNow();
    }
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
      measurement = _manualMeasurement;
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
          st407Screen: _st407Screen,
          manualMeasurement: _manualMeasurement,
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
      // Para pantallas de carga (loadingRecipe, loadingManual) necesitamos
      // mantener un 'kg a cargar' que parte del valor inicial de peso actual
      // y va disminuyendo muy de a poco; el campo 'parcial' debe reflejar
      // lo que ya se fue descargando (initial - current).
      if (_st407Screen == St407Screen.loadingRecipe ||
          _st407Screen == St407Screen.loadingManual) {
        // Asegurar inicialización del valor estático "kg a cargar"
        if (!_st407LoadingActive || _st407InitialKgToLoad == null) {
          _st407InitialKgToLoad = measurement.peso.toDouble();
          _st407CurrentDisplayedPeso = _st407InitialKgToLoad ?? 0.0;
          _st407LoadingActive = true;
        }

        // 'kg a cargar' debe mantener el valor inicial (estático)
        final double initial = _st407InitialKgToLoad ?? measurement.peso.toDouble();
        // 'peso actual' se toma del measurement que llega (debe bajar)
        final double pesoActual = measurement.peso.toDouble();
        // 'parcial' es lo que ya se descargó: initial - pesoActual (no negativo)
        final int parcial = (initial - pesoActual).clamp(0.0, double.infinity).round();
        final int kgACargar = initial.round();

        // Construir cadena según la pantalla
        if (_st407Screen == St407Screen.loadingRecipe) {
          // formato: pantalla,peso_actual,parcial,kg_a_cargar,ingrediente
          return '${_st407Screen.code},${pesoActual.round()},$parcial,$kgACargar,Maiz\r\n';
        }

        if (_st407Screen == St407Screen.loadingManual) {
          // ingrediente/identificador distinto en la pantalla manual
          return '${_st407Screen.code},${pesoActual.round()},$parcial,$kgACargar,1\r\n';
        }
      }

      // Pantalla 105 - mezclando: formato pantalla,minutos,segundos
      // Debe iniciar en 105,4,30 y decrementar como reloj.
      if (_st407Screen == St407Screen.mixing) {
        if (!_st407MixingCountdownActive) {
          _st407MixingCountdownActive = true;
          _st407MixingCurrentSeconds = 4 * 60 + 30;
        }

        final int minutes = _st407MixingCurrentSeconds ~/ 60;
        final int seconds = _st407MixingCurrentSeconds % 60;
        final String seconds2 = seconds.toString().padLeft(2, '0');
        final String payload = '${_st407Screen.code},$minutes,$seconds2\r\n';

        if (_st407MixingCurrentSeconds > 0) {
          _st407MixingCurrentSeconds -= 1;
        }

        return payload;
      }

      return St407PayloadDto(
        screen: _st407Screen,
        measurement: measurement,
        now: DateTime.now(),
      ).toProtocolString();
    }

    return ScalePayloadDto(measurement: measurement).toJsonUtf8String();
  }

  ScaleMeasurement _measurementForCurrentProtocol(ScaleMeasurement measurement) {
    if (_sendProtocol == SendProtocol.manual) {
      return _manualMeasurement;
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

    // Si estamos en protocolo ST407 remoto y en una pantalla de carga, debemos
    // mostrar un peso actual que disminuye lentamente mientras 'kg a cargar'
    // permanece estático (inicial). Para ello usamos _st407CurrentDisplayedPeso.
    if (_sendProtocol == SendProtocol.st407Remote &&
        (_st407Screen == St407Screen.loadingRecipe ||
            _st407Screen == St407Screen.loadingManual)) {
      // Inicializar si es la primera vez
      if (!_st407LoadingActive || _st407InitialKgToLoad == null) {
        _st407InitialKgToLoad = base.peso.toDouble();
        _st407CurrentDisplayedPeso = _st407InitialKgToLoad ?? base.peso.toDouble();
        _st407LoadingActive = true;
      }

      // Decrementar el peso mostrado muy de a poco
      double next = _st407CurrentDisplayedPeso - _st407DecrementPerTick;
      if (next < 0.0) next = 0.0;
      _st407CurrentDisplayedPeso = next;

      // Devolver measurement con el peso modificado para UI y payload
      return base.copyWith(peso: _st407CurrentDisplayedPeso.round());
    }

    return _withScaleStateFromWeightChange(_withWeightHoldAfterSensorChange(base));
  }

  double _normalizeHumidity(double value) {
    final double clamped = value.clamp(0.0, 22.0);
    return double.parse(clamped.toStringAsFixed(1));
  }

  ScaleMeasurement _normalizeManualMeasurement(ScaleMeasurement measurement) {
    final double normalizedHumidity =
        double.parse(measurement.humedad.clamp(0.0, 22.0).toStringAsFixed(1));
    final double normalizedVbat =
        double.parse(measurement.vbat.clamp(0.0, 5.0).toStringAsFixed(1));

    return measurement.copyWith(
      tara: measurement.tara.clamp(0, 22000),
      hold: measurement.hold.clamp(0, 1),
      vbat: normalizedVbat,
      peso: measurement.peso.clamp(0, 22000),
      estBalanza: measurement.estBalanza.clamp(0, 5),
      humedad: normalizedHumidity,
      sensorInduc: measurement.sensorInduc.clamp(0, 1),
    );
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

    if (_isResetHoldCommand(normalizedCommand)) {
      final ScaleMeasurement nextManual = _normalizeManualMeasurement(
        _manualMeasurement.copyWith(
          hold: 0,
          estBalanza: 1,
        ),
      );

      if (nextManual.hold == _manualMeasurement.hold &&
          nextManual.estBalanza == _manualMeasurement.estBalanza) {
        return;
      }

      _manualMeasurement = nextManual;
      _emit(_current.copyWith(manualMeasurement: _manualMeasurement));
      _pushLog('Comando aplicado: AT+RSTHOLD -> hold=0');
      await _sendCurrentPayloadNow();
      return;
    }

    if (_isToggleTareCommand(normalizedCommand)) {
      if (_sendProtocol != SendProtocol.manual) {
        return;
      }

      final bool activateTare = _manualMeasurement.tara == 0;
      final ScaleMeasurement toggledMeasurement = activateTare
          ? _manualMeasurement.copyWith(
              tara: _manualMeasurement.peso,
              peso: 0,
            )
          : _manualMeasurement.copyWith(
              tara: 0,
              peso: (_manualMeasurement.peso + _manualMeasurement.tara)
                  .clamp(0, 22000)
                  .toInt(),
            );
      final ScaleMeasurement nextManual =
          _normalizeManualMeasurement(toggledMeasurement);

      if (nextManual.tara == _manualMeasurement.tara &&
          nextManual.peso == _manualMeasurement.peso) {
        return;
      }

      _manualMeasurement = nextManual;
      _emit(_current.copyWith(manualMeasurement: _manualMeasurement));
      _pushLog(
        activateTare
            ? 'Comando aplicado: AT+TARA -> tara activada'
            : 'Comando aplicado: AT+TARA -> tara desactivada',
      );
      await _sendCurrentPayloadNow();
      return;
    }

    if (_isZeroWeightCommand(normalizedCommand)) {
      if (_sendProtocol == SendProtocol.manual) {
        if (_manualMeasurement.tara > 0 || _manualMeasurement.peso == 0) {
          return;
        }

        _manualMeasurement = _normalizeManualMeasurement(
          _manualMeasurement.copyWith(peso: 0),
        );
        _emit(_current.copyWith(manualMeasurement: _manualMeasurement));
        _pushLog('Comando aplicado: AT+CERO -> peso=0 (manual)');
        await _sendCurrentPayloadNow();
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
