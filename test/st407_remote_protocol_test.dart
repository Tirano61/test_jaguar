import 'package:flutter_test/flutter_test.dart';
import 'package:test_jaguar/core/constants/payload_framing.dart';
import 'package:test_jaguar/domain/value_objects/send_protocol.dart';
import 'package:test_jaguar/protocols/st407_remote/st407_screen.dart';

import 'support/orchestrator_harness.dart';

/// Harness en Remoto ST407 con [peso] kg como último peso emitido, que es de
/// donde las pantallas de carga toman su "kg a cargar".
Future<Harness> _st407Harness({int peso = 1000}) async {
  final Harness harness = await newHarness();
  await harness.tickWith(peso: peso);
  await harness.orchestrator.setSendProtocol(SendProtocol.st407Remote);
  await pumpEventQueue();
  return harness;
}

Future<String> _payloadDePantalla(Harness harness, St407Screen screen) async {
  await harness.orchestrator.setSt407Screen(screen);
  await pumpEventQueue();
  return harness.lastPayload;
}

void main() {
  group('cadenas por pantalla', () {
    test('la pantalla principal lleva peso y fecha-hora', () async {
      final Harness harness = await _st407Harness();

      // Ya viene emitida por el cambio de protocolo.
      expect(
        harness.lastPayload,
        matches(RegExp(r'^100,1000,0,0,1,,,\d{2}-\d{2}-\d{2} \d{2}:\d{2}\r\n$')),
      );
    });

    test('las 6 pantallas que arma el DTO tienen su formato fijo', () async {
      final Harness harness = await _st407Harness();

      expect(
        await _payloadDePantalla(harness, St407Screen.unloadingGuide),
        '103,1000,0,150,M1\r\n',
      );
      expect(
        await _payloadDePantalla(harness, St407Screen.unloadingManual),
        '104,1000,20,250,7\r\n',
      );
      expect(
        await _payloadDePantalla(harness, St407Screen.chooseRecipe),
        '108,1,0,1200\r\n',
      );
      expect(
        await _payloadDePantalla(harness, St407Screen.chooseAutonomous),
        '109,1,ADGF,15/05/2017,17/05/2017,Receta1,Guia1\r\n',
      );
      expect(
        await _payloadDePantalla(harness, St407Screen.chooseGuide),
        '110,1,DescNov\r\n',
      );
      expect(
        await _payloadDePantalla(harness, St407Screen.main),
        matches(RegExp(r'^100,1000,')),
      );
    });

    test('las 3 pantallas con animación no pasan por el DTO', () async {
      final Harness harness = await _st407Harness();

      // El DTO diría '101,1000,20,117,Maiz'; el simulador arma la cadena a mano
      // para poder mover "peso actual" y "parcial" tick a tick.
      expect(
        await _payloadDePantalla(harness, St407Screen.loadingRecipe),
        '101,1000,0,1000,Maiz\r\n',
      );
      // El DTO diría '102,1000,20,1200,1'.
      expect(
        await _payloadDePantalla(harness, St407Screen.loadingManual),
        '102,1000,0,1000,1\r\n',
      );
      // El DTO diría '106,1,23'.
      expect(
        await _payloadDePantalla(harness, St407Screen.mixing),
        '106,4,30\r\n',
      );
    });
  });

  group('automatismo de carga', () {
    test('el peso baja de a 1 kg y el parcial sube, ignorando el motor',
        () async {
      final Harness harness = await _st407Harness();
      await _payloadDePantalla(harness, St407Screen.loadingRecipe);

      // El peso que trae el motor es irrelevante en estas pantallas.
      await harness.tickWith(peso: 5000);
      expect(harness.lastPayload, '101,999,1,1000,Maiz\r\n');

      await harness.tickWith(peso: 5000);
      expect(harness.lastPayload, '101,998,2,1000,Maiz\r\n');
    });

    test('volver a la pantalla de carga vuelve a tomar el peso actual',
        () async {
      final Harness harness = await _st407Harness();
      await _payloadDePantalla(harness, St407Screen.loadingRecipe);
      await harness.tickWith(peso: 5000);
      await harness.tickWith(peso: 5000);
      expect(harness.lastPayload, '101,998,2,1000,Maiz\r\n');

      // Salir y volver reinicia "kg a cargar" con el peso vigente.
      await _payloadDePantalla(harness, St407Screen.main);
      expect(
        await _payloadDePantalla(harness, St407Screen.loadingRecipe),
        '101,998,0,998,Maiz\r\n',
      );
    });
  });

  group('cuenta regresiva de mezclado', () {
    test('baja un segundo por envío y se queda en 0:00', () async {
      final Harness harness = await _st407Harness();
      expect(
        await _payloadDePantalla(harness, St407Screen.mixing),
        '106,4,30\r\n',
      );

      await harness.tickWith(peso: 1000);
      expect(harness.lastPayload, '106,4,29\r\n');
      await harness.tickWith(peso: 1000);
      expect(harness.lastPayload, '106,4,28\r\n');

      // Los segundos van con cero a la izquierda, los minutos no.
      for (int i = 0; i < 300; i++) {
        await harness.tickWith(peso: 1000);
      }
      expect(harness.lastPayload, '106,0,00\r\n');
      await harness.tickWith(peso: 1000);
      expect(harness.lastPayload, '106,0,00\r\n');
    });

    test('AT+CERO le roba un segundo a la cuenta regresiva', () async {
      final Harness harness = await _st407Harness();
      await _payloadDePantalla(harness, St407Screen.mixing);

      // AT+CERO fuera del modo manual emite una medición efímera en cero, y
      // ese envío pasa por el mismo formateador que decrementa el reloj. Sin
      // el comando, el próximo tick daría 106,4,29.
      await harness.receive('AT+CERO\r\n');
      expect(harness.lastPayload, '106,4,29\r\n');

      await harness.tickWith(peso: 1000);
      expect(harness.lastPayload, '106,4,28\r\n');
    });
  });

  test('cambiar de protocolo pide el perfil GATT y el framing correctos',
      () async {
    final Harness harness = await _st407Harness();

    expect(harness.ble.uuidUpdates, hasLength(1));
    expect(harness.ble.uuidUpdates.single.uuids.serviceUuid,
        '0000ABF3-0000-1000-8000-00805F9B34FB');
    expect(harness.ble.uuidUpdates.single.framing,
        PayloadFraming.fiveByteHeader);

    await harness.orchestrator.setSendProtocol(SendProtocol.jaguarBle);
    await pumpEventQueue();
    expect(harness.ble.uuidUpdates, hasLength(2));
    expect(harness.ble.uuidUpdates.last.uuids.serviceUuid,
        '0000ABF0-0000-1000-8000-00805F9B34FB');
    expect(harness.ble.uuidUpdates.last.framing, PayloadFraming.plain);
  });

  test('salir del protocolo limpia los contadores de carga', () async {
    final Harness harness = await _st407Harness();
    await _payloadDePantalla(harness, St407Screen.loadingRecipe);
    await harness.tickWith(peso: 5000);
    expect(harness.lastPayload, '101,999,1,1000,Maiz\r\n');

    await harness.orchestrator.setSendProtocol(SendProtocol.jaguarBle);
    await harness.orchestrator.setSendProtocol(SendProtocol.st407Remote);
    await pumpEventQueue();

    // La pantalla sigue siendo la de carga, pero el "kg a cargar" ya no
    // arrastra el 1000 anterior: se vuelve a sembrar con el peso vigente (999)
    // en el envío inmediato del cambio de protocolo, no en el próximo tick.
    // Ese re-sembrado lo hace el bloque de init duplicado que vive dentro del
    // formateador de payload.
    expect(harness.lastPayload, '101,999,0,999,Maiz\r\n');

    await harness.tickWith(peso: 5000);
    expect(harness.lastPayload, '101,998,1,999,Maiz\r\n');
  });
}
