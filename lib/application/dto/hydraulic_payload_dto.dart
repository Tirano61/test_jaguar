import 'dart:convert';

import 'package:test_jaguar/domain/entities/scale_measurement.dart';
import 'package:test_jaguar/domain/value_objects/hydraulic_pto.dart';

/// JSON del modo Hidráulico BLE: los campos base de `ScaleMeasurement` más
/// los campos nuevos del protocolo (`tomaFuerza`, `rpm`, `errorEcu`). Se
/// separa de `ScalePayloadDto` para no agregar estos campos a los demás
/// protocolos.
class HydraulicPayloadDto {
  const HydraulicPayloadDto({
    required this.measurement,
    required this.tomaFuerza,
    required this.tomaFuerzaRpm,
    required this.errorEcu,
  });

  final ScaleMeasurement measurement;
  final int tomaFuerza;

  /// RPM simuladas de la toma de fuerza. Solo salen en el JSON cuando
  /// [tomaFuerza] está en encendida; ver [rpm].
  final int tomaFuerzaRpm;
  final String errorEcu;

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
    };
    return jsonEncode(map);
  }
}
