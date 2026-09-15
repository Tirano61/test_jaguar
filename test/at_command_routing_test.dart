import 'package:flutter_test/flutter_test.dart';
import 'package:test_jaguar/domain/value_objects/send_protocol.dart';

import 'support/orchestrator_harness.dart';

/// Caracteriza a qué protocolo llega cada comando AT y qué pasa cuando llega
/// al protocolo equivocado.
///
/// Hay tres comandos (`AT+RSTHOLD`, `AT+TARA`, `AT+CERO`) que tocan estado
/// compartido del orquestador y tienen efectos cruzados entre protocolos. Son
/// los que un corte estricto por protocolo rompería en silencio, así que estos
/// tests fijan el comportamiento exacto de hoy antes de mover nada.
void main() {
  group('comandos del Hidráulico recibidos en otro protocolo', () {
    test('se ignoran con un mensaje que dice qué protocolo elegir', () async {
      final Harness harness = await newHarness();
      final int payloadsAntes = harness.payloads.length;

      await harness.receive('AT+DETENER\r\n');
      expect(
        harness.lastLog,
        'AT+DETENER recibido pero se ignora: seleccioná "Hidráulico BLE" '
        'para procesarlo.',
      );

      await harness.receive('AT+REANUDAR\r\n');
      expect(
        harness.lastLog,
        'AT+REANUDAR recibido pero se ignora: seleccioná "Hidráulico BLE" '
        'para procesarlo.',
      );

      await harness.receive('AT+FINALIZAR\r\n');
      expect(
        harness.lastLog,
        'AT+FINALIZAR recibido pero se ignora: seleccioná "Hidráulico BLE" '
        'para procesarlo.',
      );

      // Ninguno de los tres genera tráfico BLE.
      expect(harness.payloads.length, payloadsAntes);
    });

    test('AT+INICIO y AT+MOVIMIENTO detallan lo que venía en el comando',
        () async {
      final Harness harness = await newHarness();
      final int payloadsAntes = harness.payloads.length;

      await harness.receive('AT+INICIO=1500,300,100,3,2\r\n');
      expect(
        harness.lastLog,
        'AT+INICIO recibido pero se ignora: seleccioná "Hidráulico BLE" '
        'para procesarlo (descarga=1500 kg, tubo=300 kg, precierre=100 kg, '
        'modo=Total, velocidad=Normal).',
      );

      await harness.receive('AT+MOVIMIENTO=1\r\n');
      expect(
        harness.lastLog,
        'AT+MOVIMIENTO recibido pero se ignora: seleccioná "Hidráulico BLE" '
        'para procesarlo (Abrir tubo).',
      );

      expect(harness.payloads.length, payloadsAntes);
    });
  });

  group('AT+TARA', () {
    test('alterna la tara en modo Manual', () async {
      final Harness harness = await newHarness();
      await harness.orchestrator.setSendProtocol(SendProtocol.manual);
      await harness.orchestrator.setManualMeasurement(
        harness.latest.manualMeasurement.copyWith(peso: 800),
      );
      await pumpEventQueue();

      await harness.receive('AT+TARA\r\n');
      expect(harness.manualTara, 800);
      expect(harness.manualPeso, 0);
      expect(harness.lastLog, 'Comando aplicado: AT+TARA -> tara activada');

      await harness.receive('AT+TARA\r\n');
      expect(harness.manualTara, 0);
      expect(harness.manualPeso, 800);
      expect(harness.lastLog, 'Comando aplicado: AT+TARA -> tara desactivada');
    });

    test('fuera de Manual no hace nada: ni log propio ni notify', () async {
      final Harness harness = await newHarness();
      final int payloadsAntes = harness.payloads.length;

      await harness.receive('AT+TARA\r\n');

      // Queda sólo el log genérico de recepción: ningún "Comando aplicado".
      expect(harness.logs, contains('Comando recibido: AT+TARA\r\n'));
      expect(harness.logsAplicados, isEmpty);
      expect(harness.manualTara, 0);
      expect(harness.payloads.length, payloadsAntes);
    });
  });

  group('AT+RSTHOLD', () {
    test('se aplica aunque el protocolo activo no sea Manual', () async {
      final Harness harness = await newHarness();
      await harness.tickWith(peso: 1234);
      final int payloadsAntes = harness.payloads.length;

      expect(harness.manualHold, 1);
      await harness.receive('AT+RSTHOLD\r\n');

      // Muta el estado manual estando en Jaguar...
      expect(harness.manualHold, 0);
      expect(harness.lastLog, 'Comando aplicado: AT+RSTHOLD -> hold=0');

      // ...y reenvía un payload del protocolo ACTIVO, no uno manual.
      expect(harness.payloads.length, payloadsAntes + 1);
      expect(harness.pesoEnJson, 1234);
      expect(harness.jsonEnviado.containsKey('tomaFuerza'), isFalse);
    });

    test('repetido no vuelve a notificar', () async {
      final Harness harness = await newHarness();
      await harness.receive('AT+RSTHOLD\r\n');
      final int payloadsDespues = harness.payloads.length;

      await harness.receive('AT+RSTHOLD\r\n');

      // El hold ya estaba en 0, así que la guarda de "no cambió nada" también
      // saltea el reenvío.
      expect(harness.payloads.length, payloadsDespues);
    });
  });

  group('AT+CERO', () {
    test('en Manual pone el peso en cero y lo deja así', () async {
      final Harness harness = await newHarness();
      await harness.orchestrator.setSendProtocol(SendProtocol.manual);
      await harness.orchestrator.setManualMeasurement(
        harness.latest.manualMeasurement.copyWith(peso: 800),
      );
      await pumpEventQueue();

      await harness.receive('AT+CERO\r\n');

      expect(harness.manualPeso, 0);
      expect(harness.lastLog, 'Comando aplicado: AT+CERO -> peso=0 (manual)');
    });

    test('en Manual con tara puesta no hace absolutamente nada', () async {
      final Harness harness = await newHarness();
      await harness.orchestrator.setSendProtocol(SendProtocol.manual);
      await harness.orchestrator.setManualMeasurement(
        harness.latest.manualMeasurement.copyWith(peso: 800, tara: 100),
      );
      await pumpEventQueue();
      final int payloadsAntes = harness.payloads.length;

      await harness.receive('AT+CERO\r\n');

      expect(harness.manualPeso, 800);
      expect(harness.payloads.length, payloadsAntes);
      expect(harness.logs, contains('Comando recibido: AT+CERO\r\n'));
      expect(harness.logsAplicados, isEmpty);
    });

    test('fuera de Manual el cero es efímero y el próximo tick lo deshace',
        () async {
      final Harness harness = await newHarness();
      await harness.tickWith(peso: 1000);

      await harness.receive('AT+CERO\r\n');
      expect(harness.pesoEnJson, 0);
      // El log dice "(jaguar)" aunque la rama también corra en ST407 e
      // Hidráulico. Comportamiento heredado.
      expect(harness.lastLog, 'Comando aplicado: AT+CERO -> peso=0 (jaguar)');

      await harness.tickWith(peso: 2000);
      expect(harness.pesoEnJson, 2000);
    });
  });

  group('normalización y deduplicación', () {
    test('acepta minúsculas, espacios, CRLF y el alias pelado', () async {
      for (final String variante in <String>[
        'at+tara\r\n',
        'AT+TARA ',
        'TARA',
        r'\r\nAT+TARA',
      ]) {
        final Harness harness = await newHarness();
        await harness.orchestrator.setSendProtocol(SendProtocol.manual);
        await harness.orchestrator.setManualMeasurement(
          harness.latest.manualMeasurement.copyWith(peso: 800),
        );
        await pumpEventQueue();

        await harness.receive(variante);

        expect(harness.manualTara, 800, reason: 'variante "$variante"');
      }
    });

    test('un write repetido con el mismo commandSequence no se reprocesa',
        () async {
      final Harness harness = await newHarness();
      await harness.orchestrator.setSendProtocol(SendProtocol.hidraulicoBle);
      await harness.orchestrator.setHydraulicPeso(1000);
      await pumpEventQueue();

      await harness.receive('AT+INICIO=1000,300,100,1,2\r\n');
      await harness.tick(); // 1000 -> 950

      // Una emisión de estado no relacionada repite el último comando sin
      // cambiar la secuencia: reprocesarla reiniciaría la descarga.
      await harness.receiveWithSameSequence('AT+INICIO=1000,300,100,1,2\r\n');

      expect(harness.hydraulicInitialPeso, 1000.0);
      expect(harness.pesoEnJson, 950);
    });

    test('un comando desconocido no genera tráfico BLE', () async {
      final Harness harness = await newHarness();
      final int payloadsAntes = harness.payloads.length;

      await harness.receive('AT+FOO\r\n');

      expect(harness.payloads.length, payloadsAntes);
      expect(harness.logs, contains('Comando recibido: AT+FOO\r\n'));
      expect(harness.logsAplicados, isEmpty);
    });
  });
}
