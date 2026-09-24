import 'package:flutter_test/flutter_test.dart';
import 'package:test_jaguar/domain/entities/scale_measurement.dart';
import 'package:test_jaguar/protocols/st567/st567_command.dart';
import 'package:test_jaguar/protocols/st567/st567_protocol.dart';
import 'package:test_jaguar/protocols/st567/st567_screen.dart';
import 'package:test_jaguar/protocols/st567/st567_state.dart';

/// Los flujos de la sección 8 de `docs/protocolo-simulador-st567.md`, contra
/// el módulo solo: sin orquestador ni BLE.
class _Indicador {
  _Indicador() : protocolo = St567Protocol(now: () => DateTime(2026, 9, 14, 10, 32));

  final St567Protocol protocolo;
  final List<String> logs = <String>[];

  ScaleMeasurement _balanza = ScaleMeasurement.baseline.copyWith(peso: 1250);

  /// Lo que la app manda. Devuelve el log del comando.
  String app(String comando) {
    final String log = protocolo.apply(St567Command.tryParse(comando)!);
    logs.add(log);
    return log;
  }

  /// La trama de la pantalla vigente, como la arma el orquestador.
  String get trama =>
      protocolo.encodePayload(protocolo.outgoing(_balanza));

  St567Screen get pantalla => protocolo.screen;

  St567State get estado => protocolo.state;

  /// El peso que el orquestador publica para la UI.
  int get pesoMostrado => protocolo.outgoing(_balanza).peso;

  void ticks(int n, {int? peso}) {
    if (peso != null) {
      _balanza = _balanza.copyWith(peso: peso);
    }
    for (int i = 0; i < n; i++) {
      protocolo.advance(_balanza, log: logs.add);
    }
  }
}

