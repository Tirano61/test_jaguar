import 'package:test_jaguar/core/constants/ble_constants.dart';
import 'package:test_jaguar/domain/entities/scale_measurement.dart';
import 'package:test_jaguar/domain/value_objects/send_protocol.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_actuator_position.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_discharge_command.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_movement_command.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_payload.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_pto.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_state.dart';
import 'package:test_jaguar/protocols/payload_framing.dart';
import 'package:test_jaguar/protocols/simulator_protocol.dart';

/// Eventos que el simulador **notifica** a la app al cerrar una descarga.
abstract final class HydraulicSaveEvent {
  static const String guardar = 'AT+GUARDAR';

  /// Cierre de la primera descarga del modo "dos descargas" (`modo = 2` en
  /// `AT+INICIO`): la app guarda/imprime/envía igual que con [guardar], pero se
  /// queda en descarga y manda un segundo `AT+INICIO` en modo 1.
  static const String guardarDos = 'AT+GUARDARDOS';
}

/// Protocolo Hidráulico BLE: la caja de manejo del tubo y la guillotina.
///
/// Comparte el perfil GATT de Jaguar, pero agrega al JSON los campos de la caja
/// (`tomaFuerza`, `rpm`, `errorEcu`) y es el único que procesa la familia de
/// comandos de descarga (`AT+INICIO`, `AT+DETENER`, `AT+REANUDAR`,
/// `AT+FINALIZAR`, `AT+MOVIMIENTO`).
///
/// **No usa el motor de simulación automático**: no hay ciclo de fases acá. El
/// peso queda fijo salvo que el tester lo edite a mano o haya una descarga
/// activa, y `sensorInduc` nunca cambia — la transición carga/descarga la
/// maneja la app conectada por comando, no por sensor.
///
/// Los métodos que procesan comandos devuelven la línea de log a publicar en
/// vez de escribirla: así el módulo no necesita conocer al orquestador y se
/// puede probar solo.
class HydraulicProtocol implements SimulatorProtocol {
  HydraulicProtocol();

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

  /// Posición de cada actuador en pasos discretos (0 cerrado .. 5 abierto):
  /// cada `AT+MOVIMIENTO` mueve un paso hasta el tope correspondiente.
  int _tuboPosicion = HydraulicActuatorPosition.closed;
  int _guillotinaPosicion = HydraulicActuatorPosition.closed;
  HydraulicDischargeCommand? _lastInicio;
  HydraulicMovementCommand? _lastMovimiento;
  bool _dischargeActive = false;

  /// `AT+DETENER` pausa la descarga en curso (no la cancela): el peso queda
  /// congelado y los parámetros de la corrida (objetivo, velocidad) se
  /// conservan hasta que llegue `AT+REANUDAR`.
  bool _dischargePaused = false;
  bool _justCompleted = false;

  /// Evento de guardado prometido por el `AT+INICIO` que inició la corrida en
  /// curso. Se congela al iniciar la descarga, como el objetivo y la velocidad,
  /// y no se deduce de [_lastInicio] al completar, porque ese campo también
  /// guarda los `AT+INICIO` inválidos y los que lleguen mientras la descarga
  /// baja.
  bool _saveAsDosDescargas = false;
  double _currentDisplayedPeso = 0.0;
  double _initialPeso = 0.0;
  double _targetPeso = 0.0;
  double _decrementPerTick = 0.0;

  HydraulicState get state => HydraulicState(
        tomaFuerza: _tomaFuerza,
        tomaFuerzaRpm: _tomaFuerzaRpm,
        errorEcu: _errorEcu,
        tuboPosicion: _tuboPosicion,
        guillotinaPosicion: _guillotinaPosicion,
        dischargeActive: _dischargeActive,
        dischargePaused: _dischargePaused,
        initialPeso: _initialPeso,
        targetPeso: _targetPeso,
        lastInicio: _lastInicio,
        lastMovimiento: _lastMovimiento,
      );

