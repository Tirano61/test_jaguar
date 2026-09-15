import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_actuator_position.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_discharge_command.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_movement_command.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_pto.dart';

/// Foto inmutable del modo Hidráulico BLE para la UI.
///
/// Separa lo que es **configuración** (toma de fuerza, rpm, errorEcu: valores
/// que el tester fija y que sobreviven a un cambio de protocolo) de lo que es
/// **estado de la corrida** (descarga en curso, pesos, actuadores), que se
/// descarta al salir del modo.
class HydraulicState {
  const HydraulicState({
    required this.tomaFuerza,
    required this.tomaFuerzaRpm,
    required this.errorEcu,
    required this.tuboPosicion,
    required this.guillotinaPosicion,
    required this.dischargeActive,
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

  /// Posición del tubo en pasos (`HydraulicActuatorPosition.closed` ..
  /// `HydraulicActuatorPosition.open`).
  final int tuboPosicion;

  /// Posición de la guillotina en pasos (misma escala que [tuboPosicion]).
  final int guillotinaPosicion;
  final bool dischargeActive;

  /// Descarga en curso pero pausada por `AT+DETENER`: el peso no baja hasta
  /// que llegue `AT+REANUDAR`.
  final bool dischargePaused;
  final double initialPeso;
  final double targetPeso;
  final HydraulicDischargeCommand? lastInicio;
  final HydraulicMovementCommand? lastMovimiento;

  static const HydraulicState initial = HydraulicState(
    tomaFuerza: HydraulicPtoState.off,
    tomaFuerzaRpm: HydraulicPtoRpm.defaultValue,
    errorEcu: '',
    tuboPosicion: HydraulicActuatorPosition.closed,
    guillotinaPosicion: HydraulicActuatorPosition.closed,
    dischargeActive: false,
    dischargePaused: false,
    initialPeso: 0.0,
    targetPeso: 0.0,
  );
}
