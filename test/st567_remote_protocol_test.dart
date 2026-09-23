import 'package:flutter_test/flutter_test.dart';
import 'package:test_jaguar/core/constants/payload_framing.dart';
import 'package:test_jaguar/domain/value_objects/send_protocol.dart';
import 'package:test_jaguar/protocols/st567/st567_screen.dart';

import 'support/orchestrator_harness.dart';

/// Harness en Remoto ST567 con [peso] kg como último peso emitido.
Future<Harness> _st567Harness({int peso = 1000}) async {
  final Harness harness = await newHarness();
  await harness.tickWith(peso: peso);
  await harness.orchestrator.setSendProtocol(SendProtocol.st567);
  await pumpEventQueue();
  return harness;
}

void main() {
  test('al activarlo notifica la pantalla principal con el peso vigente',
      () async {
    final Harness harness = await _st567Harness();

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
    final Harness harness = await _st567Harness();

    // El primer tick del modo no tiene con qué comparar: cuenta como estable.
    await harness.tickWith(peso: 1000);
    expect(harness.lastPayload, startsWith('0,1000,1,kg,'));

    await harness.tickWith(peso: 1200);
    expect(harness.lastPayload, startsWith('0,1200,0,kg,'));
    expect(harness.pesoEmitido, 1200);

    await harness.tickWith(peso: 1200);
    expect(harness.lastPayload, startsWith('0,1200,1,kg,'));
  });

  test('elegir una pantalla desde la UI la notifica y la publica', () async {
    final Harness harness = await _st567Harness();

    await harness.orchestrator.setSt567Screen(St567Screen.cambioOperario);
    await pumpEventQueue();

    expect(harness.lastPayload, '42,3,Dario,1234,Estevan,0000,Claudio,4321\r\n');
    expect(harness.latest.st567.screen, St567Screen.cambioOperario);
    expect(harness.lastLog, contains('42 - Cambio de operario'));
  });

  test('con otro protocolo activo la pantalla cambia pero no se notifica',
      () async {
    final Harness harness = await newHarness();
    await pumpEventQueue();
    final int enviados = harness.payloads.length;

    await harness.orchestrator.setSt567Screen(St567Screen.trabajos);
    await pumpEventQueue();

    expect(harness.payloads, hasLength(enviados));
    expect(harness.latest.st567.screen, St567Screen.trabajos);
  });

  test('un popup se cierra solo con los ticks', () async {
    final Harness harness = await _st567Harness();
    await harness.orchestrator.setSt567Screen(St567Screen.sinTrabajos);
    await pumpEventQueue();
    expect(harness.lastPayload, '20\r\n');

    await harness.tickWith(peso: 1000);
    await harness.tickWith(peso: 1000);
    expect(harness.lastPayload, '20\r\n');

    await harness.tickWith(peso: 1000);
    expect(harness.lastPayload, startsWith('0,1000,1,kg,'));
    expect(harness.latest.st567.screen, St567Screen.principal);
  });

  test('salir del protocolo vuelve a la pantalla principal', () async {
    final Harness harness = await _st567Harness();
    await harness.orchestrator.setSt567Screen(St567Screen.trabajos);
    await harness.orchestrator.setSendProtocol(SendProtocol.jaguarBle);
    await harness.orchestrator.setSendProtocol(SendProtocol.st567);
    await pumpEventQueue();

    expect(harness.lastPayload, startsWith('0,1000,'));
  });
}