  /// Descarta la corrida en curso al salir del modo. La configuración
  /// (`tomaFuerza`, `errorEcu`, rpm) se conserva a propósito: no es estado de
  /// una descarga, es cómo dejó configurada la caja el tester.
  void resetRunState() {
    _dischargeActive = false;
    _dischargePaused = false;
    _saveAsDosDescargas = false;
    _currentDisplayedPeso = 0.0;
    _initialPeso = 0.0;
    _targetPeso = 0.0;
    _decrementPerTick = 0.0;
    _tuboPosicion = HydraulicActuatorPosition.closed;
    _guillotinaPosicion = HydraulicActuatorPosition.closed;
  }

  /// Medición vigente. Mientras una descarga corre el peso vive en
  /// [_currentDisplayedPeso] y no en [_measurement], que sólo se fija al
  /// pausar, finalizar o completar la corrida.
  ScaleMeasurement measurement({required double humidity}) {
    final ScaleMeasurement base = _measurement.copyWith(humedad: humidity);
    return _dischargeActive
        ? base.copyWith(peso: _currentDisplayedPeso.round())
        : base;
  }

  /// Peso vigente en la tolva: el de la descarga si hay una corriendo.
  int get _currentPeso => _dischargeActive
      ? _currentDisplayedPeso.round()
      : _measurement.peso;

  /// Un tick del motor de simulación. Es lo único que hace bajar el peso
  /// durante una descarga; con la simulación detenida no hay ticks.
  ScaleMeasurement advance({required double humidity}) {
    // Sólo una descarga en curso y no pausada por AT+DETENER baja el peso en
    // este tick: pausada, queda donde estaba y la corrida sigue viva hasta que
    // llegue AT+REANUDAR.
    if (_dischargeActive && !_dischargePaused) {
      final double next = _currentDisplayedPeso - _decrementPerTick;
      if (next <= _targetPeso) {
        _currentDisplayedPeso = _targetPeso;
        _dischargeActive = false;
        _justCompleted = true;
        _measurement = _measurement.copyWith(peso: _currentDisplayedPeso.round());
      } else {
        _currentDisplayedPeso = next;
      }
    }
    return measurement(humidity: humidity);
  }

  /// Evento de guardado que dejó pendiente la descarga que acaba de completar,
  /// o `null` si no completó ninguna. Se consume una sola vez.
  ///
  /// El orquestador lo drena **después** de notificar el payload del tick, para
  /// que la app vea la tolva en su peso final antes de que le pidan guardar.
  String? takeCompletedSaveEvent() {
    if (!_justCompleted) {
      return null;
    }
    _justCompleted = false;
    final bool dosDescargas = _saveAsDosDescargas;
    _saveAsDosDescargas = false;
    return dosDescargas
        ? HydraulicSaveEvent.guardarDos
        : HydraulicSaveEvent.guardar;
  }

  String encodePayload(ScaleMeasurement measurement) {
    return HydraulicPayloadDto(
      measurement: measurement,
      tomaFuerza: _tomaFuerza,
      tomaFuerzaRpm: _tomaFuerzaRpm,
      errorEcu: _errorEcu,
    ).toJsonUtf8String();
  }

  // --- Configuración desde la UI ---
  // Devuelven la línea de log, o null si no hubo cambio que publicar.

