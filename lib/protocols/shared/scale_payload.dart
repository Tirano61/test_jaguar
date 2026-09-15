import 'dart:convert';

import 'package:test_jaguar/domain/entities/scale_measurement.dart';

/// JSON de balanza: las 7 claves de `ScaleMeasurement` y nada más.
///
/// Lo comparten Jaguar BLE y Manual, que mandan exactamente la misma trama y
/// sólo se diferencian en de dónde sale la medición (el motor de simulación o
/// los controles de la UI). El modo Hidráulico agrega campos y por eso tiene su
/// propio payload.
class ScalePayloadDto {
  const ScalePayloadDto({required this.measurement});

  final ScaleMeasurement measurement;

  String toJsonUtf8String() => jsonEncode(measurement.toMap());
}
