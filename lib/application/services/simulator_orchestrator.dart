import 'dart:async';

import 'package:test_jaguar/application/dto/hydraulic_payload_dto.dart';
import 'package:test_jaguar/application/dto/scale_payload_dto.dart';
import 'package:test_jaguar/application/dto/st456_payload_dto.dart';
import 'package:test_jaguar/application/dto/simulator_status_dto.dart';
import 'package:test_jaguar/core/constants/ble_constants.dart';
import 'package:test_jaguar/core/extensions/stream_subscription_extensions.dart';
import 'package:test_jaguar/domain/entities/ble_peripheral_status.dart';
import 'package:test_jaguar/domain/entities/scale_measurement.dart';
import 'package:test_jaguar/domain/repositories/ble_peripheral_repository.dart';
import 'package:test_jaguar/domain/repositories/scale_simulation_repository.dart';
import 'package:test_jaguar/domain/value_objects/hydraulic_actuator_position.dart';
import 'package:test_jaguar/domain/value_objects/hydraulic_discharge_command.dart';
import 'package:test_jaguar/domain/value_objects/hydraulic_movement_command.dart';
import 'package:test_jaguar/domain/value_objects/hydraulic_pto.dart';
import 'package:test_jaguar/domain/value_objects/send_protocol.dart';
import 'package:test_jaguar/domain/value_objects/st456_screen.dart';

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

  static const int _weightHoldTicksAfterSensorChange = 5;
  static const String _resetHoldCommand = 'AT+RSTHOLD';
  static const String _toggleTareCommand = 'AT+TARA';
  static const String _zeroWeightCommand = 'AT+CERO';
  static const String _stopDischargeCommand = 'AT+DETENER';
  static const String _resumeDischargeCommand = 'AT+REANUDAR';
  static const String _finishDischargeCommand = 'AT+FINALIZAR';

  // Eventos que el simulador NOTIFICA a la app (los de arriba son los que
  // recibe por characteristic write).
  static const String _guardarEvent = 'AT+GUARDAR';

  /// Cierre de la primera descarga del modo "dos descargas" (`modo = 2` en
  /// `AT+INICIO`): la app guarda/imprime/envía igual que con [_guardarEvent],
  /// pero se queda en descarga y manda un segundo `AT+INICIO` en modo 1.
  static const String _guardarDosEvent = 'AT+GUARDARDOS';

  SendProtocol _sendProtocol = SendProtocol.jaguarBle;
  St456Screen _st456Screen = St456Screen.main;
  double _selectedHumidity = 10.0;
  ScaleMeasurement _manualMeasurement = ScaleMeasurement.baseline;
  // Estado para simulación de "kg a cargar" y parcial en pantallas ST456
  double? _st456InitialKgToLoad;
  // Peso actual mostrado en la pantalla de carga (disminuye lentamente)
  double _st456CurrentDisplayedPeso = 0.0;
  bool _st456LoadingActive = false;
  // decremento por tick aplicado al peso actual mostrado
  final double _st456DecrementPerTick = 1.0;
  // Estado de cuenta regresiva para pantalla 65 (mezclando): inicia en 4:30
  bool _st456MixingCountdownActive = false;
  int _st456MixingCurrentSeconds = 4 * 60 + 30;
  int _lastSensorInduc = SimulatorStatusDto.initial.measurement.sensorInduc;
  int _weightHoldTicksRemaining = 0;
  int? _heldWeight;
  SimulatorStatusDto _current = SimulatorStatusDto.initial;

  // --- Estado modo Hidráulico BLE ---
  // Peso/sensor propios de este modo: no dependen del motor de simulación
  // automático (no hay ciclo de fases acá). sensorInduc queda siempre en 0
  // (carga) — la transición carga/descarga la maneja la app conectada por
  // AT+INICIO/AT+GUARDAR, no el sensor. peso solo cambia si el tester lo
  // edita a mano o por una descarga activa iniciada con AT+INICIO.
  ScaleMeasurement _hydraulicMeasurement = ScaleMeasurement.baseline;
  int _tomaFuerza = HydraulicPtoState.off;
  // RPM simuladas de la toma de fuerza: se configuran siempre, pero solo
  // salen en el JSON cuando _tomaFuerza está en encendida.
  int _tomaFuerzaRpm = HydraulicPtoRpm.defaultValue;
  String _errorEcu = '';
  // Posición de cada actuador en pasos discretos (0 cerrado .. 5 abierto):
  // cada AT+MOVIMIENTO mueve un paso hasta el tope correspondiente.
  int _tuboPosicion = HydraulicActuatorPosition.closed;
  int _guillotinaPosicion = HydraulicActuatorPosition.closed;
  HydraulicDischargeCommand? _lastHydraulicInicio;
  HydraulicMovementCommand? _lastHydraulicMovimiento;
  bool _hydraulicDischargeActive = false;
  // AT+DETENER pausa la descarga en curso (no la cancela): el peso queda
  // congelado y los parámetros de la corrida (objetivo, velocidad) se
  // conservan hasta que llegue AT+REANUDAR.
  bool _hydraulicDischargePaused = false;
  bool _hydraulicJustCompleted = false;
  // Evento de guardado prometido por el AT+INICIO que inició la corrida en
  // curso: modo 2 ("dos descargas") cierra con AT+GUARDARDOS y el resto con
  // AT+GUARDAR. Se congela al iniciar la descarga, como el objetivo y la
  // velocidad, y no se deduce de _lastHydraulicInicio al completar, porque ese
  // campo también guarda los AT+INICIO inválidos y los que lleguen mientras la
  // descarga baja.
  bool _hydraulicSaveAsDosDescargas = false;
  double _hydraulicCurrentDisplayedPeso = 0.0;
  double _hydraulicInitialPeso = 0.0;
  double _hydraulicTargetPeso = 0.0;
  double _hydraulicDecrementPerTick = 0.0;
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
    await _bleRepository.updateBleUuids(
      protocol == SendProtocol.st456Remote
          ? BleConstants.st456
          : BleConstants.jaguar,
    );
    _weightHoldTicksRemaining = 0;
    _heldWeight = null;
    _lastSensorInduc = _current.measurement.sensorInduc;

    // Limpiar estado ST456 si ya no estamos en ese protocolo
    if (_sendProtocol != SendProtocol.st456Remote) {
      _st456LoadingActive = false;
      _st456InitialKgToLoad = null;
      _st456CurrentDisplayedPeso = 0.0;
      _st456MixingCountdownActive = false;
      _st456MixingCurrentSeconds = 4 * 60 + 30;
    }

    // Limpiar estado de ejecución hidráulico si ya no estamos en ese
    // protocolo (tomaFuerza/errorEcu se conservan, son configuración, no
    // estado de una corrida en curso).
    if (_sendProtocol != SendProtocol.hidraulicoBle) {
      _hydraulicDischargeActive = false;
      _hydraulicDischargePaused = false;
      _hydraulicSaveAsDosDescargas = false;
      _hydraulicCurrentDisplayedPeso = 0.0;
      _hydraulicInitialPeso = 0.0;
      _hydraulicTargetPeso = 0.0;
      _hydraulicDecrementPerTick = 0.0;
      _tuboPosicion = HydraulicActuatorPosition.closed;
      _guillotinaPosicion = HydraulicActuatorPosition.closed;
    }

    _emit(_withHydraulicSnapshot(_current.copyWith(sendProtocol: _sendProtocol)));
    _pushLog('Protocolo seleccionado: ${protocol.label}');
    await _sendCurrentPayloadNow();
  }

  Future<void> setHydraulicPeso(int value) async {
    if (_hydraulicDischargeActive) {
      return; // no se edita a mano mientras hay una descarga en curso
    }
    final int next = value.clamp(0, 22000);
    if (_hydraulicMeasurement.peso == next) {
      return;
    }
    _hydraulicMeasurement = _hydraulicMeasurement.copyWith(peso: next);
    _pushLog('Peso hidráulico configurado: $next kg');
    await _sendCurrentPayloadNow();
  }

  Future<void> setTomaFuerza(int value) async {
    final int next = value.clamp(
      HydraulicPtoState.off,
      HydraulicPtoState.requestOff,
    );
    if (_tomaFuerza == next) {
      return;
    }
    _tomaFuerza = next;
    final int rpmEnviadas =
        HydraulicPtoState.isOn(_tomaFuerza) ? _tomaFuerzaRpm : 0;
    _pushLog(
      'Toma de fuerza configurada: $_tomaFuerza '
      '(rpm enviadas: $rpmEnviadas)',
    );
    await _sendCurrentPayloadNow();
  }

  /// RPM simuladas de la toma de fuerza. Se pueden configurar en cualquier
  /// estado, pero el JSON solo las manda con la toma de fuerza encendida.
  Future<void> setTomaFuerzaRpm(int value) async {
    final int next = HydraulicPtoRpm.clamp(value);
    if (_tomaFuerzaRpm == next) {
      return;
    }
    _tomaFuerzaRpm = next;
    _pushLog(
      HydraulicPtoState.isOn(_tomaFuerza)
          ? 'RPM toma de fuerza configuradas: $_tomaFuerzaRpm'
          : 'RPM toma de fuerza configuradas: $_tomaFuerzaRpm '
              '(se envía rpm: 0 hasta que tomaFuerza sea '
              '${HydraulicPtoState.on})',
    );
    await _sendCurrentPayloadNow();
  }

  Future<void> setErrorEcu(String value) async {
    if (_errorEcu == value) {
      return;
    }
    _errorEcu = value;
    _pushLog('errorEcu configurado: "$_errorEcu"');
    await _sendCurrentPayloadNow();
  }

  /// Envía el evento `AT+GUARDAR` crudo por notify BLE. Lo usa el botón manual
  /// de la UI, que siempre manda el cierre clásico; el disparo automático al
  /// completar una descarga pasa por [_sendSaveEvent], que manda
  /// `AT+GUARDARDOS` cuando la corrida se inició con modo 2.
  Future<void> sendGuardarEvent() => _sendSaveEvent(_guardarEvent);

  /// Notifica uno de los eventos de guardado crudos ([_guardarEvent] o
  /// [_guardarDosEvent]). Centralizado para que el terminador `\r\n` no se
  /// pueda desincronizar entre los dos.
  Future<void> _sendSaveEvent(String event) async {
    try {
      await _bleRepository.notifyUtf8Json('$event\r\n');
    } catch (error) {
      _pushLog('Error enviando $event: $error');
      return;
    }
    _pushLog('$event enviado');
  }

  Future<void> setSt456Screen(St456Screen screen) async {
    if (_st456Screen == screen) {
      return;
    }

    _st456Screen = screen;
    _emit(_current.copyWith(st456Screen: _st456Screen));
    _pushLog('Pantalla ST456 seleccionada: ${screen.label}');

    if (_sendProtocol == SendProtocol.st456Remote) {
      // Inicializar estado de carga cuando se seleccionan pantallas de carga
      if (screen == St456Screen.loadingRecipe || screen == St456Screen.loadingManual) {
        _st456InitialKgToLoad = _current.measurement.peso.toDouble();
        // peso mostrado parte del peso actual y luego irá bajando
        _st456CurrentDisplayedPeso = _st456InitialKgToLoad ?? 0.0;
        _st456LoadingActive = true;
        _st456MixingCountdownActive = false;
        _st456MixingCurrentSeconds = 4 * 60 + 30;
      } else if (screen == St456Screen.mixing) {
        _st456LoadingActive = false;
        _st456InitialKgToLoad = null;
        _st456CurrentDisplayedPeso = 0.0;
        _st456MixingCountdownActive = true;
        _st456MixingCurrentSeconds = 4 * 60 + 30;
      } else {
        _st456LoadingActive = false;
        _st456InitialKgToLoad = null;
        _st456CurrentDisplayedPeso = 0.0;
        _st456MixingCountdownActive = false;
        _st456MixingCurrentSeconds = 4 * 60 + 30;
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

        if (_hydraulicJustCompleted) {
          _hydraulicJustCompleted = false;
          // Copia local antes del await: el listener de watchStatus() puede
          // intercalarse acá y procesar un AT+INICIO nuevo, que pisaría el
          // evento prometido por la corrida que se está cerrando.
          final bool dosDescargas = _hydraulicSaveAsDosDescargas;
          _hydraulicSaveAsDosDescargas = false;
          final String saveEvent =
              dosDescargas ? _guardarDosEvent : _guardarEvent;
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

  /// Medición vigente del modo Hidráulico BLE. Mientras una descarga corre el
  /// peso vive en [_hydraulicCurrentDisplayedPeso] y no en
  /// [_hydraulicMeasurement], que sólo se fija al pausar, finalizar o
  /// completar la corrida.
  ScaleMeasurement get _currentHydraulicMeasurement {
    final ScaleMeasurement base =
        _hydraulicMeasurement.copyWith(humedad: _selectedHumidity);
    return _hydraulicDischargeActive
        ? base.copyWith(peso: _hydraulicCurrentDisplayedPeso.round())
        : base;
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
      measurement = _currentHydraulicMeasurement;
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
          st456Screen: _st456Screen,
          manualMeasurement: _manualMeasurement,
          weightHoldSecondsRemaining: weightHoldSecondsRemaining,
          lastJson: payload,
        ),
      ),
    );
  }

  SimulatorStatusDto _withHydraulicSnapshot(SimulatorStatusDto value) {
    return value.copyWith(
      tomaFuerza: _tomaFuerza,
      tomaFuerzaRpm: _tomaFuerzaRpm,
      errorEcu: _errorEcu,
      tuboPosicion: _tuboPosicion,
      guillotinaPosicion: _guillotinaPosicion,
      hydraulicDischargeActive: _hydraulicDischargeActive,
      hydraulicDischargePaused: _hydraulicDischargePaused,
      hydraulicInitialPeso: _hydraulicInitialPeso,
      hydraulicTargetPeso: _hydraulicTargetPeso,
      lastHydraulicInicio: _lastHydraulicInicio,
      lastHydraulicMovimiento: _lastHydraulicMovimiento,
    );
  }

  String _payloadForCurrentProtocol(ScaleMeasurement measurement) {
    if (_sendProtocol == SendProtocol.hidraulicoBle) {
      return HydraulicPayloadDto(
        measurement: measurement,
        tomaFuerza: _tomaFuerza,
        tomaFuerzaRpm: _tomaFuerzaRpm,
        errorEcu: _errorEcu,
      ).toJsonUtf8String();
    }

    if (_sendProtocol == SendProtocol.st456Remote) {
      // Para pantallas de carga (loadingRecipe, loadingManual) necesitamos
      // mantener un 'kg a cargar' que parte del valor inicial de peso actual
      // y va disminuyendo muy de a poco; el campo 'parcial' debe reflejar
      // lo que ya se fue descargando (initial - current).
      if (_st456Screen == St456Screen.loadingRecipe ||
          _st456Screen == St456Screen.loadingManual) {
        // Asegurar inicialización del valor estático "kg a cargar"
        if (!_st456LoadingActive || _st456InitialKgToLoad == null) {
          _st456InitialKgToLoad = measurement.peso.toDouble();
          _st456CurrentDisplayedPeso = _st456InitialKgToLoad ?? 0.0;
          _st456LoadingActive = true;
        }

        // 'kg a cargar' debe mantener el valor inicial (estático)
        final double initial = _st456InitialKgToLoad ?? measurement.peso.toDouble();
        // 'peso actual' se toma del measurement que llega (debe bajar)
        final double pesoActual = measurement.peso.toDouble();
        // 'parcial' es lo que ya se descargó: initial - pesoActual (no negativo)
        final int parcial = (initial - pesoActual).clamp(0.0, double.infinity).round();
        final int kgACargar = initial.round();

        // Construir cadena según la pantalla
        if (_st456Screen == St456Screen.loadingRecipe) {
          // formato: pantalla,peso_actual,parcial,kg_a_cargar,ingrediente
          return '${_st456Screen.code},${pesoActual.round()},$parcial,$kgACargar,Maiz\r\n';
        }

        if (_st456Screen == St456Screen.loadingManual) {
          // ingrediente/identificador distinto en la pantalla manual
          return '${_st456Screen.code},${pesoActual.round()},$parcial,$kgACargar,1\r\n';
        }
      }

      // Pantalla 65 - mezclando: formato pantalla,minutos,segundos
      // Debe iniciar en 65,4,30 y decrementar como reloj.
      if (_st456Screen == St456Screen.mixing) {
        if (!_st456MixingCountdownActive) {
          _st456MixingCountdownActive = true;
          _st456MixingCurrentSeconds = 4 * 60 + 30;
        }

        final int minutes = _st456MixingCurrentSeconds ~/ 60;
        final int seconds = _st456MixingCurrentSeconds % 60;
        final String seconds2 = seconds.toString().padLeft(2, '0');
        final String payload = '${_st456Screen.code},$minutes,$seconds2\r\n';

        if (_st456MixingCurrentSeconds > 0) {
          _st456MixingCurrentSeconds -= 1;
        }

        return payload;
      }

      return St456PayloadDto(
        screen: _st456Screen,
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
      // hasta que llegue AT+REANUDAR.
      if (_hydraulicDischargeActive && !_hydraulicDischargePaused) {
        final double next =
            _hydraulicCurrentDisplayedPeso - _hydraulicDecrementPerTick;
        if (next <= _hydraulicTargetPeso) {
          _hydraulicCurrentDisplayedPeso = _hydraulicTargetPeso;
          _hydraulicDischargeActive = false;
          _hydraulicJustCompleted = true;
          _hydraulicMeasurement = _hydraulicMeasurement.copyWith(
            peso: _hydraulicCurrentDisplayedPeso.round(),
          );
        } else {
          _hydraulicCurrentDisplayedPeso = next;
        }
      }
      return _currentHydraulicMeasurement;
    }

    ScaleMeasurement base = measurement.copyWith(humedad: _selectedHumidity);

    // Si estamos en protocolo ST456 remoto y en una pantalla de carga, debemos
    // mostrar un peso actual que disminuye lentamente mientras 'kg a cargar'
    // permanece estático (inicial). Para ello usamos _st456CurrentDisplayedPeso.
    if (_sendProtocol == SendProtocol.st456Remote &&
        (_st456Screen == St456Screen.loadingRecipe ||
            _st456Screen == St456Screen.loadingManual)) {
      // Inicializar si es la primera vez
      if (!_st456LoadingActive || _st456InitialKgToLoad == null) {
        _st456InitialKgToLoad = base.peso.toDouble();
        _st456CurrentDisplayedPeso = _st456InitialKgToLoad ?? base.peso.toDouble();
        _st456LoadingActive = true;
      }

      // Decrementar el peso mostrado muy de a poco
      double next = _st456CurrentDisplayedPeso - _st456DecrementPerTick;
      if (next < 0.0) next = 0.0;
      _st456CurrentDisplayedPeso = next;

      // Devolver measurement con el peso modificado para UI y payload
      return base.copyWith(peso: _st456CurrentDisplayedPeso.round());
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
        await _applyHydraulicDetener();
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
        await _applyHydraulicReanudar();
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
        await _applyHydraulicFinalizar();
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
        await _applyHydraulicInicio(inicio);
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
        await _applyHydraulicMovimiento(movimiento);
      } else {
        _pushLog(
          'AT+MOVIMIENTO recibido pero se ignora: seleccioná "Hidráulico BLE" '
          'para procesarlo (${movimiento.label}).',
        );
      }
      return;
    }
  }

  Future<void> _applyHydraulicInicio(HydraulicDischargeCommand command) async {
    _lastHydraulicInicio = command;

    final int currentPeso = _currentHydraulicMeasurement.peso;
    final bool validRange = command.hasValidRange;
    // Igual al peso de la tolva es válido: así es como el firmware recibe una
    // descarga total (se le manda todo el contenido y la vacía). Lo único que
    // no se puede pedir es descargar más de lo que hay.
    final bool validAgainstCurrent = command.kgDescarga <= currentPeso;

    if (!validRange || !validAgainstCurrent) {
      _pushLog(
        'AT+INICIO recibido con parámetros inválidos (${command.summary}): '
        'se requiere kgDescarga > kgTubo y kgDescarga <= peso actual '
        '($currentPeso kg). No se inicia la descarga simulada.',
      );
      await _sendCurrentPayloadNow();
      return;
    }

    _hydraulicCurrentDisplayedPeso = currentPeso.toDouble();
    _hydraulicInitialPeso = currentPeso.toDouble();
    _hydraulicTargetPeso = (currentPeso - command.kgDescarga).toDouble();
    _hydraulicDecrementPerTick = _hydraulicRateForVelocidad(command.velocidad);
    _hydraulicDischargeActive = true;
    _hydraulicDischargePaused = false;
    _hydraulicSaveAsDosDescargas = command.isDosDescargas;

    // Al descargar el tubo queda totalmente abierto y la guillotina en alguna
    // posición que no sea "cerrada": si venía cerrada se la lleva al primer
    // paso de apertura, si ya estaba abierta se respeta donde la dejaron.
    _tuboPosicion = HydraulicActuatorPosition.open;
    if (HydraulicActuatorPosition.isClosed(_guillotinaPosicion)) {
      _guillotinaPosicion = HydraulicActuatorPosition.firstOpenStep;
    }

    _pushLog(
      'AT+INICIO recibido: ${command.summary} -> tubo '
      '${HydraulicActuatorPosition.label(_tuboPosicion)}, guillotina '
      '${HydraulicActuatorPosition.label(_guillotinaPosicion)}, cierra con '
      '${_hydraulicSaveAsDosDescargas ? _guardarDosEvent : _guardarEvent}',
    );
    await _sendCurrentPayloadNow();
  }

  /// `AT+DETENER` **pausa** la descarga simulada en curso: el peso queda
  /// congelado donde estaba, la corrida sigue viva (objetivo, velocidad y
  /// posiciones de los actuadores se conservan) y **no** se envía
  /// `AT+GUARDAR`, porque todavía no se alcanzó el objetivo. La descarga
  /// retoma desde ese mismo peso al recibir `AT+REANUDAR`.
  Future<void> _applyHydraulicDetener() async {
    if (!_hydraulicDischargeActive) {
      _pushLog('AT+DETENER recibido: no hay descarga en curso');
      await _sendCurrentPayloadNow();
      return;
    }

    if (_hydraulicDischargePaused) {
      _pushLog('AT+DETENER recibido: la descarga ya estaba pausada');
      await _sendCurrentPayloadNow();
      return;
    }

    _hydraulicDischargePaused = true;
    // Mientras la descarga corre el peso vive en
    // _hydraulicCurrentDisplayedPeso: hay que fijarlo en la medición del modo
    // o el próximo tick volvería al peso previo al AT+INICIO.
    _hydraulicMeasurement = _hydraulicMeasurement.copyWith(
      peso: _hydraulicCurrentDisplayedPeso.round(),
    );

    _pushLog(
      'AT+DETENER recibido: descarga pausada en '
      '${_hydraulicMeasurement.peso} kg (objetivo '
      '${_hydraulicTargetPeso.round()} kg), esperando AT+REANUDAR',
    );
    await _sendCurrentPayloadNow();
  }

  /// `AT+REANUDAR` continúa la descarga que `AT+DETENER` dejó pausada: sigue
  /// desde el peso en el que había quedado, con el mismo objetivo y la misma
  /// velocidad del `AT+INICIO` original, y al llegar al objetivo dispara
  /// `AT+GUARDAR` como cualquier descarga completa.
  Future<void> _applyHydraulicReanudar() async {
    if (!_hydraulicDischargeActive) {
      _pushLog('AT+REANUDAR recibido: no hay descarga pausada');
      await _sendCurrentPayloadNow();
      return;
    }

    if (!_hydraulicDischargePaused) {
      _pushLog('AT+REANUDAR recibido: la descarga ya venía en curso');
      await _sendCurrentPayloadNow();
      return;
    }

    _hydraulicDischargePaused = false;
    _pushLog(
      'AT+REANUDAR recibido: descarga retomada desde '
      '${_hydraulicCurrentDisplayedPeso.round()} kg (objetivo '
      '${_hydraulicTargetPeso.round()} kg)',
    );
    await _sendCurrentPayloadNow();
  }

  /// `AT+FINALIZAR` termina la descarga automática sin haber llegado al
  /// objetivo: el peso queda donde estaba en ese momento y la corrida se
  /// descarta (no queda nada para reanudar). Sirve tanto con la descarga
  /// corriendo como pausada por `AT+DETENER`. No se envía `AT+GUARDAR`,
  /// porque el guardado lo decide la app que finalizó. Los actuadores
  /// quedan en la posición en la que estaban y vuelven a responder a
  /// `AT+MOVIMIENTO`.
  Future<void> _applyHydraulicFinalizar() async {
    if (!_hydraulicDischargeActive) {
      _pushLog('AT+FINALIZAR recibido: no hay descarga en curso');
      await _sendCurrentPayloadNow();
      return;
    }

    final bool estabaPausada = _hydraulicDischargePaused;
    _hydraulicDischargeActive = false;
    _hydraulicDischargePaused = false;
    _hydraulicJustCompleted = false;
    // La corrida se descarta entera: su evento de guardado no puede quedar
    // pegado para el próximo AT+INICIO.
    _hydraulicSaveAsDosDescargas = false;
    // Mientras la descarga corre el peso vive en
    // _hydraulicCurrentDisplayedPeso: hay que fijarlo en la medición del
    // modo o el próximo tick volvería al peso previo al AT+INICIO.
    _hydraulicMeasurement = _hydraulicMeasurement.copyWith(
      peso: _hydraulicCurrentDisplayedPeso.round(),
    );

    _pushLog(
      'AT+FINALIZAR recibido: descarga automática terminada en '
      '${_hydraulicMeasurement.peso} kg (objetivo '
      '${_hydraulicTargetPeso.round()} kg'
      '${estabaPausada ? ', estaba pausada' : ''}), '
      'no se envía AT+GUARDAR',
    );
    await _sendCurrentPayloadNow();
  }

  Future<void> _applyHydraulicMovimiento(
    HydraulicMovementCommand command,
  ) async {
    _lastHydraulicMovimiento = command;

    // Durante una descarga las posiciones las maneja la descarga misma: los
    // abrir/cerrar de tubo y guillotina se ignoran hasta que termine. Una
    // descarga pausada por AT+DETENER sigue siendo una descarga en curso.
    if (_hydraulicDischargeActive) {
      _pushLog(
        'AT+MOVIMIENTO recibido: ${command.label} (tipo=${command.tipo}) -> '
        'ignorado, hay una descarga en curso'
        '${_hydraulicDischargePaused ? ' (pausada)' : ''}',
      );
      await _sendCurrentPayloadNow();
      return;
    }

    final bool? opens = command.opens;
    if (opens != null && command.affectsTube) {
      _tuboPosicion = HydraulicActuatorPosition.stepped(
        _tuboPosicion,
        opening: opens,
      );
      _pushLog(
        'AT+MOVIMIENTO recibido: ${command.label} (tipo=${command.tipo}) -> '
        'tubo en ${HydraulicActuatorPosition.label(_tuboPosicion)}',
      );
    } else if (opens != null && command.affectsGuillotine) {
      _guillotinaPosicion = HydraulicActuatorPosition.stepped(
        _guillotinaPosicion,
        opening: opens,
      );
      _pushLog(
        'AT+MOVIMIENTO recibido: ${command.label} (tipo=${command.tipo}) -> '
        'guillotina en ${HydraulicActuatorPosition.label(_guillotinaPosicion)}',
      );
    } else {
      _pushLog(
        'AT+MOVIMIENTO recibido: ${command.label} (tipo=${command.tipo})',
      );
    }

    await _sendCurrentPayloadNow();
  }

  double _hydraulicRateForVelocidad(int velocidad) {
    switch (velocidad) {
      case 1:
        return 20.0; // lenta
      case 2:
        return 50.0; // normal
      case 3:
        return 120.0; // rápida
      case 4:
        return 70.0; // variable (valor intermedio fijo, sin jitter)
      default:
        return 50.0;
    }
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
