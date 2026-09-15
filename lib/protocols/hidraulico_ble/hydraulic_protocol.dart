import 'dart:math';

import 'package:test_jaguar/core/constants/ble_constants.dart';
import 'package:test_jaguar/core/constants/payload_framing.dart';
import 'package:test_jaguar/domain/entities/scale_measurement.dart';
import 'package:test_jaguar/domain/value_objects/send_protocol.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_actuators.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_discharge_command.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_movement_command.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_payload.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_pto.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_state.dart';
import 'package:test_jaguar/protocols/simulator_protocol.dart';

/// Eventos que el simulador **notifica** a la app al cerrar una descarga.
abstract final class HydraulicSaveEvent {
  static const String guardar = 'AT+GUARDAR';

  /// Cierre de la primera descarga del modo "dos descargas" (`modo = 2` en
  /// `AT+INICIO`): la app guarda/imprime/envía igual que con [guardar], pero se
  /// queda en descarga y manda un segundo `AT+INICIO` en modo 1.
  static const String guardarDos = 'AT+GUARDARDOS';
}

/// Lo que dejó pendiente un paso del reloj de actuadores.
class HydraulicActuatorTick {
  const HydraulicActuatorTick({required this.logs, this.saveEvent});

  static const HydraulicActuatorTick none =
      HydraulicActuatorTick(logs: <String>[]);

  final List<String> logs;

  /// Evento de guardado a notificar, si en este paso terminó la descarga.
  final String? saveEvent;
}

/// Protocolo Hidráulico BLE: la caja de manejo del tubo y la guillotina.
///
/// Comparte el perfil GATT de Jaguar, pero agrega al JSON los campos de la caja
/// (`tomaFuerza`, `rpm`, `errorEcu`, `tubo`, `gillo`) y es el único que procesa
/// la familia de comandos de descarga (`AT+INICIO`, `AT+DETENER`,
/// `AT+REANUDAR`, `AT+FINALIZAR`, `AT+MOVIMIENTO`).
///
/// **Tiene dos relojes, y no es casual.** El peso baja con el tick del motor de
/// simulación, igual que en los demás protocolos. Los actuadores corren con su
/// propio reloj de 1 s ([advanceActuators]), que sigue andando con la
/// simulación detenida: en el equipo real el hidráulico no depende de que la
/// balanza esté pesando.
///
/// **No usa el ciclo de fases del motor**: el peso queda fijo salvo que el
/// tester lo edite a mano o haya una descarga bajando, y `sensorInduc` nunca
/// cambia — la transición carga/descarga la maneja la app por comando.
///
/// Los métodos que procesan comandos devuelven la línea de log a publicar en
/// vez de escribirla: así el módulo no necesita conocer al orquestador y se
/// puede probar solo.
class HydraulicProtocol implements SimulatorProtocol {
  HydraulicProtocol({Random? random})
      : _guillotina = HydraulicGuillotine(random: random);

  @override
  SendProtocol get id => SendProtocol.hidraulicoBle;

  @override
  BleUuids get bleUuids => BleConstants.jaguar;

  @override
  PayloadFraming get framing => PayloadFraming.plain;

  // --- Configuración: sobrevive a un cambio de protocolo ---
  int _tomaFuerza = HydraulicPtoState.off;

  /// RPM simuladas de la toma de fuerza: se configuran siempre, pero sólo
  /// salen en el JSON cuando [_tomaFuerza] está en encendida.
  int _tomaFuerzaRpm = HydraulicPtoRpm.defaultValue;
  String _errorEcu = '';

  // --- Estado de la corrida: se descarta al salir del modo ---
  ScaleMeasurement _measurement = ScaleMeasurement.baseline;

  final HydraulicTube _tubo = HydraulicTube();
  final HydraulicGuillotine _guillotina;

  HydraulicRunPhase _phase = HydraulicRunPhase.idle;
  HydraulicDischargeCommand? _lastInicio;
  HydraulicMovementCommand? _lastMovimiento;

