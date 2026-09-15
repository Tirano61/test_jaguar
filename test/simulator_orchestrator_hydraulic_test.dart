import 'package:flutter_test/flutter_test.dart';
import 'package:test_jaguar/domain/value_objects/send_protocol.dart';

import 'support/orchestrator_harness.dart';

/// Simulador en modo Hidráulico BLE con [peso] kg en la tolva y la simulación
/// detenida (que es como queda al abrir la app).
Future<Harness> _hydraulicHarness({required int peso}) async {
  final Harness harness = await newHarness();
  await harness.orchestrator.setSendProtocol(SendProtocol.hidraulicoBle);
  await harness.orchestrator.setHydraulicPeso(peso);
  // watchStatus() es un broadcast stream: entrega en microtask, así que el
  // harness no puede devolverse con emisiones todavía en vuelo.
  await pumpEventQueue();
  return harness;
}

void main() {
  test('el peso editado a mano viaja en el JSON sin esperar un tick', () async {
    final Harness harness = await _hydraulicHarness(peso: 1500);

    expect(harness.pesoEnJson, 1500);
    expect(harness.pesoEmitido, 1500);
  });

  test('AT+INICIO por todo el peso de la tolva inicia la descarga', () async {
    final Harness harness = await _hydraulicHarness(peso: 1500);

    await harness.receive('AT+INICIO=1500,300,100,3,2\r\n');

    expect(harness.hydraulicActive, isTrue);
    expect(harness.hydraulicInitialPeso, 1500.0);
    expect(harness.hydraulicTargetPeso, 0.0);
  });

  test('AT+INICIO por más kg de los cargados se rechaza', () async {
    final Harness harness = await _hydraulicHarness(peso: 1500);

    await harness.receive('AT+INICIO=1501,300,100,3,2\r\n');

    expect(harness.hydraulicActive, isFalse);
    expect(harness.lastLog, contains('parámetros inválidos'));
  });

  test('AT+INICIO con kgDescarga <= kgTubo se rechaza', () async {
    final Harness harness = await _hydraulicHarness(peso: 1500);

    await harness.receive('AT+INICIO=300,300,100,3,2\r\n');

    expect(harness.hydraulicActive, isFalse);
    expect(harness.lastLog, contains('parámetros inválidos'));
  });

  test('la descarga total vacía la tolva y cierra con AT+GUARDAR', () async {
    final Harness harness = await _hydraulicHarness(peso: 1500);
    await harness.receive('AT+INICIO=1500,300,100,3,2\r\n');

    // Velocidad 2 (normal) baja 50 kg por tick: 1500 kg son 30 ticks.
    for (int i = 0; i < 40 && harness.hydraulicActive; i++) {
      await harness.tick();
    }

    expect(harness.hydraulicActive, isFalse);
    expect(harness.pesoEnJson, 0);
    expect(harness.lastPayload, 'AT+GUARDAR\r\n');
  });

  test('la descarga en modo 2 cierra con AT+GUARDARDOS', () async {
    final Harness harness = await _hydraulicHarness(peso: 1500);
    await harness.receive('AT+INICIO=1500,300,100,2,2\r\n');

    for (int i = 0; i < 40 && harness.hydraulicActive; i++) {
      await harness.tick();
    }

    expect(harness.lastPayload, 'AT+GUARDARDOS\r\n');
  });

  test('sin ticks del motor la descarga aceptada no mueve el peso', () async {
    final Harness harness = await _hydraulicHarness(peso: 1500);

    await harness.receive('AT+INICIO=1500,300,100,3,2\r\n');

    expect(harness.hydraulicActive, isTrue);
    expect(harness.pesoEnJson, 1500);
  });

  test('el guardado se notifica DESPUÉS del payload con el peso final',
      () async {
    final Harness harness = await _hydraulicHarness(peso: 1500);
    await harness.receive('AT+INICIO=1500,300,100,3,2\r\n');

    for (int i = 0; i < 40 && harness.hydraulicActive; i++) {
      await harness.tick();
    }

    // El orden importa: la app tiene que ver la tolva en 0 antes de que le
    // pidan guardar. Mirar sólo `.last` dejaría pasar el orden invertido.
    final List<String> ultimosDos =
        harness.payloads.sublist(harness.payloads.length - 2);
    expect(ultimosDos.first, contains('"peso":0'));
    expect(ultimosDos.last, 'AT+GUARDAR\r\n');
  });

  test('AT+MOVIMIENTO se ignora mientras hay una descarga en curso', () async {
    final Harness harness = await _hydraulicHarness(peso: 1500);
    await harness.receive('AT+INICIO=1500,300,100,3,2\r\n');

    await harness.receive('AT+MOVIMIENTO=2\r\n');

    expect(
      harness.lastLog,
      'AT+MOVIMIENTO recibido: Cerrar tubo (tipo=2) -> ignorado, hay una '
      'descarga en curso',
    );
  });

  test('AT+DETENER pausa y AT+REANUDAR continúa desde el mismo peso', () async {
    final Harness harness = await _hydraulicHarness(peso: 1000);
    await harness.receive('AT+INICIO=1000,300,100,1,2\r\n');
    await harness.tick(); // 1000 -> 950

    await harness.receive('AT+DETENER\r\n');
    expect(harness.hydraulicPaused, isTrue);
    expect(harness.pesoEnJson, 950);

    // Pausada, el tick no mueve el peso.
    await harness.tick();
    expect(harness.pesoEnJson, 950);

    await harness.receive('AT+REANUDAR\r\n');
    expect(harness.hydraulicPaused, isFalse);
    await harness.tick();
    expect(harness.pesoEnJson, 900);
  });

  test('AT+FINALIZAR corta la descarga sin notificar guardado', () async {
    final Harness harness = await _hydraulicHarness(peso: 1000);
    await harness.receive('AT+INICIO=1000,300,100,1,2\r\n');
    await harness.tick(); // 1000 -> 950

    await harness.receive('AT+FINALIZAR\r\n');

    expect(harness.hydraulicActive, isFalse);
    expect(harness.pesoEnJson, 950);
    expect(harness.lastLog, contains('no se envía AT+GUARDAR'));
    expect(harness.payloads, isNot(contains('AT+GUARDAR\r\n')));
  });
}
