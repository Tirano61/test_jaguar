import 'package:flutter_test/flutter_test.dart';
import 'package:test_jaguar/core/constants/ble_constants.dart';
import 'package:test_jaguar/core/constants/payload_framing.dart';
import 'package:test_jaguar/domain/entities/scale_measurement.dart';
import 'package:test_jaguar/protocols/st567/st567_protocol.dart';
import 'package:test_jaguar/protocols/st567/st567_screen.dart';

final DateTime _ahora = DateTime(2026, 9, 14, 10, 32);

St567Protocol _protocolo() => St567Protocol(now: () => _ahora);

ScaleMeasurement _peso(int peso) =>
    ScaleMeasurement.baseline.copyWith(peso: peso);

void _sinLog(String _) {}

void main() {
  test('usa el perfil GATT y el framing del ST407', () {
    final St567Protocol protocolo = _protocolo();
    expect(protocolo.bleUuids, same(BleConstants.remotoAbf3));
    expect(protocolo.framing, PayloadFraming.fiveByteHeader);
  });

  group('pantalla principal', () {
    test('lleva peso, estabilidad, unidad, fecha y levelLock', () {
      expect(
        _protocolo().encodePayload(_peso(1250)),
        '0,1250,1,kg,,14/09/2026 10:32,0\r\n',
      );
    });

    test('la balanza está estable si el peso no cambió desde el tick anterior',
        () {
      final St567Protocol protocolo = _protocolo();

      protocolo.advance(_peso(1000), log: _sinLog);
      protocolo.advance(_peso(1248), log: _sinLog);
      expect(protocolo.encodePayload(_peso(1248)),
          startsWith('0,1248,0,kg,'));

      protocolo.advance(_peso(1248), log: _sinLog);
      expect(protocolo.encodePayload(_peso(1248)),
          startsWith('0,1248,1,kg,'));
    });
  });

  group('listas', () {
    test('las recetas se mandan de a una página, con y sin preset', () {
      final St567Protocol protocolo = _protocolo();

      protocolo.goTo(St567Screen.elegirReceta);
      expect(
        protocolo.encodePayload(_peso(0)),
        '30,5,1,Vacas Lecheras,2,Terneros,3,Engorde,4,Vaquillonas,5,Secas\r\n',
      );

      protocolo.goTo(St567Screen.elegirRecetaPreset);
      expect(
        protocolo.encodePayload(_peso(0)),
        '60,5,1,Vacas Lecheras,1500,2,Terneros,800,3,Engorde,2000,'
        '4,Vaquillonas,1000,5,Secas,600\r\n',
      );
    });

    test('ingredientes, trabajos y operarios', () {
      final St567Protocol protocolo = _protocolo();

      protocolo.goTo(St567Screen.elegirIngrediente);
      expect(
        protocolo.encodePayload(_peso(0)),
        '32,5,1,Maiz,2,Soja,3,Heno,4,Nucleo,5,Silo\r\n',
      );

      protocolo.goTo(St567Screen.trabajos);
      expect(
        protocolo.encodePayload(_peso(0)),
        '34,5,1,Trabajo Manana,1,2,Trabajo Tarde,0,3,Trabajo Noche,0,'
        '4,Vaquillonas Norte,0,5,Secas Sur,0\r\n',
      );

      protocolo.goTo(St567Screen.cambioOperario);
      expect(
        protocolo.encodePayload(_peso(0)),
        '42,3,Dario,1234,Estevan,0000,Claudio,4321\r\n',
      );
    });
  });

  test('los diálogos y popups van sin campos', () {
    final St567Protocol protocolo = _protocolo();
    for (final St567Screen screen in <St567Screen>[
      St567Screen.loteYCantidad,
      St567Screen.sincronizacionFallida,
      St567Screen.sincronizacionExitosa,
      St567Screen.masCarga,
      St567Screen.reanudarTrabajo,
      St567Screen.sinOperario,
      St567Screen.indicadorOcupado,
    ]) {
      protocolo.goTo(screen);
      expect(protocolo.encodePayload(_peso(0)), '${screen.code}\r\n');
    }
  });

  group('popups', () {
    test('se cierran solos a los tres ticks y vuelven a la principal', () {
      final St567Protocol protocolo = _protocolo();
      final List<String> logs = <String>[];
      protocolo.goTo(St567Screen.sinTrabajos);

      protocolo.advance(_peso(0), log: logs.add);
      protocolo.advance(_peso(0), log: logs.add);
      expect(protocolo.screen, St567Screen.sinTrabajos);

      protocolo.advance(_peso(0), log: logs.add);
      expect(protocolo.screen, St567Screen.principal);
      expect(logs.single, contains('popup 20'));
    });

    test('el de indicador ocupado se queda hasta que lo cambien', () {
      final St567Protocol protocolo = _protocolo();
      protocolo.goTo(St567Screen.indicadorOcupado);
      for (int i = 0; i < 10; i++) {
        protocolo.advance(_peso(0), log: _sinLog);
      }
      expect(protocolo.screen, St567Screen.indicadorOcupado);
    });
  });

  test('goTo a la pantalla vigente no hace nada', () {
    final St567Protocol protocolo = _protocolo();
    expect(protocolo.goTo(St567Screen.principal), isNull);
    expect(protocolo.goTo(St567Screen.trabajos), contains('34 - Trabajos'));
  });

  test('las pantallas no pisan los códigos reservados', () {
    for (final St567Screen screen in St567Screen.values) {
      expect(screen.code, isNot(13), reason: screen.name);
      expect(screen.code, lessThan(100), reason: '${screen.name} es del ST407');
    }
  });
}
