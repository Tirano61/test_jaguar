import 'package:flutter_test/flutter_test.dart';
import 'package:test_jaguar/core/constants/payload_framing.dart';
import 'package:test_jaguar/domain/value_objects/send_protocol.dart';
import 'package:test_jaguar/protocols/st456web/st456web_screen.dart';
import 'package:test_jaguar/protocols/st456web/st456web_state.dart';

import 'support/orchestrator_harness.dart';

/// Harness en Remoto ST456web con [peso] kg como último peso emitido.
Future<Harness> _st456webHarness({int peso = 1000}) async {
  final Harness harness = await newHarness();
  await harness.tickWith(peso: peso);
  await harness.orchestrator.setSendProtocol(SendProtocol.st456web);
  await pumpEventQueue();
  return harness;
}

void main() {
  test('al activarlo notifica la pantalla principal con el peso vigente',
      () async {
    final Harness harness = await _st456webHarness();

    expect(
      harness.lastPayload,
      matches(RegExp(r'^0,1000,1,kg,,\d{2}/\d{2}/\d{4} \d{2}:\d{2},0\r\n$')),
    );
    expect(harness.ble.uuidUpdates.single.uuids.serviceUuid,
        '0000ABF3-0000-1000-8000-00805F9B34FB');
    expect(harness.ble.uuidUpdates.single.uuids.notifyUuid,
        '0000ABF5-0000-1000-8000-00805F9B34FB');
    expect(harness.ble.uuidUpdates.single.uuids.writeUuid,
        '0000ABF4-0000-1000-8000-00805F9B34FB');
    expect(harness.ble.uuidUpdates.single.framing,
        PayloadFraming.fiveByteHeader);
  });

  test('cada tick reenvía la pantalla vigente con el peso del motor', () async {
    final Harness harness = await _st456webHarness();

    await harness.tickWith(peso: 1000);
    expect(harness.lastPayload, startsWith('0,1000,1,kg,'));

    await harness.tickWith(peso: 1200);
    expect(harness.lastPayload, startsWith('0,1200,0,kg,'));
    expect(harness.pesoEmitido, 1200);
  });

  test('elegir una pantalla desde la UI la notifica y la publica', () async {
    final Harness harness = await _st456webHarness();

    await harness.orchestrator.setSt456webScreen(St456webScreen.cambioOperario);
    await pumpEventQueue();

    expect(harness.lastPayload, '42,3,Dario,1234,Estevan,0000,Claudio,4321\r\n');
    expect(harness.latest.st456web.screen, St456webScreen.cambioOperario);
    expect(harness.lastLog, contains('42 - Cambio de operario'));
  });

  test('con otro protocolo activo la pantalla cambia pero no se notifica',
      () async {
    final Harness harness = await newHarness();
    await pumpEventQueue();
    final int enviados = harness.payloads.length;

    await harness.orchestrator.setSt456webScreen(St456webScreen.trabajos);
    await pumpEventQueue();

    expect(harness.payloads, hasLength(enviados));
    expect(harness.latest.st456web.screen, St456webScreen.trabajos);
  });

  test('un popup se cierra solo con los ticks', () async {
    final Harness harness = await _st456webHarness();
    await harness.orchestrator.setSt456webScreen(St456webScreen.sinTrabajos);
    await pumpEventQueue();
    expect(harness.lastPayload, '20\r\n');

    await harness.tickWith(peso: 1000);
    await harness.tickWith(peso: 1000);
    expect(harness.lastPayload, '20\r\n');

    await harness.tickWith(peso: 1000);
    expect(harness.lastPayload, startsWith('0,1000,1,kg,'));
    expect(harness.latest.st456web.screen, St456webScreen.principal);
  });

  group('comandos CTR', () {
    test('llegan escapados como los entrega el datasource y responden',
        () async {
      final Harness harness = await _st456webHarness();

      await harness.receive(r'CTR,elegirReceta\r\n');
      expect(harness.lastPayload, '8,Vacas Lecheras,1500\r\n');
      expect(harness.latest.st456web.screen, St456webScreen.elegirReceta);
      expect(harness.lastLog, contains('8 - Elegir receta'));
    });

    test('el operario conserva mayúsculas y espacios', () async {
      final Harness harness = await _st456webHarness();
      await harness.receive(r'CTR,cargaManual\r\n');
      await harness.tickWith(peso: 1000);
      await harness.receive(r'CTR,acum,Juan\sPerez\r\n');

      expect(harness.latest.st456web.operario, 'Juan Perez');
      expect(harness.lastLog, contains('operario Juan Perez'));
    });

    test('con otro protocolo activo se ignoran y no se notifica nada',
        () async {
      final Harness harness = await newHarness();
      await pumpEventQueue();
      final int enviados = harness.payloads.length;

      await harness.receive(r'CTR,elegirReceta\r\n');

      expect(harness.payloads, hasLength(enviados));
      expect(harness.latest.st456web.screen, St456webScreen.principal);
      expect(harness.lastLog, contains('"Remoto ST456web"'));
    });

    test('con el ST567 activo los procesa el ST567, no el ST456web', () async {
      final Harness harness = await newHarness();
      await harness.orchestrator.setSendProtocol(SendProtocol.st567);
      await harness.receive(r'CTR,elegirReceta\r\n');

      expect(harness.lastPayload, startsWith('60,'));
      expect(harness.latest.st456web.screen, St456webScreen.principal);
    });

    test('en una pantalla de carga la UI ve lo que falta, y al salir vuelve '
        'el peso de la balanza', () async {
      final Harness harness = await _st456webHarness();
      await harness.receive('CTR,elegirReceta\r\n');
      await harness.receive('CTR,start,1500\r\n');

      await harness.tickWith(peso: 1000);
      expect(harness.lastPayload, '1,30,30,600,Maiz,0,0,0\r\n');
      expect(harness.pesoEmitido, 570);

      // El envío inmediato del ESC no puede tomar el 570 como peso de la
      // balanza.
      await harness.receive('CTR,esc\r\n');
      expect(harness.lastPayload, startsWith('0,1000,1,kg,'));
      expect(harness.pesoEmitido, 1000);
    });
  });

  test('las opciones se guardan aunque el protocolo activo sea otro',
      () async {
    final Harness harness = await newHarness();
    await harness.orchestrator.setSt456webOptions(
      const St456webOptions(sinTrabajos: true),
    );
    await harness.orchestrator.setSendProtocol(SendProtocol.st456web);
    await harness.receive('CTR,elegirTrabajo\r\n');

    expect(harness.lastPayload, '20\r\n');
  });

  test('salir del protocolo vuelve a la pantalla principal', () async {
    final Harness harness = await _st456webHarness();
    await harness.orchestrator.setSt456webScreen(St456webScreen.trabajos);
    await harness.orchestrator.setSendProtocol(SendProtocol.jaguarBle);
    await harness.orchestrator.setSendProtocol(SendProtocol.st456web);
    await pumpEventQueue();

    expect(harness.lastPayload, startsWith('0,1000,'));
  });
}