void main() {
  group('reposo', () {
    test('levelLock alterna las líneas rojas', () {
      final _Indicador ind = _Indicador();
      ind.app('CTR,levelLock');
      expect(ind.trama, '0,1250,1,kg,,14/09/2026 10:32,1\r\n');
      ind.app('CTR,levelLock');
      expect(ind.trama, '0,1250,1,kg,,14/09/2026 10:32,0\r\n');
    });

    test('cero descuenta el peso vigente de la balanza', () {
      final _Indicador ind = _Indicador();
      ind.ticks(1, peso: 1250);
      ind.app('CTR,cero');
      expect(ind.trama, startsWith('0,0,1,kg,'));

      ind.ticks(1, peso: 1300);
      expect(ind.trama, startsWith('0,50,0,kg,'));
    });

    test('un comando fuera de su pantalla se loguea y no cambia nada', () {
      final _Indicador ind = _Indicador();
      expect(ind.app('CTR,acum,Dario'),
          'CTR,acum se ignora en la pantalla 0 - Principal');
      expect(ind.pantalla, St567Screen.principal);

      expect(ind.app('CTR,elegirGuia'), contains('no lo usa el ST567'));
    });
  });

  group('carga por receta', () {
    test('listas paginadas, detalle y vuelta a la misma página', () {
      final _Indicador ind = _Indicador();
      ind.app('CTR,elegirReceta');
      expect(ind.pantalla, St567Screen.elegirRecetaPreset);

      ind.app('CTR,nextPage');
      expect(ind.trama, '60,2,6,Toros,1200,7,Recria,900\r\n');
      expect(ind.app('CTR,nextPage'), contains('no hay más páginas'));

      ind.app('CTR,detail,6');
      expect(ind.trama, '37,Toros,30,1,2,Maiz,600,1,10,30,Heno,600,1,10,30\r\n');

      ind.app('CTR,esc');
      expect(ind.trama, '60,2,6,Toros,1200,7,Recria,900\r\n');

      ind.app('CTR,prevPage');
      expect(ind.trama, startsWith('60,5,1,Vacas Lecheras,1500,'));
    });

    test('sin preset responde la pantalla 30', () {
      final _Indicador ind = _Indicador();
      ind.protocolo.setOptions(const St567Options(recetasConPreset: false));
      ind.app('CTR,elegirReceta');
      expect(ind.trama, startsWith('30,5,1,Vacas Lecheras,2,Terneros,'));
    });

    test('ingrediente por ingrediente, sirena de aviso y mezcla', () {
      final _Indicador ind = _Indicador();
      ind.app('CTR,elegirReceta');
      ind.app('CTR,select,1,1500');
      expect(
        ind.trama,
        '38,0,0,600,Maiz,0,0,0,3,Maiz,600,1,10,30,0,Soja,300,0,20,30,0,'
        'Heno,600,1,15,60,0\r\n',
      );

      // Maiz sube de a 30 kg (600 en 20 ticks); el aviso es el 10 %: 60 kg.
      ind.ticks(17);
      expect(ind.trama, startsWith('38,510,510,600,Maiz,0,0,0,'));
      expect(ind.pesoMostrado, 90);
      ind.ticks(1);
      expect(ind.trama, startsWith('38,540,540,600,Maiz,0,0,1,'));
      ind.ticks(10);
      expect(ind.trama, startsWith('38,600,600,600,Maiz,0,0,1,'));

      ind.app('CTR,acum,Dario');
      expect(
        ind.trama,
        '38,600,0,300,Soja,0,0,0,3,Maiz,600,1,10,30,1,Soja,300,0,20,30,0,'
        'Heno,600,1,15,60,0\r\n',
      );
      expect(ind.estado.operario, 'Dario');

      ind.ticks(20);
      ind.app('CTR,acum,Dario');
      ind.ticks(20);
      ind.app('CTR,acum,Dario');

      // Receta completa: 30 s de mezcla, después vuelve a la principal.
      expect(ind.trama, '6,0,30\r\n');
      ind.ticks(1);
      expect(ind.trama, '6,0,29\r\n');
      ind.ticks(29);
      expect(ind.trama, '6,0,0\r\n');
      ind.ticks(1);
      expect(ind.pantalla, St567Screen.principal);
      expect(ind.estado.totalCargado, 1500);
      expect(ind.trama, startsWith('0,1250,1,kg,Dario,'));
    });

    test('sin operario, elegir una receta muestra el 16 y vuelve a la '
        'principal', () {
      final _Indicador ind = _Indicador();
      ind.protocolo.setOptions(const St567Options(sinOperario: true));
      ind.app('CTR,elegirReceta');
      ind.app('CTR,select,1,1500');
      expect(ind.trama, '16\r\n');

      ind.ticks(St567Protocol.ticksPopup);
      expect(ind.pantalla, St567Screen.principal);
    });

    test('la cantidad pedida escala la receta', () {
      final _Indicador ind = _Indicador();
      ind.app('CTR,elegirReceta');
      ind.app('CTR,select,1,1000');
      expect(
        ind.trama,
        '38,0,0,400,Maiz,0,0,0,3,Maiz,400,1,10,30,0,Soja,200,0,20,30,0,'
        'Heno,400,1,15,60,0\r\n',
      );
    });

    test('lock, level y rotate', () {
      final _Indicador ind = _Indicador();
      ind.app('CTR,elegirReceta');
      ind.app('CTR,select,1,1500');
      ind.app('CTR,lock');
      ind.app('CTR,level');
      expect(ind.trama, startsWith('38,0,0,600,Maiz,1,1,0,'));
      expect(ind.app('CTR,rotate'), contains('rotate'));
      expect(ind.pantalla, St567Screen.cargaReceta);
    });

    test('cambiar de operario en medio de la carga vuelve a la carga', () {
      final _Indicador ind = _Indicador();
      ind.app('CTR,elegirReceta');
      ind.app('CTR,select,1,1500');
      ind.ticks(2);
      ind.app('CTR,cambiarOperario');
      expect(ind.trama, '42,3,Dario,1234,Estevan,0000,Claudio,4321\r\n');
      ind.app('CTR,esc');
      expect(ind.trama, startsWith('38,60,60,600,Maiz,'));
    });

    test('ESC abandona una receta suelta', () {
      final _Indicador ind = _Indicador();
      ind.app('CTR,elegirReceta');
      ind.app('CTR,select,1,1500');
      ind.ticks(5);
      ind.app('CTR,esc');
      expect(ind.pantalla, St567Screen.principal);
      expect(ind.estado.totalCargado, 0);
    });
  });

  group('carga y descarga manual', () {
    test('carga un ingrediente, acumula y vuelve a la lista', () {
      final _Indicador ind = _Indicador();
      ind.app('CTR,cargaManual');
      expect(ind.pantalla, St567Screen.elegirIngrediente);

      ind.app('CTR,select,3,500');
      expect(ind.trama, '2,0,0,500,3,Heno,0,0,0\r\n');
      ind.ticks(1);
      expect(ind.trama, '2,25,25,500,3,Heno,0,0,0\r\n');
      ind.ticks(17);
      expect(ind.trama, '2,450,450,500,3,Heno,0,0,1\r\n');

      ind.app('CTR,acum,Dario');
      expect(ind.pantalla, St567Screen.elegirIngrediente);
      expect(ind.estado.totalCargado, 450);
    });

    test('selectIngrediente cambia de ingrediente sin acumular', () {
      final _Indicador ind = _Indicador();
      ind.app('CTR,cargaManual');
      ind.app('CTR,select,1,500');
      ind.ticks(3);
      ind.app('CTR,selectIngrediente');
      expect(ind.pantalla, St567Screen.elegirIngrediente);
      expect(ind.estado.totalCargado, 0);
    });

    test('descarga con objetivo, pide lote y sigue sin objetivo', () {
      final _Indicador ind = _Indicador();
      ind.app('CTR,cargaManual');
      ind.app('CTR,select,3,500');
      ind.ticks(18);
      ind.app('CTR,acum,Dario');
      ind.app('CTR,esc');

      ind.app('CTR,descargaManual,L01,300');
      expect(ind.trama, '4,450,0,300,L01,0,0,0\r\n');
      ind.ticks(1);
      expect(ind.trama, '4,435,15,300,L01,0,0,0\r\n');

      ind.app('CTR,acum');
      expect(ind.trama, '33\r\n');
      expect(ind.estado.totalCargado, 435);

      // kg en 0: descarga sin objetivo, la app muestra lo descargado.
      ind.app('CTR,descargaManual,L02,0');
      ind.ticks(1);
      expect(ind.trama, '4,385,50,0,L02,0,0,0\r\n');
      expect(ind.pesoMostrado, 50);
    });

    test('no descarga más de lo que hay en el mixer', () {
      final _Indicador ind = _Indicador();
      ind.app('CTR,descargaManual,L01,300');
      ind.ticks(5);
      expect(ind.trama, '4,0,0,300,L01,0,0,0\r\n');
    });

    test('descargaManual sin cantidad se ignora', () {
      final _Indicador ind = _Indicador();
      expect(ind.app('CTR,descargaManual,L01'), contains('se ignora'));
      expect(ind.pantalla, St567Screen.principal);
    });
  });

  group('trabajos', () {
    test('detalle de un trabajo y vuelta a la lista', () {
      final _Indicador ind = _Indicador();
      ind.app('CTR,elegirTrabajo');
      ind.app('CTR,detail,1');
      expect(
        ind.trama,
        '31,Trabajo Manana,Vacas Lecheras,2,50,30,3,2,4,Maiz,600,Soja,300,'
        'Heno,600,Corral 1,800,Corral 2,700\r\n',
      );
      ind.app('CTR,esc');
      expect(ind.pantalla, St567Screen.trabajos);
    });

    test('sin trabajos responde el popup 20', () {
      final _Indicador ind = _Indicador();
      ind.protocolo.setOptions(const St567Options(sinTrabajos: true));
      ind.app('CTR,elegirTrabajo');
      expect(ind.trama, '20\r\n');
    });

    test('carga, mezcla, descarga por lotes y "preparar más carga"', () {
      final _Indicador ind = _Indicador();
      ind.app('CTR,elegirTrabajo');
      ind.app('CTR,select,2');
      expect(ind.trama, startsWith('38,0,0,400,Maiz,0,0,0,3,'));

      for (int i = 0; i < 3; i++) {
        ind.ticks(20);
        ind.app('CTR,acum,Dario');
      }
      expect(ind.pantalla, St567Screen.mezclando);
      ind.ticks(21);

      expect(
        ind.trama,
        '39,800,0,500,Corral 3,0,0,0,3,Corral 3,0,500,Corral 4,0,300,'
        'Corral 5,0,200\r\n',
      );
      ind.ticks(20);
      expect(ind.trama, startsWith('39,300,500,500,Corral 3,0,0,1,3,'
          'Corral 3,500,500,'));
      ind.app('CTR,acum,Dario');
      ind.ticks(20);
      ind.app('CTR,acum,Dario');

      // 800 kg cargados, 800 descargados y todavía falta Corral 5.
      expect(ind.trama, '40\r\n');
      expect(ind.estado.totalCargado, 0);

      // NUEVA: otra carga de la receta por los 200 kg que faltan.
      ind.app('CTR,boton2');
      expect(ind.trama, startsWith('38,0,0,100,Maiz,0,0,0,3,Maiz,100,'));
      for (int i = 0; i < 3; i++) {
        ind.ticks(20);
        ind.app('CTR,acum,Dario');
      }
      ind.ticks(21);
      expect(ind.trama, startsWith('39,200,0,200,Corral 5,'));
      ind.ticks(20);
      ind.app('CTR,acum,Dario');

      expect(ind.pantalla, St567Screen.principal);
      expect(ind.logs.last, contains('Trabajo Tarde terminado'));
      ind.app('CTR,elegirTrabajo');
      expect(ind.trama, contains('2,Trabajo Tarde,1,'));
    });

    test('CONTINUAR en "preparar más carga" sigue con el lote vacío', () {
      final _Indicador ind = _Indicador();
      ind.app('CTR,elegirTrabajo');
      ind.app('CTR,select,2');
      for (int i = 0; i < 3; i++) {
        ind.ticks(20);
        ind.app('CTR,acum,Dario');
      }
      ind.ticks(21 + 20);
      ind.app('CTR,acum,Dario');
      ind.ticks(20);
      ind.app('CTR,acum,Dario');

      ind.app('CTR,boton1');
      ind.ticks(5);
      expect(ind.trama, startsWith('39,0,0,200,Corral 5,'));
      ind.app('CTR,acum,Dario');
      expect(ind.pantalla, St567Screen.principal);
    });

    test('un trabajo abandonado pregunta si reanudarlo', () {
      final _Indicador ind = _Indicador();
      ind.app('CTR,elegirTrabajo');
      ind.app('CTR,select,3');
      ind.ticks(2);
      expect(ind.trama, startsWith('38,120,120,1200,Maiz,'));
      ind.app('CTR,esc');
      expect(ind.pantalla, St567Screen.principal);

      ind.app('CTR,elegirTrabajo');
      ind.app('CTR,select,3');
      expect(ind.trama, '41\r\n');

      // ESC en el diálogo vuelve a la lista y el trabajo sigue en pausa.
      ind.app('CTR,esc');
      expect(ind.pantalla, St567Screen.trabajos);
      ind.app('CTR,select,3');
      expect(ind.trama, '41\r\n');

      ind.app('CTR,boton1');
      expect(ind.trama, startsWith('38,120,120,1200,Maiz,'));
    });

    test('ESC en la mezcla de un trabajo pasa directo a descargar', () {
      final _Indicador ind = _Indicador();
      ind.app('CTR,elegirTrabajo');
      ind.app('CTR,select,3');
      for (int i = 0; i < 3; i++) {
        ind.ticks(20);
        ind.app('CTR,acum,Dario');
      }
      ind.ticks(5);
      expect(ind.pantalla, St567Screen.mezclando);

      ind.app('CTR,esc');
      expect(ind.trama, startsWith('39,2000,0,1200,Corral 6,'));
    });

    test('un trabajo abandonado en la descarga avisa con el 17 y sigue '
        'descargando', () {
      final _Indicador ind = _Indicador();
      ind.app('CTR,elegirTrabajo');
      ind.app('CTR,select,3');
      for (int i = 0; i < 3; i++) {
        ind.ticks(20);
        ind.app('CTR,acum,Dario');
      }
      ind.ticks(46 + 20);
      ind.app('CTR,acum,Dario');
      ind.ticks(4);
      expect(ind.trama, startsWith('39,640,160,800,Corral 7,'));
      ind.app('CTR,esc');
      expect(ind.pantalla, St567Screen.principal);

      ind.app('CTR,elegirTrabajo');
      ind.app('CTR,select,3');
      expect(ind.trama, '17\r\n');

      // El popup no tiene ESC: si llega igual no corta la reanudación.
      expect(ind.app('CTR,esc'), contains('se ignora'));
      ind.ticks(St567Protocol.ticksPopup);
      expect(ind.logs.last, contains('popup 17 -> 39'));
      expect(ind.trama, startsWith('39,640,160,800,Corral 7,'));
    });

    test('sin operario, elegir un trabajo muestra el 16 y vuelve a la lista',
        () {
      final _Indicador ind = _Indicador();
      ind.protocolo.setOptions(const St567Options(sinOperario: true));
      ind.app('CTR,elegirTrabajo');
      ind.app('CTR,nextPage');
      ind.app('CTR,select,6');
      expect(ind.trama, '16\r\n');

      ind.ticks(St567Protocol.ticksPopup);
      expect(ind.trama, startsWith('34,1,6,Recria Oeste,'));
    });

    test('REINICIAR arranca el trabajo de cero', () {
      final _Indicador ind = _Indicador();
      ind.app('CTR,elegirTrabajo');
      ind.app('CTR,select,3');
      ind.ticks(2);
      ind.app('CTR,esc');
      ind.app('CTR,elegirTrabajo');
      ind.app('CTR,select,3');
      ind.app('CTR,boton2');
      expect(ind.trama, startsWith('38,0,0,1200,Maiz,'));
    });
  });

  group('sincronización', () {
    test('avanza de a 25 % y termina en 36', () {
      final _Indicador ind = _Indicador();
      ind.app('CTR,sync');
      expect(ind.trama, '19,0\r\n');
      ind.ticks(3);
      expect(ind.trama, '19,75\r\n');
      ind.ticks(1);
      expect(ind.trama, '36\r\n');
      ind.app('CTR,esc');
      expect(ind.pantalla, St567Screen.principal);
    });

    test('con la opción de falla termina en 35', () {
      final _Indicador ind = _Indicador();
      ind.protocolo.setOptions(const St567Options(sincronizacionFalla: true));
      ind.app('CTR,sync');
      ind.ticks(4);
      expect(ind.trama, '35\r\n');
    });
  });

  test('salir del modo descarta la sesión pero conserva las opciones', () {
    final _Indicador ind = _Indicador();
    ind.protocolo.setOptions(const St567Options(recetasConPreset: false));
    ind.app('CTR,cargaManual');
    ind.app('CTR,select,1,100');
    ind.ticks(20);
    ind.app('CTR,acum,Dario');

    ind.protocolo.resetRunState();
    expect(ind.pantalla, St567Screen.principal);
    expect(ind.estado.totalCargado, 0);
    expect(ind.estado.operario, '');
    expect(ind.estado.options.recetasConPreset, isFalse);
  });

  group('pantallas forzadas desde la UI', () {
    test('los diálogos 40 y 41 sin trabajo vuelven a la principal', () {
      final _Indicador ind = _Indicador();
      for (final St567Screen dialogo in <St567Screen>[
        St567Screen.masCarga,
        St567Screen.reanudarTrabajo,
      ]) {
        for (final String boton in <String>['CTR,boton1', 'CTR,boton2']) {
          ind.protocolo.goTo(dialogo);
          expect(ind.app(boton), contains('sin un trabajo en curso'));
          expect(ind.pantalla, St567Screen.principal);
        }
      }
    });

    test('la 18 muestra sólo la guía del primer trabajo y vuelve a la '
        'principal', () {
      final _Indicador ind = _Indicador();
      expect(ind.protocolo.goTo(St567Screen.detalleGuia),
          contains('"Corrales Este" (Trabajo Manana)'));
      expect(ind.trama,
          '18,2,Corrales Este,Corrales Este,0,0,2,Corral 1,800,Corral 2,700\r\n');
      ind.app('CTR,esc');
      expect(ind.pantalla, St567Screen.principal);
    });

    test('la 18 desde un detalle muestra esa guía y vuelve al detalle', () {
      final _Indicador ind = _Indicador();
      ind.app('CTR,elegirTrabajo');
      ind.app('CTR,nextPage');
      ind.app('CTR,detail,6');
      ind.protocolo.goTo(St567Screen.detalleGuia);
      expect(ind.trama,
          '18,2,Lotes Recria,Lotes Recria,0,0,2,Lote O1,450,Lote O2,450\r\n');

      ind.app('CTR,esc');
      expect(ind.pantalla, St567Screen.detalleTrabajo);
      ind.app('CTR,esc');
      expect(ind.trama, startsWith('34,1,6,Recria Oeste,0'));
    });

    test('la 18 en medio de una descarga muestra la guía del trabajo en curso',
        () {
      final _Indicador ind = _Indicador();
      ind.app('CTR,elegirTrabajo');
      ind.app('CTR,select,3');
      for (int i = 0; i < 3; i++) {
        ind.ticks(20);
        ind.app('CTR,acum,Dario');
      }
      ind.ticks(46);
      expect(ind.pantalla, St567Screen.descargaGuia);

      ind.protocolo.goTo(St567Screen.detalleGuia);
      expect(ind.trama, startsWith('18,2,Corrales Sur,Corrales Sur,0,0,2,'));
      ind.app('CTR,esc');
      expect(ind.trama, startsWith('39,'));
    });

    test('la 42 forzada vuelve a la principal aunque antes se haya entrado '
        'desde una carga', () {
      final _Indicador ind = _Indicador();
      ind.app('CTR,elegirReceta');
      ind.app('CTR,select,1,1500');
      ind.app('CTR,cambiarOperario');
      ind.app('CTR,esc');
      ind.app('CTR,esc');
      expect(ind.pantalla, St567Screen.principal);

      ind.protocolo.goTo(St567Screen.cambioOperario);
      ind.app('CTR,esc');
      expect(ind.pantalla, St567Screen.principal);
      expect(ind.trama, startsWith('0,'));
    });
  });
}