  /// `AT+DETENER` pausa la descarga en curso (no la cancela): el peso queda
  /// congelado y los parámetros de la corrida (objetivo, velocidad) se
  /// conservan hasta que llegue `AT+REANUDAR`.
  bool _dischargePaused = false;
  bool _justCompleted = false;

  /// Evento de guardado prometido por el `AT+INICIO` que inició la corrida en
  /// curso. Se congela al iniciar, como el objetivo y la velocidad, y no se
  /// deduce de [_lastInicio] al completar, porque ese campo también guarda los
  /// `AT+INICIO` inválidos y los que lleguen mientras la descarga baja.
  bool _saveAsDosDescargas = false;
  double _currentDisplayedPeso = 0.0;
  double _initialPeso = 0.0;
  double _targetPeso = 0.0;
  double _decrementPerTick = 0.0;

  HydraulicState get state => HydraulicState(
        tomaFuerza: _tomaFuerza,
        tomaFuerzaRpm: _tomaFuerzaRpm,
        errorEcu: _errorEcu,
        tubo: _tubo.state,
        tuboProgress: _tubo.progress,
        gillo: _guillotina.percent,
        phase: _phase,
        dischargePaused: _dischargePaused,
        initialPeso: _initialPeso,
        targetPeso: _targetPeso,
        lastInicio: _lastInicio,
        lastMovimiento: _lastMovimiento,
      );

  /// Hay algo que animar: el reloj de actuadores tiene que seguir corriendo.
  bool get needsActuatorClock =>
      _phase != HydraulicRunPhase.idle ||
      _tubo.isMoving ||
      _guillotina.isMoving;

  /// Descarta la corrida en curso al salir del modo. La configuración
  /// (`tomaFuerza`, `errorEcu`, rpm) se conserva a propósito: no es estado de
  /// una descarga, es cómo dejó configurada la caja el tester.
  void resetRunState() {
    _phase = HydraulicRunPhase.idle;
    _dischargePaused = false;
    _justCompleted = false;
    _saveAsDosDescargas = false;
    _currentDisplayedPeso = 0.0;
    _initialPeso = 0.0;
    _targetPeso = 0.0;
    _decrementPerTick = 0.0;
    _tubo.reset();
    _guillotina.reset();
  }

  /// Medición vigente. Mientras la descarga baja el peso vive en
  /// [_currentDisplayedPeso] y no en [_measurement], que sólo se fija al
  /// pausar, finalizar o completar la corrida.
  ScaleMeasurement measurement({required double humidity}) {
    final ScaleMeasurement base = _measurement.copyWith(humedad: humidity);
    return _phase == HydraulicRunPhase.descargando
        ? base.copyWith(peso: _currentDisplayedPeso.round())
        : base;
  }

  /// Peso vigente en la tolva: el de la descarga si hay una bajando.
  int get _currentPeso => _phase == HydraulicRunPhase.descargando
      ? _currentDisplayedPeso.round()
      : _measurement.peso;

  /// Un tick del motor de simulación. Es lo único que hace bajar el peso; con
  /// la simulación detenida no hay ticks y la descarga queda esperando.
  ScaleMeasurement advance({required double humidity}) {
    // Sólo una descarga bajando y no pausada por AT+DETENER mueve el peso en
    // este tick: pausada, queda donde estaba y la corrida sigue viva hasta que
    // llegue AT+REANUDAR.
    if (_phase == HydraulicRunPhase.descargando && !_dischargePaused) {
      final double next = _currentDisplayedPeso - _decrementPerTick;
      if (next <= _targetPeso) {
        _currentDisplayedPeso = _targetPeso;
        _justCompleted = true;
        _measurement =
            _measurement.copyWith(peso: _currentDisplayedPeso.round());
      } else {
        _currentDisplayedPeso = next;
      }
    }
    return measurement(humidity: humidity);
  }

