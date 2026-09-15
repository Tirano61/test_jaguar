import 'package:flutter_test/flutter_test.dart';
import 'package:test_jaguar/domain/entities/scale_measurement.dart';
import 'package:test_jaguar/domain/value_objects/send_protocol.dart';

import 'support/orchestrator_harness.dart';

/// Caracteriza el congelado de peso: cuando `sensorInduc` cambia, el peso
/// queda fijo 5 ticks. Es el automatismo compartido entre Jaguar BLE y
/// Remoto ST407 y el de más riesgo al separar los protocolos, porque su
/// estado vive en el orquestador y se alimenta del último peso emitido
/// **globalmente**, no del peso del protocolo activo.
void main() {
  test('el peso queda congelado exactamente 5 ticks tras el cambio de sensor',
      () async {
    final Harness harness = await newHarness();

    await harness.tickWith(peso: 1000);
    expect(harness.pesoEnJson, 1000);

    // El cambio de sensorInduc congela el peso que se había emitido antes.
    await harness.tickWith(peso: 2000, sensorInduc: 1);
    expect(harness.pesoEnJson, 1000);

    for (final int peso in <int>[3000, 4000, 5000, 6000]) {
      await harness.tickWith(peso: peso, sensorInduc: 1);
      expect(harness.pesoEnJson, 1000, reason: 'sigue congelado en $peso');
    }

    // Sexto tick después del cambio: se descongela.
    await harness.tickWith(peso: 7000, sensorInduc: 1);
    expect(harness.pesoEnJson, 7000);
  });

  test('el cambio de sensor se loguea una sola vez', () async {
    final Harness harness = await newHarness();

    await harness.tickWith(peso: 1000);
    await harness.tickWith(peso: 2000, sensorInduc: 1);

    expect(harness.lastLog, 'Cambio sensorInduc 0 -> 1: peso congelado 5s');

    await harness.tickWith(peso: 3000, sensorInduc: 1);
    final int repeticiones = harness.logs
        .where((String l) => l.startsWith('Cambio sensorInduc'))
        .length;
    expect(repeticiones, 1);
  });

  test('la cuenta atrás reportada arranca en 4, no en 5', () async {
    final Harness harness = await newHarness();

    await harness.tickWith(peso: 1000);
    expect(harness.weightHoldSecondsRemaining, 0);

    // El contador se pone en 5 y se decrementa antes de reportarse, así que
    // el primer valor que ve la UI es 4.
    final List<int> reportados = <int>[];
    await harness.tickWith(peso: 2000, sensorInduc: 1);
    reportados.add(harness.weightHoldSecondsRemaining);
    for (final int peso in <int>[3000, 4000, 5000, 6000]) {
      await harness.tickWith(peso: peso, sensorInduc: 1);
      reportados.add(harness.weightHoldSecondsRemaining);
    }

    expect(reportados, <int>[4, 3, 2, 1, 0]);
  });

  test('el peso congelado sale del último emitido, aunque fuera de otro modo',
      () async {
    final Harness harness = await newHarness();

    // Un peso manual bien distinguible pasa a ser el último emitido.
    await harness.orchestrator.setSendProtocol(SendProtocol.manual);
    await harness.orchestrator.setManualMeasurement(
      ScaleMeasurement.baseline.copyWith(peso: 7777),
    );
    await pumpEventQueue();
    expect(harness.pesoEnJson, 7777);

    await harness.orchestrator.setSendProtocol(SendProtocol.jaguarBle);
    await pumpEventQueue();

    // Al congelar, el orquestador toma el último peso emitido globalmente:
    // el del modo manual, no el que trae el motor.
    await harness.tickWith(peso: 500, sensorInduc: 1);
    expect(harness.pesoEnJson, 7777);
  });

  test('cambiar de protocolo cancela un congelado en curso', () async {
    final Harness harness = await newHarness();

    await harness.tickWith(peso: 1000);
    await harness.tickWith(peso: 2000, sensorInduc: 1);
    expect(harness.weightHoldSecondsRemaining, 4);

    await harness.orchestrator.setSendProtocol(SendProtocol.st407Remote);
    await pumpEventQueue();
    expect(harness.weightHoldSecondsRemaining, 0);

    // Ya no congela: el peso del motor pasa derecho.
    await harness.tickWith(peso: 3000, sensorInduc: 1);
    expect(harness.pesoEmitido, 3000);
  });

  test('estBalanza reporta estable mientras el peso está congelado', () async {
    final Harness harness = await newHarness();

    await harness.tickWith(peso: 1000);
    // Peso distinto del anterior -> inestable.
    await harness.tickWith(peso: 2000);
    expect(harness.jsonEnviado['estBalanza'], 0);

    // Durante el congelado el peso emitido no cambia, así que se reporta
    // estable aunque el sensor se esté moviendo. Comportamiento heredado.
    await harness.tickWith(peso: 3000, sensorInduc: 1);
    expect(harness.pesoEnJson, 2000);
    expect(harness.jsonEnviado['estBalanza'], 1);
  });
}
