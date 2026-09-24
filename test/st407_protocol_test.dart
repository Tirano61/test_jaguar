import 'package:flutter_test/flutter_test.dart';
import 'package:test_jaguar/domain/entities/scale_measurement.dart';
import 'package:test_jaguar/protocols/st407_remote/st407_remote_protocol.dart';
import 'package:test_jaguar/protocols/st407_remote/st407_screen.dart';

/// El módulo ST407 se prueba solo. Las pruebas de integración (cómo interactúa
/// con el cambio de protocolo, el tick del motor y `AT+CERO`) siguen en
/// `st407_remote_protocol_test.dart`.
void main() {
  ScaleMeasurement conPeso(int peso) =>
      ScaleMeasurement.baseline.copyWith(peso: peso);

  St407RemoteProtocol enPantalla(St407Screen screen, {int peso = 1000}) {
    final St407RemoteProtocol p = St407RemoteProtocol(
      now: () => DateTime(2026, 9, 15, 14, 30),
    );
    p.selectScreen(screen);
    p.seedScreenState(currentPeso: peso);
    return p;
  }

  test('el reloj inyectado fija la cadena de la pantalla principal', () {
    final St407RemoteProtocol p = enPantalla(St407Screen.main);

    expect(
      p.encodePayload(conPeso(1000)),
      '100,1000,0,0,1,,,15-09-26 14:30\r\n',
    );
  });

  test('selectScreen avisa si la pantalla no cambió', () {
    final St407RemoteProtocol p = enPantalla(St407Screen.main);

    expect(p.selectScreen(St407Screen.main), isFalse);
    expect(p.selectScreen(St407Screen.mixing), isTrue);
  });

  test('la carga baja de a 1 kg con "kg a cargar" fijo', () {
    final St407RemoteProtocol p = enPantalla(St407Screen.loadingRecipe);

    expect(p.encodePayload(conPeso(1000)), '101,1000,0,1000,Maiz\r\n');

    // El peso que trae el motor es irrelevante: lo anima el protocolo.
    expect(
      p.encodePayload(p.advanceLoading(conPeso(9999))),
      '101,999,1,1000,Maiz\r\n',
    );
    expect(
      p.encodePayload(p.advanceLoading(conPeso(9999))),
      '101,998,2,1000,Maiz\r\n',
    );
  });

  test('la cuenta de mezclado avanza en el propio formateador', () {
    final St407RemoteProtocol p = enPantalla(St407Screen.mixing);

    // Cada envío consume un segundo: no hay timer, el reloj lo mueve el envío.
    expect(p.encodePayload(conPeso(1000)), '106,4,30\r\n');
    expect(p.encodePayload(conPeso(1000)), '106,4,29\r\n');
    expect(p.encodePayload(conPeso(1000)), '106,4,28\r\n');
  });

  test('la cuenta de mezclado se queda en 0:00', () {
    final St407RemoteProtocol p = enPantalla(St407Screen.mixing);
    for (int i = 0; i < 270; i++) {
      p.encodePayload(conPeso(1000));
    }

    expect(p.encodePayload(conPeso(1000)), '106,0,00\r\n');
    expect(p.encodePayload(conPeso(1000)), '106,0,00\r\n');
  });

  test('resetRunState re-siembra la carga con el peso del próximo envío', () {
    final St407RemoteProtocol p = enPantalla(St407Screen.loadingRecipe);
    p.advanceLoading(conPeso(1000));

    p.resetRunState();

    // Sin contadores sembrados, el primer envío los toma del peso que llega.
    expect(p.encodePayload(conPeso(4000)), '101,4000,0,4000,Maiz\r\n');
  });

  test('isLoadingScreen distingue las pantallas que animan el peso', () {
    expect(enPantalla(St407Screen.loadingRecipe).isLoadingScreen, isTrue);
    expect(enPantalla(St407Screen.loadingManual).isLoadingScreen, isTrue);
    expect(enPantalla(St407Screen.mixing).isLoadingScreen, isFalse);
    expect(enPantalla(St407Screen.main).isLoadingScreen, isFalse);
  });
}