  /// Un paso del reloj de actuadores, que corre aunque la simulación esté
  /// detenida. Mueve el tubo y la guillotina y hace avanzar el ciclo de la
  /// corrida.
  HydraulicActuatorTick advanceActuators(Duration elapsed) {
    final List<String> logs = <String>[];
    String? saveEvent;

    _tubo.advance(elapsed);
    _guillotina.advance(elapsed);

    switch (_phase) {
      case HydraulicRunPhase.abriendoTubo:
        // Se pregunta por el estado y no por "llegó en este paso": si el tubo
        // ya venía abierto de un AT+MOVIMIENTO, no hay recorrido que esperar y
        // la descarga arranca en el primer paso.
        if (!_tubo.isMoving && _tubo.isOpen) {
          _phase = HydraulicRunPhase.descargando;
          logs.add(
            'Tubo abierto: arranca la descarga hasta ${_targetPeso.round()} kg',
          );
        }

      case HydraulicRunPhase.descargando:
        if (!_dischargePaused) {
          final int? nuevoGillo = _guillotina.shuffleDuringDischarge(elapsed);
          if (nuevoGillo != null) {
            logs.add('Guillotina regulando: $nuevoGillo%');
          }
        }
        if (_justCompleted) {
          _justCompleted = false;
          saveEvent = _saveAsDosDescargas
              ? HydraulicSaveEvent.guardarDos
              : HydraulicSaveEvent.guardar;
          _saveAsDosDescargas = false;
          _phase = HydraulicRunPhase.cerrandoTubo;
          _tubo.closeAfterDischarge();
          _guillotina.close();
          logs.add(
            'Descarga completada (peso objetivo alcanzado): enviando '
            '$saveEvent y cerrando tubo y guillotina',
          );
        }

      case HydraulicRunPhase.cerrandoTubo:
        if (!_tubo.isMoving) {
          _phase = HydraulicRunPhase.idle;
          logs.add('Tubo cerrado: corrida terminada');
        }

      case HydraulicRunPhase.idle:
        break;
    }

    return HydraulicActuatorTick(logs: logs, saveEvent: saveEvent);
  }

  @override
  String encodePayload(ScaleMeasurement measurement) {
    return HydraulicPayloadDto(
      measurement: measurement,
      tomaFuerza: _tomaFuerza,
      tomaFuerzaRpm: _tomaFuerzaRpm,
      errorEcu: _errorEcu,
      tubo: _tubo.state,
      gillo: _guillotina.percent,
    ).toJsonUtf8String();
  }

  // --- Configuración desde la UI ---
  // Devuelven la línea de log, o null si no hubo cambio que publicar.

  String? setPeso(int value) {
    if (_phase == HydraulicRunPhase.descargando) {
      return null; // no se edita a mano mientras la descarga baja
    }
    final int next = value.clamp(0, 22000);
    if (_measurement.peso == next) {
      return null;
    }
    _measurement = _measurement.copyWith(peso: next);
    return 'Peso hidráulico configurado: $next kg';
  }

  String? setTomaFuerza(int value) {
    final int next =
        value.clamp(HydraulicPtoState.off, HydraulicPtoState.requestOff);
    if (_tomaFuerza == next) {
      return null;
    }
    _tomaFuerza = next;
    final int rpmEnviadas =
        HydraulicPtoState.isOn(_tomaFuerza) ? _tomaFuerzaRpm : 0;
    return 'Toma de fuerza configurada: $_tomaFuerza '
        '(rpm enviadas: $rpmEnviadas)';
  }

  /// RPM simuladas de la toma de fuerza. Se pueden configurar en cualquier
  /// estado, pero el JSON sólo las manda con la toma de fuerza encendida.
  String? setTomaFuerzaRpm(int value) {
    final int next = HydraulicPtoRpm.clamp(value);
    if (_tomaFuerzaRpm == next) {
      return null;
    }
    _tomaFuerzaRpm = next;
    return HydraulicPtoState.isOn(_tomaFuerza)
        ? 'RPM toma de fuerza configuradas: $_tomaFuerzaRpm'
        : 'RPM toma de fuerza configuradas: $_tomaFuerzaRpm '
            '(se envía rpm: 0 hasta que tomaFuerza sea ${HydraulicPtoState.on})';
  }

