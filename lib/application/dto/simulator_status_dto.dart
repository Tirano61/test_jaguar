import 'package:test_jaguar/core/constants/ble_constants.dart';
import 'package:test_jaguar/domain/entities/ble_peripheral_status.dart';
import 'package:test_jaguar/domain/entities/scale_measurement.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_actuator_position.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_discharge_command.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_movement_command.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_pto.dart';
import 'package:test_jaguar/domain/value_objects/send_protocol.dart';
import 'package:test_jaguar/domain/value_objects/st407_screen.dart';
import 'package:test_jaguar/domain/value_objects/simulation_phase.dart';

class SimulatorStatusDto {
  const SimulatorStatusDto({
    required this.bleStatus,
    required this.running,
    required this.sendProtocol,
    required this.bleUuids,
    required this.st407Screen,
    required this.phase,
    required this.measurement,
    required this.manualMeasurement,
    required this.weightHoldSecondsRemaining,
    required this.lastJson,
    required this.logs,
    required this.tomaFuerza,
    required this.tomaFuerzaRpm,
    required this.errorEcu,
    required this.tuboPosicion,
    required this.guillotinaPosicion,
    required this.hydraulicDischargeActive,
    required this.hydraulicDischargePaused,
    required this.hydraulicInitialPeso,
    required this.hydraulicTargetPeso,
    this.lastHydraulicInicio,
    this.lastHydraulicMovimiento,
  });

  final BlePeripheralStatus bleStatus;
  final bool running;
  final SendProtocol sendProtocol;

  /// Perfil GATT que el protocolo activo pide anunciar. Lo decide el
  /// protocolo, así que la UI lo muestra en vez de volver a deducirlo.
  final BleUuids bleUuids;
  final St407Screen st407Screen;
  final SimulationPhase phase;
  final ScaleMeasurement measurement;
  final ScaleMeasurement manualMeasurement;
  final int weightHoldSecondsRemaining;
  final String lastJson;
  final List<String> logs;
  final int tomaFuerza;

  /// RPM simuladas de la toma de fuerza (solo viajan en el JSON con la
  /// toma de fuerza encendida).
  final int tomaFuerzaRpm;
  final String errorEcu;
  /// Posición del tubo en pasos (`HydraulicActuatorPosition.closed` ..
  /// `HydraulicActuatorPosition.open`).
  final int tuboPosicion;

  /// Posición de la guillotina en pasos (misma escala que [tuboPosicion]).
  final int guillotinaPosicion;
  final bool hydraulicDischargeActive;

  /// Descarga en curso pero pausada por `AT+DETENER`: el peso no baja
  /// hasta que llegue `AT+REANUDAR`.
  final bool hydraulicDischargePaused;
  final double hydraulicInitialPeso;
  final double hydraulicTargetPeso;
  final HydraulicDischargeCommand? lastHydraulicInicio;
  final HydraulicMovementCommand? lastHydraulicMovimiento;

  static const SimulatorStatusDto initial = SimulatorStatusDto(
    bleStatus: BlePeripheralStatus.initial,
    running: false,
    sendProtocol: SendProtocol.jaguarBle,
    bleUuids: BleConstants.jaguar,
    st407Screen: St407Screen.main,
    phase: SimulationPhase.loadedWaiting,
    measurement: ScaleMeasurement.baseline,
    manualMeasurement: ScaleMeasurement.baseline,
    weightHoldSecondsRemaining: 0,
    lastJson: '{}',
    logs: <String>[],
    tomaFuerza: HydraulicPtoState.off,
    tomaFuerzaRpm: HydraulicPtoRpm.defaultValue,
    errorEcu: '',
    tuboPosicion: HydraulicActuatorPosition.closed,
    guillotinaPosicion: HydraulicActuatorPosition.closed,
    hydraulicDischargeActive: false,
    hydraulicDischargePaused: false,
    hydraulicInitialPeso: 0.0,
    hydraulicTargetPeso: 0.0,
  );

  SimulatorStatusDto copyWith({
    BlePeripheralStatus? bleStatus,
    bool? running,
    SendProtocol? sendProtocol,
    BleUuids? bleUuids,
    St407Screen? st407Screen,
    SimulationPhase? phase,
    ScaleMeasurement? measurement,
    ScaleMeasurement? manualMeasurement,
    int? weightHoldSecondsRemaining,
    String? lastJson,
    List<String>? logs,
    int? tomaFuerza,
    int? tomaFuerzaRpm,
    String? errorEcu,
    int? tuboPosicion,
    int? guillotinaPosicion,
    bool? hydraulicDischargeActive,
    bool? hydraulicDischargePaused,
    double? hydraulicInitialPeso,
    double? hydraulicTargetPeso,
    HydraulicDischargeCommand? lastHydraulicInicio,
    HydraulicMovementCommand? lastHydraulicMovimiento,
  }) {
    return SimulatorStatusDto(
      bleStatus: bleStatus ?? this.bleStatus,
      running: running ?? this.running,
      sendProtocol: sendProtocol ?? this.sendProtocol,
      bleUuids: bleUuids ?? this.bleUuids,
      st407Screen: st407Screen ?? this.st407Screen,
      phase: phase ?? this.phase,
      measurement: measurement ?? this.measurement,
      manualMeasurement: manualMeasurement ?? this.manualMeasurement,
      weightHoldSecondsRemaining:
          weightHoldSecondsRemaining ?? this.weightHoldSecondsRemaining,
      lastJson: lastJson ?? this.lastJson,
      logs: logs ?? this.logs,
      tomaFuerza: tomaFuerza ?? this.tomaFuerza,
      tomaFuerzaRpm: tomaFuerzaRpm ?? this.tomaFuerzaRpm,
      errorEcu: errorEcu ?? this.errorEcu,
      tuboPosicion: tuboPosicion ?? this.tuboPosicion,
      guillotinaPosicion: guillotinaPosicion ?? this.guillotinaPosicion,
      hydraulicDischargeActive:
          hydraulicDischargeActive ?? this.hydraulicDischargeActive,
      hydraulicDischargePaused:
          hydraulicDischargePaused ?? this.hydraulicDischargePaused,
      hydraulicInitialPeso: hydraulicInitialPeso ?? this.hydraulicInitialPeso,
      hydraulicTargetPeso: hydraulicTargetPeso ?? this.hydraulicTargetPeso,
      lastHydraulicInicio: lastHydraulicInicio ?? this.lastHydraulicInicio,
      lastHydraulicMovimiento:
          lastHydraulicMovimiento ?? this.lastHydraulicMovimiento,
    );
  }
}
