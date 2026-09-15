import 'package:flutter_test/flutter_test.dart';
import 'package:test_jaguar/domain/value_objects/send_protocol.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_actuators.dart';

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

/// Manda `AT+INICIO` y deja que el tubo termine de abrir, que es cuando
/// realmente arranca la descarga.
Future<void> _iniciarYAbrirTubo(Harness harness, String comando) async {
  await harness.receive(comando);
  await harness.actuatorSeconds(HydraulicTube.dischargeTravel.inSeconds);
}

void main() {
  test('el peso editado a mano viaja en el JSON sin esperar un tick', () async {
    final Harness harness = await _hydraulicHarness(peso: 1500);

    expect(harness.pesoEnJson, 1500);
    expect(harness.pesoEmitido, 1500);
  });

  test('el JSON del modo lleva tubo y gillo', () async {
    final Harness harness = await _hydraulicHarness(peso: 1500);

    expect(harness.jsonEnviado['tubo'], TubeState.cerrado);
    expect(harness.jsonEnviado['gillo'], 0);
  });

  group('ciclo de descarga', () {
    test('AT+INICIO abre el tubo y recién ahí arranca la descarga', () async {
      final Harness harness = await _hydraulicHarness(peso: 1500);

      await harness.receive('AT+INICIO=1500,300,100,3,2\r\n');
      expect(harness.jsonEnviado['tubo'], TubeState.abriendo);
      expect(harness.hydraulicActive, isFalse, reason: 'todavía no descarga');

      // El tubo abre con su propio reloj, aunque la simulación esté detenida.
      await harness.actuatorSeconds(6);
      expect(harness.jsonEnviado['tubo'], TubeState.abierto);
      expect(harness.hydraulicActive, isTrue);
      expect(harness.hydraulicInitialPeso, 1500.0);
      expect(harness.hydraulicTargetPeso, 0.0);
    });

    test('la guillotina abre a 25% mientras el tubo se abre', () async {
      final Harness harness = await _hydraulicHarness(peso: 1500);

      await harness.receive('AT+INICIO=1500,300,100,3,2\r\n');
      await harness.actuatorSeconds(4);

      expect(
        harness.jsonEnviado['gillo'],
        HydraulicGuillotine.dischargeOpenPercent,
      );
    });

    test('la descarga total vacía la tolva y cierra con AT+GUARDAR', () async {
      final Harness harness = await _hydraulicHarness(peso: 1500);
      await _iniciarYAbrirTubo(harness, 'AT+INICIO=1500,300,100,3,2\r\n');

      // Velocidad 2 (normal) baja 50 kg por tick: 1500 kg son 30 ticks.
      for (int i = 0; i < 40 && harness.hydraulicActive; i++) {
        await harness.tick();
      }
      expect(harness.pesoEnJson, 0);

      // El guardado sale en el primer paso del reloj de actuadores posterior.
      await harness.actuatorSeconds(1);
      expect(harness.lastPayload, 'AT+GUARDAR\r\n');
    });

    test('la descarga en modo 2 cierra con AT+GUARDARDOS', () async {
      final Harness harness = await _hydraulicHarness(peso: 1500);
      await _iniciarYAbrirTubo(harness, 'AT+INICIO=1500,300,100,2,2\r\n');

      for (int i = 0; i < 40 && harness.hydraulicActive; i++) {
        await harness.tick();
      }
      await harness.actuatorSeconds(1);

      expect(harness.lastPayload, 'AT+GUARDARDOS\r\n');
    });

    test('el guardado se notifica DESPUÉS del payload con el peso final',
        () async {
      final Harness harness = await _hydraulicHarness(peso: 1500);
      await _iniciarYAbrirTubo(harness, 'AT+INICIO=1500,300,100,3,2\r\n');

      for (int i = 0; i < 40 && harness.hydraulicActive; i++) {
        await harness.tick();
      }
      await harness.actuatorSeconds(1);

      // El orden importa: la app tiene que ver la tolva en 0 antes de que le
      // pidan guardar. Mirar sólo `.last` dejaría pasar el orden invertido.
      final List<String> ultimosDos =
          harness.payloads.sublist(harness.payloads.length - 2);
      expect(ultimosDos.first, contains('"peso":0'));
      expect(ultimosDos.last, 'AT+GUARDAR\r\n');
    });

    test('al terminar cierra el tubo y la guillotina', () async {
      final Harness harness = await _hydraulicHarness(peso: 100);
      await _iniciarYAbrirTubo(harness, 'AT+INICIO=100,50,10,1,2\r\n');

      for (int i = 0; i < 10 && harness.hydraulicActive; i++) {
        await harness.tick();
      }
      await harness.actuatorSeconds(1);
      expect(harness.jsonEnviado['tubo'], TubeState.cerrando);

      await harness.actuatorSeconds(6);
      expect(harness.jsonEnviado['tubo'], TubeState.cerrado);
      expect(harness.jsonEnviado['gillo'], 0);
    });

    test('sin ticks del motor la descarga aceptada no mueve el peso', () async {
      final Harness harness = await _hydraulicHarness(peso: 1500);

      await _iniciarYAbrirTubo(harness, 'AT+INICIO=1500,300,100,3,2\r\n');

      expect(harness.hydraulicActive, isTrue);
      expect(harness.pesoEnJson, 1500);
    });
  });

  group('validación de AT+INICIO', () {
    test('por más kg de los cargados se rechaza', () async {
      final Harness harness = await _hydraulicHarness(peso: 1500);

      await harness.receive('AT+INICIO=1501,300,100,3,2\r\n');

      expect(harness.hydraulicActive, isFalse);
      expect(harness.jsonEnviado['tubo'], TubeState.cerrado);
      expect(harness.lastLog, contains('parámetros inválidos'));
    });

    test('con kgDescarga <= kgTubo se rechaza', () async {
      final Harness harness = await _hydraulicHarness(peso: 1500);

      await harness.receive('AT+INICIO=300,300,100,3,2\r\n');

      expect(harness.hydraulicActive, isFalse);
      expect(harness.lastLog, contains('parámetros inválidos'));
    });
  });

  group('comandos durante la corrida', () {
    test('AT+MOVIMIENTO se ignora mientras hay una descarga en curso',
        () async {
      final Harness harness = await _hydraulicHarness(peso: 1500);
      await _iniciarYAbrirTubo(harness, 'AT+INICIO=1500,300,100,3,2\r\n');

      await harness.receive('AT+MOVIMIENTO=2\r\n');

      expect(
        harness.lastLog,
        'AT+MOVIMIENTO recibido: Cerrar tubo (tipo=2) -> ignorado, hay una '
        'descarga en curso',
      );
      expect(harness.jsonEnviado['tubo'], TubeState.abierto);
    });

    test('AT+DETENER pausa y AT+REANUDAR continúa desde el mismo peso',
        () async {
      final Harness harness = await _hydraulicHarness(peso: 1000);
      await _iniciarYAbrirTubo(harness, 'AT+INICIO=1000,300,100,1,2\r\n');
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

    test('AT+FINALIZAR corta sin guardar, cierra la guillotina y deja el tubo',
        () async {
      final Harness harness = await _hydraulicHarness(peso: 1000);
      await _iniciarYAbrirTubo(harness, 'AT+INICIO=1000,300,100,1,2\r\n');
      await harness.tick(); // 1000 -> 950

      await harness.receive('AT+FINALIZAR\r\n');

      expect(harness.hydraulicActive, isFalse);
      expect(harness.pesoEnJson, 950);
      expect(harness.lastLog, contains('no se envía AT+GUARDAR'));
      expect(harness.payloads, isNot(contains('AT+GUARDAR\r\n')));

      // El tubo queda abierto; la guillotina sí se cierra.
      expect(harness.jsonEnviado['tubo'], TubeState.abierto);
      await harness.actuatorSeconds(HydraulicGuillotine.travel.inSeconds);
      expect(harness.jsonEnviado['gillo'], 0);
    });
  });

  group('movimiento manual', () {
    test('el tubo recorre en 15 s y se puede invertir a mitad de camino',
        () async {
      final Harness harness = await _hydraulicHarness(peso: 1000);

      await harness.receive('AT+MOVIMIENTO=1\r\n');
      expect(harness.jsonEnviado['tubo'], TubeState.abriendo);

      await harness.actuatorSeconds(6);
      await harness.receive('AT+MOVIMIENTO=2\r\n');
      expect(harness.jsonEnviado['tubo'], TubeState.cerrando);

      // Vuelve los mismos 6 s que llevaba recorridos, no los 15 enteros.
      await harness.actuatorSeconds(5);
      expect(harness.jsonEnviado['tubo'], TubeState.cerrando);
      await harness.actuatorSeconds(1);
      expect(harness.jsonEnviado['tubo'], TubeState.cerrado);
    });

    test('la guillotina se mueve a mano y viaja en el JSON', () async {
      final Harness harness = await _hydraulicHarness(peso: 1000);

      await harness.receive('AT+MOVIMIENTO=3\r\n'); // abrir guillotina
      await harness.actuatorSeconds(HydraulicGuillotine.travel.inSeconds);

      expect(harness.jsonEnviado['gillo'], 100);
    });
  });
}