  String? setErrorEcu(String value) {
    if (_errorEcu == value) {
      return null;
    }
    _errorEcu = value;
    return 'errorEcu configurado: "$_errorEcu"';
  }

  // --- Comandos recibidos por characteristic write ---
  // Devuelven siempre la línea de log: todos publican algo y fuerzan un envío.

  String applyInicio(HydraulicDischargeCommand command) {
    _lastInicio = command;

    final int currentPeso = _currentPeso;
    final bool validRange = command.hasValidRange;
    // Igual al peso de la tolva es válido: así es como el firmware recibe una
    // descarga total (se le manda todo el contenido y la vacía). Lo único que
    // no se puede pedir es descargar más de lo que hay.
    final bool validAgainstCurrent = command.kgDescarga <= currentPeso;

    if (!validRange || !validAgainstCurrent) {
      return 'AT+INICIO recibido con parámetros inválidos (${command.summary}): '
          'se requiere kgDescarga > kgTubo y kgDescarga <= peso actual '
          '($currentPeso kg). No se inicia la descarga simulada.';
    }

    _currentDisplayedPeso = currentPeso.toDouble();
    _initialPeso = currentPeso.toDouble();
    _targetPeso = (currentPeso - command.kgDescarga).toDouble();
    _decrementPerTick = _rateForVelocidad(command.velocidad);
    _dischargePaused = false;
    _justCompleted = false;
    _saveAsDosDescargas = command.isDosDescargas;

    // La descarga no arranca acá: primero hay que abrir el tubo. Recién cuando
    // termina de abrir el peso empieza a bajar.
    _phase = HydraulicRunPhase.abriendoTubo;
    _tubo.openForDischarge();
    _guillotina.openForDischarge();

    return 'AT+INICIO recibido: ${command.summary} -> abriendo tubo '
        '(${HydraulicTube.dischargeTravel.inSeconds}s) y guillotina a '
        '${HydraulicGuillotine.dischargeOpenPercent}%, cierra con '
        '${_saveAsDosDescargas ? HydraulicSaveEvent.guardarDos : HydraulicSaveEvent.guardar}';
  }

  /// `AT+DETENER` **pausa** la descarga simulada en curso: el peso queda
  /// congelado donde estaba, la corrida sigue viva (objetivo, velocidad y
  /// posiciones de los actuadores se conservan) y **no** se envía `AT+GUARDAR`,
  /// porque todavía no se alcanzó el objetivo. La descarga retoma desde ese
  /// mismo peso al recibir `AT+REANUDAR`.
  String applyDetener() {
    if (_phase != HydraulicRunPhase.descargando) {
      return 'AT+DETENER recibido: no hay descarga en curso';
    }
    if (_dischargePaused) {
      return 'AT+DETENER recibido: la descarga ya estaba pausada';
    }

    _dischargePaused = true;
    // Mientras la descarga baja el peso vive en _currentDisplayedPeso: hay que
    // fijarlo en la medición del modo o el próximo tick volvería al peso previo
    // al AT+INICIO.
    _measurement = _measurement.copyWith(peso: _currentDisplayedPeso.round());

    return 'AT+DETENER recibido: descarga pausada en ${_measurement.peso} kg '
        '(objetivo ${_targetPeso.round()} kg), esperando AT+REANUDAR';
  }

