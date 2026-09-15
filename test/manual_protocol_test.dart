import 'package:flutter_test/flutter_test.dart';
import 'package:test_jaguar/domain/entities/scale_measurement.dart';
import 'package:test_jaguar/protocols/manual/manual_protocol.dart';

/// El módulo Manual se prueba solo. El ruteo de los comandos entre protocolos
/// (que `AT+RSTHOLD` llegue acá aunque el modo activo sea otro, que `AT+TARA`
/// no) sigue en `at_command_routing_test.dart`.
void main() {
  ManualProtocol conPeso(int peso) {
    final ManualProtocol p = ManualProtocol();
    p.set(ScaleMeasurement.baseline.copyWith(peso: peso));
    return p;
  }

  test('recorta cada campo a su rango', () {
    final ManualProtocol p = ManualProtocol();
    p.set(const ScaleMeasurement(
      tara: 99999,
      hold: 7,
      vbat: 9.99,
      peso: -5,
      estBalanza: 9,
      humedad: 99.9,
      sensorInduc: 5,
    ));

    expect(p.measurement.tara, 22000);
    expect(p.measurement.hold, 1);
    expect(p.measurement.vbat, 5.0);
    expect(p.measurement.peso, 0);
    expect(p.measurement.estBalanza, 5);
    expect(p.measurement.humedad, 22.0);
    expect(p.measurement.sensorInduc, 1);
  });

  test('AT+TARA pasa el peso a tara y lo devuelve al desactivar', () {
    final ManualProtocol p = conPeso(800);

    expect(p.applyToggleTare(), 'Comando aplicado: AT+TARA -> tara activada');
    expect(p.measurement.tara, 800);
    expect(p.measurement.peso, 0);

    expect(p.applyToggleTare(), 'Comando aplicado: AT+TARA -> tara desactivada');
    expect(p.measurement.tara, 0);
    expect(p.measurement.peso, 800);
  });

  test('AT+CERO no hace nada con una tara puesta', () {
    final ManualProtocol p = conPeso(800);
    p.applyToggleTare(); // deja tara=800, peso=0

    expect(p.applyZeroWeight(), isNull, reason: 'peso ya en 0');

    p.set(p.measurement.copyWith(peso: 500)); // peso 500 con tara 800
    expect(p.applyZeroWeight(), isNull, reason: 'hay tara puesta');
    expect(p.measurement.peso, 500);
  });

  test('AT+CERO sin tara pone el peso en cero', () {
    final ManualProtocol p = conPeso(800);

    expect(p.applyZeroWeight(), 'Comando aplicado: AT+CERO -> peso=0 (manual)');
    expect(p.measurement.peso, 0);
    expect(p.applyZeroWeight(), isNull, reason: 'ya estaba en 0');
  });

  test('AT+RSTHOLD suelta el hold una sola vez', () {
    final ManualProtocol p = conPeso(800);
    expect(p.measurement.hold, 1, reason: 'baseline viene con hold');

    expect(p.applyResetHold(), 'Comando aplicado: AT+RSTHOLD -> hold=0');
    expect(p.measurement.hold, 0);
    expect(p.measurement.estBalanza, 1);

    // Repetido no cambia nada, y por eso el orquestador tampoco reenvía.
    expect(p.applyResetHold(), isNull);
  });

  test('el payload son las 7 claves de la medición, sin extras', () {
    final ManualProtocol p = conPeso(800);

    expect(
      p.encodePayload(p.measurement),
      '{"tara":0,"hold":1,"vbat":3.9,"peso":800,"estBalanza":3,'
      '"humedad":10.0,"sensorInduc":0}',
    );
  });
}
