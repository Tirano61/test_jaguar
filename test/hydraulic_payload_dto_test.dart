import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:test_jaguar/application/dto/hydraulic_payload_dto.dart';
import 'package:test_jaguar/domain/entities/scale_measurement.dart';
import 'package:test_jaguar/domain/value_objects/hydraulic_pto.dart';

Map<String, dynamic> _payload({
  required int tomaFuerza,
  int tomaFuerzaRpm = 800,
}) {
  return jsonDecode(
    HydraulicPayloadDto(
      measurement: ScaleMeasurement.baseline,
      tomaFuerza: tomaFuerza,
      tomaFuerzaRpm: tomaFuerzaRpm,
      errorEcu: '',
    ).toJsonUtf8String(),
  ) as Map<String, dynamic>;
}

void main() {
  test('rpm viaja con la toma de fuerza encendida', () {
    expect(_payload(tomaFuerza: HydraulicPtoState.on)['rpm'], 800);
  });

  test('rpm va en 0 en el resto de los estados de toma de fuerza', () {
    for (final int estado in <int>[
      HydraulicPtoState.off,
      HydraulicPtoState.requestOn,
      HydraulicPtoState.requestOff,
    ]) {
      expect(_payload(tomaFuerza: estado)['rpm'], 0, reason: 'estado $estado');
    }
  });

  test('rpm queda topeada al rango simulable', () {
    expect(
      _payload(tomaFuerza: HydraulicPtoState.on, tomaFuerzaRpm: 5000)['rpm'],
      HydraulicPtoRpm.max,
    );
    expect(
      _payload(tomaFuerza: HydraulicPtoState.on, tomaFuerzaRpm: 0)['rpm'],
      HydraulicPtoRpm.min,
    );
  });
}
