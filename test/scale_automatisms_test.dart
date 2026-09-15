import 'package:flutter_test/flutter_test.dart';
import 'package:test_jaguar/domain/entities/scale_measurement.dart';
import 'package:test_jaguar/protocols/shared/scale_automatisms.dart';

/// Los automatismos compartidos por Jaguar BLE y Remoto ST407, probados solos.
/// La integración con el orquestador (que el congelado tome el peso de otro
/// protocolo, que se cancele al cambiar de modo) sigue en
/// `weight_hold_automatism_test.dart`.
void main() {
  ScaleMeasurement medicion(int peso, {int sensorInduc = 0}) =>
      ScaleMeasurement.baseline.copyWith(peso: peso, sensorInduc: sensorInduc);

  ScaleAutomatisms nuevo() => ScaleAutomatisms(sensorInduc: 0);

  test('sin cambio de sensor el peso pasa derecho', () {
    final ScaleAutomatisms a = nuevo();

    final ScaleMeasurement r = a.apply(
      medicion(1000),
      lastEmitted: medicion(900),
      log: (_) {},
    );

    expect(r.peso, 1000);
    expect(a.holdSecondsRemaining, 0);
  });

  test('el cambio de sensor congela el peso del último emitido', () {
    final ScaleAutomatisms a = nuevo();
    final List<String> logs = <String>[];

    final ScaleMeasurement r = a.apply(
      medicion(5000, sensorInduc: 1),
      lastEmitted: medicion(900),
      log: logs.add,
    );

    expect(r.peso, 900, reason: 'congela el emitido, no el que llega');
    expect(logs, <String>['Cambio sensorInduc 0 -> 1: peso congelado 5s']);
  });

  test('el congelado dura 5 aplicaciones y reporta 4-3-2-1-0', () {
    final ScaleAutomatisms a = nuevo();
    final List<int> reportados = <int>[];

    a.apply(medicion(5000, sensorInduc: 1),
        lastEmitted: medicion(900), log: (_) {});
    reportados.add(a.holdSecondsRemaining);

    for (int i = 0; i < 4; i++) {
      final ScaleMeasurement r = a.apply(
        medicion(6000 + i, sensorInduc: 1),
        lastEmitted: medicion(900),
        log: (_) {},
      );
      expect(r.peso, 900);
      reportados.add(a.holdSecondsRemaining);
    }

    expect(reportados, <int>[4, 3, 2, 1, 0]);

    // Sexta aplicación: ya no congela.
    final ScaleMeasurement libre = a.apply(
      medicion(7000, sensorInduc: 1),
      lastEmitted: medicion(900),
      log: (_) {},
    );
    expect(libre.peso, 7000);
  });

  test('el log del cambio de sensor sale una sola vez', () {
    final ScaleAutomatisms a = nuevo();
    final List<String> logs = <String>[];

    for (int i = 0; i < 3; i++) {
      a.apply(medicion(5000, sensorInduc: 1),
          lastEmitted: medicion(900), log: logs.add);
    }

    expect(logs, hasLength(1));
  });

  test('reset cancela el congelado en curso', () {
    final ScaleAutomatisms a = nuevo();
    a.apply(medicion(5000, sensorInduc: 1),
        lastEmitted: medicion(900), log: (_) {});
    expect(a.holdSecondsRemaining, 4);

    a.reset(sensorInduc: 1);

    expect(a.holdSecondsRemaining, 0);
    final ScaleMeasurement r = a.apply(
      medicion(5000, sensorInduc: 1),
      lastEmitted: medicion(900),
      log: (_) {},
    );
    expect(r.peso, 5000, reason: 'ya no congela');
  });

  test('estBalanza: 0 si el peso se movió, 1 si no', () {
    final ScaleAutomatisms a = nuevo();

    expect(
      a.apply(medicion(1000), lastEmitted: medicion(900), log: (_) {}).estBalanza,
      0,
    );
    expect(
      a.apply(medicion(1000), lastEmitted: medicion(1000), log: (_) {}).estBalanza,
      1,
    );
  });

  test('durante el congelado reporta estable aunque el sensor se mueva', () {
    final ScaleAutomatisms a = nuevo();

    // El peso emitido no cambia porque está congelado, así que la comparación
    // de estabilidad da "igual". Comportamiento heredado.
    final ScaleMeasurement r = a.apply(
      medicion(5000, sensorInduc: 1),
      lastEmitted: medicion(900),
      log: (_) {},
    );

    expect(r.peso, 900);
    expect(r.estBalanza, 1);
  });
}
