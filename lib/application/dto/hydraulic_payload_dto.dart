import 'dart:convert';

import 'package:test_jaguar/domain/entities/scale_measurement.dart';

/// JSON del modo Hidráulico BLE: los campos base de `ScaleMeasurement` más
/// los dos campos nuevos del protocolo (`tomaFuerza`, `errorEcu`). Se separa
/// de `ScalePayloadDto` para no agregar estos campos a los demás protocolos.
class HydraulicPayloadDto {
  const HydraulicPayloadDto({
    required this.measurement,
    required this.tomaFuerza,
    required this.errorEcu,
  });

  final ScaleMeasurement measurement;
  final int tomaFuerza;
  final String errorEcu;

  String toJsonUtf8String() {
    final Map<String, dynamic> map = <String, dynamic>{
      ...measurement.toMap(),
      'tomaFuerza': tomaFuerza,
      'errorEcu': errorEcu,
    };
    return jsonEncode(map);
  }
}
