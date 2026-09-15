import 'dart:convert';

import 'package:test_jaguar/domain/entities/scale_measurement.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_pto.dart';

/// JSON del modo Hidráulico BLE: los campos base de `ScaleMeasurement` más
/// los del protocolo — la toma de fuerza (`tomaFuerza`, `rpm`), el error de la
/// ECU (`errorEcu`) y los dos actuadores (`tubo`, `gillo`). Se separa de
/// `ScalePayloadDto` para no agregar estos campos a los demás protocolos.
class HydraulicPayloadDto {
  const HydraulicPayloadDto({
    required this.measurement,
    required this.tomaFuerza,
    required this.tomaFuerzaRpm,
    required this.errorEcu,
    required this.tubo,
    required this.gillo,
  });

  final ScaleMeasurement measurement;
  final int tomaFuerza;

  /// RPM simuladas de la toma de fuerza. Solo salen en el JSON cuando
  /// [tomaFuerza] está en encendida; ver [rpm].
  final int tomaFuerzaRpm;
  final String errorEcu;

  /// Estado del tubo: 0 cerrado, 1 abierto, 2 abriendo, 3 cerrando. No lleva
  /// posición porque el equipo real sólo tiene sensores de fin de carrera.
  final int tubo;

  /// Apertura de la guillotina, 0 cerrada a 100 totalmente abierta.
  final int gillo;

  /// RPM que se mandan en el JSON: las simuladas con la toma de fuerza
  /// encendida, 0 en cualquier otro estado.
  int get rpm => HydraulicPtoState.isOn(tomaFuerza)
      ? HydraulicPtoRpm.clamp(tomaFuerzaRpm)
      : 0;

  String toJsonUtf8String() {
    final Map<String, dynamic> map = <String, dynamic>{
      ...measurement.toMap(),
      'tomaFuerza': tomaFuerza,
      'rpm': rpm,
      'errorEcu': errorEcu,
      'tubo': tubo,
      'gillo': gillo,
    };
    return jsonEncode(map);
  }
}
