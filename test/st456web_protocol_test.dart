import 'package:flutter_test/flutter_test.dart';
import 'package:test_jaguar/core/constants/ble_constants.dart';
import 'package:test_jaguar/core/constants/payload_framing.dart';
import 'package:test_jaguar/domain/entities/scale_measurement.dart';
import 'package:test_jaguar/protocols/st456web/st456web_catalog.dart';
import 'package:test_jaguar/protocols/st456web/st456web_payload.dart';
import 'package:test_jaguar/protocols/st456web/st456web_protocol.dart';
import 'package:test_jaguar/protocols/st456web/st456web_screen.dart';

final DateTime _ahora = DateTime(2026, 9, 14, 10, 32);

St456webProtocol _protocolo() => St456webProtocol(now: () => _ahora);

ScaleMeasurement _peso(int peso) =>
    ScaleMeasurement.baseline.copyWith(peso: peso);

void _sinLog(String _) {}

St456webPesaje _pesaje(int total, int parcial, int objetivo) => St456webPesaje(
      total: total,
      parcial: parcial,
      objetivo: objetivo,
      lock: false,
      level: false,
      sirena: false,
    );

void main() {
  const St456webCatalog catalogo = St456webCatalog.demo;

  test('usa el perfil GATT y el framing del ST407', () {
    final St456webProtocol protocolo = _protocolo();
    expect(protocolo.bleUuids, same(BleConstants.remotoAbf3));
    expect(protocolo.framing, PayloadFraming.fiveByteHeader);
  });

  test('no usa códigos del ST567 ni los reservados', () {
    for (final St456webScreen s in St456webScreen.values) {
      expect(s.code, isNot(13));
      expect(s.code, lessThan(100));
      expect(<int>[30, 31, 32, 33, 34, 37, 38, 39, 40, 41, 60],
          isNot(contains(s.code)),
          reason: s.label);
    }
  });

  group('pantalla principal', () {
    test('lleva peso, estabilidad, unidad, fecha y levelLock siempre en 0', () {
      expect(
        _protocolo().encodePayload(_peso(1250)),
        '0,1250,1,kg,,14/09/2026 10:32,0\r\n',
      );
    });

    test('la balanza está estable si el peso no cambió desde el tick anterior',
        () {
      final St456webProtocol protocolo = _protocolo();

      protocolo.advance(_peso(1000), log: _sinLog);
      protocolo.advance(_peso(1248), log: _sinLog);
      expect(protocolo.encodePayload(_peso(1248)),
          startsWith('0,1248,0,kg,'));

      protocolo.advance(_peso(1248), log: _sinLog);
      expect(protocolo.encodePayload(_peso(1248)),
          startsWith('0,1248,1,kg,'));
    });
  });

  group('pantallas forzadas desde la UI', () {
    String forzar(St456webScreen screen) {
      final St456webProtocol protocolo = _protocolo();
      protocolo.goTo(screen);
      return protocolo.encodePayload(_peso(0));
    }

    test('8, 9 y 10 muestran el primer ítem de cada lista', () {
      expect(forzar(St456webScreen.elegirReceta), '8,Vacas Lecheras,1500\r\n');
      expect(
        forzar(St456webScreen.elegirAutonomo),
        '9,1,Autonomo Norte,01/09/2026,30/09/2026,Vacas Lecheras,'
        'Corrales A\r\n',
      );
      expect(forzar(St456webScreen.elegirGuia), '10,1,Corrales A\r\n');
    });

    test('la 11 manda hasta 6 trabajos con 5 campos cada uno', () {
      expect(
        forzar(St456webScreen.trabajos),
        '11,6,'
        '1,1,RECE,Carga Manana,1,'
        '2,2,GUIA,Descarga Corrales A,0,'
        '3,3,AUTO,Autonomo Norte,0,'
        '4,4,RECE,Terneros Tarde,0,'
        '5,5,GUIA,Descarga Lote Norte,0,'
        '6,6,AUTO,Autonomo Sur,0\r\n',
      );
    });

    test('12, 18, 19 y 42 llevan sus datos', () {
      expect(forzar(St456webScreen.usarParcial), '12,1500\r\n');
      expect(
        forzar(St456webScreen.detalle),
        '18,1,Vacas Lecheras,,2,3,0,Maiz,600,Soja,300,Heno,600\r\n',
      );
      expect(forzar(St456webScreen.sincronizando), '19,0\r\n');
      expect(forzar(St456webScreen.cambioOperario),
          '42,3,Dario,1234,Estevan,0000,Claudio,4321\r\n');
    });

    test('los diálogos y popups van sin campos', () {
      for (final St456webScreen s in <St456webScreen>[
        St456webScreen.descargaPendiente,
        St456webScreen.cargaODescarga,
        St456webScreen.sinOperario,
        St456webScreen.cargaRealizada,
        St456webScreen.sinTrabajos,
        St456webScreen.sincronizacionFallida,
        St456webScreen.sincronizacionExitosa,
        St456webScreen.operarioNoEncontrado,
        St456webScreen.claveIncorrecta,
        St456webScreen.indicadorOcupado,
      ]) {
        expect(forzar(s), '${s.code}\r\n');
      }
    });

    test('las de peso no se pueden forzar', () {
      for (final St456webScreen s in <St456webScreen>[
        St456webScreen.cargaReceta,
        St456webScreen.cargaManual,
        St456webScreen.descargaGuia,
        St456webScreen.descargaManual,
        St456webScreen.mezclando,
      ]) {
        expect(St456webScreen.forzables, isNot(contains(s)));
      }
    });

    test('elegir la pantalla vigente no hace nada', () {
      expect(_protocolo().goTo(St456webScreen.principal), isNull);
    });
  });

  group('popups', () {
    test('se cierran solos y vuelven a la principal', () {
      final St456webProtocol protocolo = _protocolo();
      final List<String> logs = <String>[];
      protocolo.goTo(St456webScreen.sinTrabajos);

      for (int i = 0; i < St456webProtocol.ticksPopup - 1; i++) {
        protocolo.advance(_peso(0), log: logs.add);
      }
      expect(protocolo.screen, St456webScreen.sinTrabajos);

      protocolo.advance(_peso(0), log: logs.add);
      expect(protocolo.screen, St456webScreen.principal);
      expect(logs.single, contains('popup 20'));
    });

    test('el 45 (indicador ocupado) no se cierra solo', () {
      final St456webProtocol protocolo = _protocolo();
      protocolo.goTo(St456webScreen.indicadorOcupado);
      for (int i = 0; i < 10; i++) {
        protocolo.advance(_peso(0), log: _sinLog);
      }
      expect(protocolo.screen, St456webScreen.indicadorOcupado);
    });
  });

  group('tramas (sección 7 del documento)', () {
    test('pantallas de peso', () {
      expect(
        St456webPayload.cargaReceta(_pesaje(3200, 450, 1200),
            ingrediente: 'Maiz'),
        '1,3200,450,1200,Maiz,0,0,0\r\n',
      );
      expect(
        St456webPayload.cargaManual(_pesaje(800, 120, 500),
            nroIngrediente: '3', ingrediente: 'Soja'),
        '2,800,120,500,3,Soja,0,0,0\r\n',
      );
      expect(
        St456webPayload.descargaGuia(_pesaje(5000, 1500, 2000),
            lote: 'Corral 4'),
        '3,5000,1500,2000,Corral 4,0,0,0\r\n',
      );
      expect(
        St456webPayload.descargaManual(
          const St456webPesaje(
            total: 2600,
            parcial: 300,
            objetivo: 1000,
            lock: true,
            level: false,
            sirena: true,
          ),
          lote: 'L01',
        ),
        '4,2600,300,1000,L01,1,0,1\r\n',
      );
    });

    test('mezclando manda minutos y segundos sin rellenar', () {
      expect(St456webPayload.mezclando(125), '6,2,5\r\n');
      expect(St456webPayload.mezclando(59), '6,0,59\r\n');
    });

    test('detalle tipo 2 repite el nombre de la guía en el campo de la receta',
        () {
      expect(
        St456webPayload.detalleGuia(catalogo.guia('Corrales A')!),
        '18,2,Corrales A,Corrales A,0,0,2,Corral 1,1000,Corral 2,800\r\n',
      );
    });

    test('detalle tipo 3 lleva la receta escalada a los kg del autónomo', () {
      final St456webTrabajo trabajo = catalogo.trabajo('3')!;
      final St456webReceta receta = catalogo.recetaDe(trabajo)!;
      expect(
        St456webPayload.detalleRecetaYGuia(
          receta,
          receta.escalada(catalogo.kgDe(trabajo)),
          catalogo.guiaDe(trabajo)!,
        ),
        '18,3,Vacas Lecheras,Corrales A,2,3,2,Maiz,720,Soja,360,Heno,720,'
        'Corral 1,1000,Corral 2,800\r\n',
      );
    });
  });

  group('catálogo', () {
    test('más trabajos que los que entran en una página', () {
      expect(catalogo.trabajos.length,
          greaterThan(St456webProtocol.itemsPorPagina));
    });

    test('los trabajos apuntan a recetas, guías y autónomos que existen', () {
      for (final St456webTrabajo t in catalogo.trabajos) {
        switch (t.tipo) {
          case St456webTipoTrabajo.receta:
            expect(catalogo.recetaDe(t), isNotNull, reason: t.nombre);
            expect(catalogo.guiaDe(t), isNull, reason: t.nombre);
          case St456webTipoTrabajo.guia:
            expect(catalogo.recetaDe(t), isNull, reason: t.nombre);
            expect(catalogo.guiaDe(t), isNotNull, reason: t.nombre);
          case St456webTipoTrabajo.autonomo:
            expect(catalogo.recetaDe(t), isNotNull, reason: t.nombre);
            expect(catalogo.guiaDe(t), isNotNull, reason: t.nombre);
        }
      }
    });

    test('escalar una receta no pierde kilos por redondeo', () {
      final St456webReceta receta = catalogo.receta('Terneros')!;
      final int suma = receta
          .escalada(1001)
          .fold<int>(0, (int s, St456webIngrediente i) => s + i.kg);
      expect(suma, 1001);
    });

    test('sólo ASCII y sin comas en los textos', () {
      final Iterable<String> textos = <String>[
        for (final St456webReceta r in catalogo.recetas) ...<String>[
          r.nombre,
          for (final St456webIngrediente i in r.ingredientes) i.nombre,
        ],
        for (final St456webAutonomo a in catalogo.autonomos) a.nombre,
        for (final St456webGuia g in catalogo.guias) ...<String>[
          g.nombre,
          for (final St456webLote l in g.lotes) l.nombre,
        ],
        for (final St456webTrabajo t in catalogo.trabajos) t.nombre,
        for (final St456webOperario o in catalogo.operarios) o.nombre,
      ];
      for (final String texto in textos) {
        expect(texto, matches(RegExp(r'^[\x20-\x7E]+$')), reason: texto);
        expect(texto, isNot(contains(',')), reason: texto);
      }
    });
  });
}
