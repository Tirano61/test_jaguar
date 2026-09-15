import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_actuators.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_discharge_command.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_movement_command.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_pto.dart';

/// En qué momento del ciclo está una corrida de descarga.
///
/// La descarga ya no arranca apenas llega `AT+INICIO`: primero hay que abrir el
/// tubo, y al terminar hay que cerrarlo. Son tres fases con comportamientos
/// distintos, no un booleano.
enum HydraulicRunPhase {
  /// Sin corrida: los actuadores responden a `AT+MOVIMIENTO`.
  idle,

  /// Llegó `AT+INICIO` y el tubo se está abriendo. El peso todavía no baja.
  abriendoTubo,

  /// Tubo abierto: el peso baja con cada tick del motor.
  descargando,

  /// Se alcanzó el objetivo y ya se notificó el guardado; el tubo se cierra.
  cerrandoTubo,
}

/// Foto inmutable del modo Hidráulico BLE para la UI.
///
/// Separa lo que es **configuración** (toma de fuerza, rpm, errorEcu: valores
/// que el tester fija y que sobreviven a un cambio de protocolo) de lo que es
/// **estado de la corrida** (fase, pesos, actuadores), que se descarta al salir
/// del modo.
class HydraulicState {
  const HydraulicState({
    required this.tomaFuerza,
    required this.tomaFuerzaRpm,
    required this.errorEcu,
    required this.tubo,
    required this.tuboProgress,
    required this.gillo,
    required this.phase,
    required this.dischargePaused,
    required this.initialPeso,
    required this.targetPeso,
    this.lastInicio,
    this.lastMovimiento,
  });

  final int tomaFuerza;

  /// RPM simuladas de la toma de fuerza. Sólo viajan en el JSON con la toma de
  /// fuerza encendida.
  final int tomaFuerzaRpm;
  final String errorEcu;

  /// Estado del tubo (`TubeState`), que es lo que viaja en el JSON.
  final int tubo;

  /// Cuánto lleva recorrido el tubo, 0.0 a 1.0. **Sólo para la barra de la UI
  /// del simulador**: el equipo real no tiene esta información y por eso no
  /// sale en el JSON.
  final double tuboProgress;

  /// Apertura de la guillotina, 0 a 100.
  final int gillo;

  final HydraulicRunPhase phase;

  /// Descarga en curso pero pausada por `AT+DETENER`: el peso no baja hasta
  /// que llegue `AT+REANUDAR`.
  final bool dischargePaused;
  final double initialPeso;
  final double targetPeso;
  final HydraulicDischargeCommand? lastInicio;
  final HydraulicMovementCommand? lastMovimiento;

  /// Hay una corrida en curso: desde que se acepta `AT+INICIO` hasta que el
  /// tubo termina de cerrarse. Mientras dure, `AT+MOVIMIENTO` se ignora.
  bool get runActive => phase != HydraulicRunPhase.idle;

  /// El peso está bajando (o pausado a mitad de camino).
  bool get dischargeActive => phase == HydraulicRunPhase.descargando;

  static const HydraulicState initial = HydraulicState(
    tomaFuerza: HydraulicPtoState.off,
    tomaFuerzaRpm: HydraulicPtoRpm.defaultValue,
    errorEcu: '',
    tubo: TubeState.cerrado,
    tuboProgress: 0.0,
    gillo: 0,
    phase: HydraulicRunPhase.idle,
    dischargePaused: false,
    initialPeso: 0.0,
    targetPeso: 0.0,
  );
}