  String? setPeso(int value) {
    if (_dischargeActive) {
      return null; // no se edita a mano mientras hay una descarga en curso
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
    final int rpmEnviadas = HydraulicPtoState.isOn(_tomaFuerza) ? _tomaFuerzaRpm : 0;
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
    _dischargeActive = true;
    _dischargePaused = false;
    _saveAsDosDescargas = command.isDosDescargas;

    // Al descargar el tubo queda totalmente abierto y la guillotina en alguna
    // posición que no sea "cerrada": si venía cerrada se la lleva al primer
    // paso de apertura, si ya estaba abierta se respeta donde la dejaron.
    _tuboPosicion = HydraulicActuatorPosition.open;
    if (HydraulicActuatorPosition.isClosed(_guillotinaPosicion)) {
      _guillotinaPosicion = HydraulicActuatorPosition.firstOpenStep;
    }

    return 'AT+INICIO recibido: ${command.summary} -> tubo '
        '${HydraulicActuatorPosition.label(_tuboPosicion)}, guillotina '
        '${HydraulicActuatorPosition.label(_guillotinaPosicion)}, cierra con '
        '${_saveAsDosDescargas ? HydraulicSaveEvent.guardarDos : HydraulicSaveEvent.guardar}';
  }

  /// `AT+DETENER` **pausa** la descarga simulada en curso: el peso queda
  /// congelado donde estaba, la corrida sigue viva (objetivo, velocidad y
  /// posiciones de los actuadores se conservan) y **no** se envía `AT+GUARDAR`,
  /// porque todavía no se alcanzó el objetivo. La descarga retoma desde ese
  /// mismo peso al recibir `AT+REANUDAR`.
  String applyDetener() {
    if (!_dischargeActive) {
      return 'AT+DETENER recibido: no hay descarga en curso';
    }
    if (_dischargePaused) {
      return 'AT+DETENER recibido: la descarga ya estaba pausada';
    }

    _dischargePaused = true;
    // Mientras la descarga corre el peso vive en _currentDisplayedPeso: hay que
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
    if (!_dischargeActive) {
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
  /// objetivo: el peso queda donde estaba en ese momento y la corrida se
  /// descarta (no queda nada para reanudar). Sirve tanto con la descarga
  /// corriendo como pausada por `AT+DETENER`. No se envía `AT+GUARDAR`, porque
  /// el guardado lo decide la app que finalizó. Los actuadores quedan en la
  /// posición en la que estaban y vuelven a responder a `AT+MOVIMIENTO`.
  String applyFinalizar() {
    if (!_dischargeActive) {
      return 'AT+FINALIZAR recibido: no hay descarga en curso';
    }

    final bool estabaPausada = _dischargePaused;
    _dischargeActive = false;
    _dischargePaused = false;
    _justCompleted = false;
    // La corrida se descarta entera: su evento de guardado no puede quedar
    // pegado para el próximo AT+INICIO.
    _saveAsDosDescargas = false;
    // Mientras la descarga corre el peso vive en _currentDisplayedPeso: hay que
    // fijarlo en la medición del modo o el próximo tick volvería al peso previo
    // al AT+INICIO.
    _measurement = _measurement.copyWith(peso: _currentDisplayedPeso.round());

    return 'AT+FINALIZAR recibido: descarga automática terminada en '
        '${_measurement.peso} kg (objetivo ${_targetPeso.round()} kg'
        '${estabaPausada ? ', estaba pausada' : ''}), no se envía AT+GUARDAR';
  }

  String applyMovimiento(HydraulicMovementCommand command) {
    _lastMovimiento = command;

    // Durante una descarga las posiciones las maneja la descarga misma: los
    // abrir/cerrar de tubo y guillotina se ignoran hasta que termine. Una
    // descarga pausada por AT+DETENER sigue siendo una descarga en curso.
    if (_dischargeActive) {
      return 'AT+MOVIMIENTO recibido: ${command.label} (tipo=${command.tipo}) '
          '-> ignorado, hay una descarga en curso'
          '${_dischargePaused ? ' (pausada)' : ''}';
    }

    final bool? opens = command.opens;
    if (opens != null && command.affectsTube) {
      _tuboPosicion =
          HydraulicActuatorPosition.stepped(_tuboPosicion, opening: opens);
      return 'AT+MOVIMIENTO recibido: ${command.label} (tipo=${command.tipo}) '
          '-> tubo en ${HydraulicActuatorPosition.label(_tuboPosicion)}';
    }
    if (opens != null && command.affectsGuillotine) {
      _guillotinaPosicion = HydraulicActuatorPosition.stepped(
        _guillotinaPosicion,
        opening: opens,
      );
      return 'AT+MOVIMIENTO recibido: ${command.label} (tipo=${command.tipo}) '
          '-> guillotina en '
          '${HydraulicActuatorPosition.label(_guillotinaPosicion)}';
    }
    return 'AT+MOVIMIENTO recibido: ${command.label} (tipo=${command.tipo})';
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