  /// `AT+REANUDAR` continúa la descarga que `AT+DETENER` dejó pausada: sigue
  /// desde el peso en el que había quedado, con el mismo objetivo y la misma
  /// velocidad del `AT+INICIO` original, y al llegar al objetivo dispara
  /// `AT+GUARDAR` como cualquier descarga completa.
  String applyReanudar() {
    if (_phase != HydraulicRunPhase.descargando) {
      return 'AT+REANUDAR recibido: no hay descarga pausada';
    }
    if (!_dischargePaused) {
      return 'AT+REANUDAR recibido: la descarga ya venía en curso';
    }

    _dischargePaused = false;
    return 'AT+REANUDAR recibido: descarga retomada desde '
        '${_currentDisplayedPeso.round()} kg (objetivo '
        '${_targetPeso.round()} kg)';
  }

  /// `AT+FINALIZAR` termina la descarga automática sin haber llegado al
  /// objetivo: el peso queda donde estaba y la corrida se descarta. No se envía
  /// `AT+GUARDAR`, porque el guardado lo decide la app que finalizó.
  ///
  /// **El tubo queda como está** —si venía abriéndose, termina de abrir— pero
  /// la guillotina sí se cierra: es la que corta el caudal.
  String applyFinalizar() {
    if (_phase == HydraulicRunPhase.idle ||
        _phase == HydraulicRunPhase.cerrandoTubo) {
      return 'AT+FINALIZAR recibido: no hay descarga en curso';
    }

    final bool estabaPausada = _dischargePaused;
    _phase = HydraulicRunPhase.idle;
    _dischargePaused = false;
    _justCompleted = false;
    // La corrida se descarta entera: su evento de guardado no puede quedar
    // pegado para el próximo AT+INICIO.
    _saveAsDosDescargas = false;
    // Mientras la descarga baja el peso vive en _currentDisplayedPeso: hay que
    // fijarlo en la medición del modo o el próximo tick volvería al peso previo
    // al AT+INICIO.
    _measurement = _measurement.copyWith(peso: _currentDisplayedPeso.round());
    _guillotina.close();

    return 'AT+FINALIZAR recibido: descarga terminada en ${_measurement.peso} '
        'kg (objetivo ${_targetPeso.round()} kg'
        '${estabaPausada ? ', estaba pausada' : ''}), cerrando guillotina, '
        'el tubo queda como está, no se envía AT+GUARDAR';
  }

  /// `AT+MOVIMIENTO` mueve un actuador a mano. El recorrido completo tarda
  /// [HydraulicTube.manualTravel]; invertir la marcha a mitad de camino
  /// arranca desde donde quedó, no desde el tope.
  String applyMovimiento(HydraulicMovementCommand command) {
    _lastMovimiento = command;

    // Durante una corrida los actuadores los maneja el ciclo de descarga: los
    // abrir/cerrar se ignoran hasta que termine. Una descarga pausada por
    // AT+DETENER sigue siendo una corrida en curso.
    if (_phase != HydraulicRunPhase.idle) {
      return 'AT+MOVIMIENTO recibido: ${command.label} (tipo=${command.tipo}) '
          '-> ignorado, hay una descarga en curso'
          '${_dischargePaused ? ' (pausada)' : ''}';
    }

    final bool? opens = command.opens;
    if (opens == null) {
      return 'AT+MOVIMIENTO recibido: ${command.label} (tipo=${command.tipo})';
    }

    final int segundos = HydraulicTube.manualTravel.inSeconds;
    if (command.affectsTube) {
      _tubo.moveManually(opening: opens);
      return 'AT+MOVIMIENTO recibido: ${command.label} (tipo=${command.tipo}) '
          '-> tubo ${TubeState.label(_tubo.state)} (recorrido ${segundos}s)';
    }
    _guillotina.moveManually(opening: opens);
    return 'AT+MOVIMIENTO recibido: ${command.label} (tipo=${command.tipo}) '
        '-> guillotina ${opens ? 'abriendo' : 'cerrando'} desde '
        '${_guillotina.percent}% (recorrido ${segundos}s)';
  }

  double _rateForVelocidad(int velocidad) {
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
}
