import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_payload.dart';
import 'package:test_jaguar/domain/entities/scale_measurement.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_pto.dart';

Map<String, dynamic> _payload({
  required int tomaFuerza,
  int tomaFuerzaRpm = 800,
  int tubo = 0,
  int gillo = 0,
}) {
  return jsonDecode(
    HydraulicPayloadDto(
      measurement: ScaleMeasurement.baseline,
      tomaFuerza: tomaFuerza,
      tomaFuerzaRpm: tomaFuerzaRpm,
      errorEcu: '',
      tubo: tubo,
      gillo: gillo,
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

  test('tubo y gillo viajan tal cual se los pasa', () {
    final Map<String, dynamic> json =
        _payload(tomaFuerza: HydraulicPtoState.off, tubo: 2, gillo: 37);

    expect(json['tubo'], 2);
    expect(json['gillo'], 37);
  });
}
