import 'package:flutter_test/flutter_test.dart';
import 'package:test_jaguar/domain/entities/scale_measurement.dart';
import 'package:test_jaguar/protocols/shared/ctr_command.dart';
import 'package:test_jaguar/protocols/st456web/st456web_protocol.dart';
import 'package:test_jaguar/protocols/st456web/st456web_screen.dart';
import 'package:test_jaguar/protocols/st456web/st456web_state.dart';

/// Los flujos de las secciones 8 y 9 de
/// `docs/protocolo-simulador-st456web.md`, contra el módulo solo: sin
/// orquestador ni BLE.
class _Indicador {
  _Indicador()
      : protocolo = St456webProtocol(now: () => DateTime(2026, 9, 14, 10, 32));

  final St456webProtocol protocolo;
  final List<String> logs = <String>[];

  ScaleMeasurement _balanza = ScaleMeasurement.baseline.copyWith(peso: 1250);

  /// Lo que la app manda. Devuelve el log del comando.
  String app(String comando) {
    final String log = protocolo.apply(CtrCommand.tryParse(comando)!);
    logs.add(log);
    return log;
  }

  /// La trama de la pantalla vigente, como la arma el orquestador.
  String get trama => protocolo.encodePayload(protocolo.outgoing(_balanza));

  St456webScreen get pantalla => protocolo.screen;

  St456webState get estado => protocolo.state;

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

  /// Carga cada ingrediente hasta el objetivo y lo acumula, hasta que la
  /// receta pasa a mezclar.
  void cargarTodo({String operario = 'Dario'}) {
    while (pantalla == St456webScreen.cargaReceta) {
      ticks(St456webProtocol.ticksPorPaso);
      app('CTR,acum,$operario');
    }
  }

  /// Descarga cada lote hasta el objetivo y lo acumula, hasta terminar la
  /// guía.
  void descargarTodo() {
    while (pantalla == St456webScreen.descargaGuia) {
      ticks(St456webProtocol.ticksPorPaso);
      app('CTR,acum,Dario');
    }
  }

  /// Deja correr la mezcla hasta que termina.
  void mezclar() {
    while (pantalla == St456webScreen.mezclando) {
      ticks(1);
    }
  }
}

void main() {
  group('reposo', () {
    test('levelLock es del ST567: se ignora y el campo sigue en 0', () {
      final _Indicador ind = _Indicador();
      expect(ind.app('CTR,levelLock'), contains('lo ignora'));
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
      expect(ind.pantalla, St456webScreen.principal);

      expect(ind.app('CTR,elegirGuia'), contains('no lo usa el ST456web'));
      expect(ind.app('CTR,esc'), contains('no hay a dónde volver'));
    });
  });

  group('sincronización (8.6)', () {
    test('19 avanza con los ticks y termina en 36; OK vuelve a la principal',
        () {
      final _Indicador ind = _Indicador();
      ind.app('CTR,sync');
      expect(ind.trama, '19,0\r\n');

      ind.ticks(2);
      expect(ind.trama, '19,50\r\n');

      ind.ticks(2);
      expect(ind.pantalla, St456webScreen.sincronizacionExitosa);
      expect(ind.trama, '36\r\n');

      ind.app('CTR,esc');
      expect(ind.pantalla, St456webScreen.principal);
    });

    test('con la opción de falla termina en 35', () {
      final _Indicador ind = _Indicador();
      ind.protocolo.setOptions(const St456webOptions(sincronizacionFalla: true));
      ind.app('CTR,sync');
      ind.ticks(4);
      expect(ind.trama, '35\r\n');
    });
  });

  group('carga por receta (8.2)', () {
    test('next y prev recorren las recetas dando la vuelta', () {
      final _Indicador ind = _Indicador();
      ind.app('CTR,elegirReceta');
      expect(ind.trama, '8,Vacas Lecheras,1500\r\n');

      ind.app('CTR,next');
      expect(ind.trama, '8,Terneros,800\r\n');

      ind.app('CTR,prev');
      ind.app('CTR,prev');
      expect(ind.trama, '8,Secas,600\r\n');
    });

    test('start con cantidad escala la receta, anima el peso y avisa con la '
        'sirena', () {
      final _Indicador ind = _Indicador();
      ind.app('CTR,elegirReceta');
      ind.app('CTR,start,3000');
      expect(ind.pantalla, St456webScreen.cargaReceta);
      expect(ind.trama, '1,0,0,1200,Maiz,0,0,0\r\n');

      ind.ticks(10);
      expect(ind.trama, '1,600,600,1200,Maiz,0,0,0\r\n');
      // La app muestra lo que falta.
      expect(ind.pesoMostrado, 600);

      ind.ticks(8);
      expect(ind.trama, '1,1080,1080,1200,Maiz,0,0,1\r\n');

      ind.ticks(2);
      ind.app('CTR,acum,Dario');
      expect(ind.trama, '1,1200,0,600,Soja,0,0,0\r\n');
      expect(ind.estado.operario, 'Dario');
      expect(ind.estado.totalCargado, 1200);
    });

    test('el último ACUM mezcla y la mezcla termina en la principal', () {
      final _Indicador ind = _Indicador();
      ind.app('CTR,elegirReceta');
      ind.app('CTR,start,1500');
      ind.cargarTodo();

      expect(ind.pantalla, St456webScreen.mezclando);
      expect(ind.trama, '6,2,0\r\n');
      ind.ticks(1);
      expect(ind.trama, '6,1,59\r\n');

      ind.mezclar();
      expect(ind.pantalla, St456webScreen.principal);
      expect(ind.estado.totalCargado, 1500);
      expect(ind.logs.last, 'ST456web: mezcla terminada -> principal');
    });

    test('start con la cantidad vacía o en 0 usa la precargada', () {
      for (final String comando in <String>['CTR,start,', 'CTR,start,0']) {
        final _Indicador ind = _Indicador();
        ind.app('CTR,elegirReceta');
        expect(ind.app(comando), contains('Vacas Lecheras, 1500 kg'));
      }
    });

    test('sin operario responde el 16 y vuelve a la receta', () {
      final _Indicador ind = _Indicador();
      ind.protocolo.setOptions(const St456webOptions(sinOperario: true));
      ind.app('CTR,elegirReceta');
      ind.app('CTR,next');
      ind.app('CTR,start,800');
      expect(ind.trama, '16\r\n');

      ind.ticks(St456webProtocol.ticksPopup);
      expect(ind.trama, '8,Terneros,800\r\n');
    });

    test('lock, level y rotate en la carga; lock fuera de ella se ignora', () {
      final _Indicador ind = _Indicador();
      expect(ind.app('CTR,lock'), contains('se ignora'));

      ind.app('CTR,elegirReceta');
      ind.app('CTR,start,1500');
      ind.app('CTR,lock');
      ind.app('CTR,level');
      expect(ind.trama, '1,0,0,600,Maiz,1,1,0\r\n');
      expect(ind.app('CTR,rotate'), contains('sin cambio de pantalla'));
      ind.app('CTR,lock');
      expect(ind.trama, '1,0,0,600,Maiz,0,1,0\r\n');
    });

    test('ESC en la carga vuelve a la principal y pierde lo no acumulado', () {
      final _Indicador ind = _Indicador();
      ind.app('CTR,elegirReceta');
      ind.app('CTR,start,1500');
      ind.ticks(5);
      ind.app('CTR,esc');
      expect(ind.pantalla, St456webScreen.principal);
      expect(ind.estado.totalCargado, 0);
    });

    test('cambiar operario desde la carga vuelve a la carga', () {
      final _Indicador ind = _Indicador();
      ind.app('CTR,elegirReceta');
      ind.app('CTR,start,1500');
      ind.app('CTR,cambiarOperario');
      expect(ind.trama, '42,3,Dario,1234,Estevan,0000,Claudio,4321\r\n');

      ind.app('CTR,esc');
      expect(ind.trama, '1,0,0,600,Maiz,0,0,0\r\n');
    });
  });

  group('trabajos (8.3)', () {
    test('sin trabajos responde el 20 y vuelve a la principal', () {
      final _Indicador ind = _Indicador();
      ind.protocolo.setOptions(const St456webOptions(sinTrabajos: true));
      ind.app('CTR,elegirTrabajo');
      expect(ind.trama, '20\r\n');
      ind.ticks(St456webProtocol.ticksPopup);
      expect(ind.pantalla, St456webScreen.principal);
    });

    test('paginado de a 6 y select por fila de la página, no por índice', () {
      final _Indicador ind = _Indicador();
      ind.app('CTR,elegirTrabajo');
      expect(ind.trama, startsWith('11,6,1,1,RECE,Carga Manana,1,'));

      ind.app('CTR,nextPage');
      expect(ind.trama, '11,2,7,7,RECE,Engorde,0,8,8,RECE,Secas,0\r\n');
      expect(ind.app('CTR,nextPage'), contains('no hay más páginas'));

      expect(ind.app('CTR,select,3'), contains('no hay trabajo en la fila'));
      expect(ind.app('CTR,select,1'), contains('inicia Engorde'));
      expect(ind.pantalla, St456webScreen.cargaODescarga);
      expect(ind.trama, '15\r\n');

      // ESC vuelve a la misma página.
      ind.app('CTR,esc');
      expect(ind.trama, startsWith('11,2,7,'));
    });

    test('detail recibe el índice y ESC vuelve a la lista', () {
      final _Indicador ind = _Indicador();
      ind.app('CTR,elegirTrabajo');

      ind.app('CTR,detail,4');
      expect(ind.trama,
          '18,1,Terneros,,1,3,0,Maiz,400,Nucleo,100,Heno,300\r\n');
      ind.app('CTR,esc');

      ind.app('CTR,detail,2');
      expect(ind.trama,
          '18,2,Corrales A,Corrales A,0,0,2,Corral 1,1000,Corral 2,800\r\n');
      ind.app('CTR,esc');

      ind.app('CTR,detail,3');
      expect(
        ind.trama,
        '18,3,Vacas Lecheras,Corrales A,2,3,2,Maiz,720,Soja,360,Heno,720,'
        'Corral 1,1000,Corral 2,800\r\n',
      );
      ind.app('CTR,esc');
      expect(ind.pantalla, St456webScreen.trabajos);

      expect(ind.app('CTR,detail,99'), contains('no existe el trabajo 99'));
    });

    test('RECE: 15 -> CARGA -> 12 con los kg del trabajo -> 1 -> 6 -> 0 y '
        'queda realizado', () {
      final _Indicador ind = _Indicador();
      ind.app('CTR,elegirTrabajo');
      ind.app('CTR,nextPage');
      ind.app('CTR,select,1');
      expect(ind.app('CTR,boton2'), contains('no tiene guía'));

      ind.app('CTR,boton1');
      expect(ind.trama, '12,2000\r\n');

      ind.app('CTR,start,1000');
      expect(ind.trama, '1,0,0,600,Maiz,0,0,0\r\n');
      ind.cargarTodo();
      ind.mezclar();
      expect(ind.pantalla, St456webScreen.principal);
      expect(ind.logs.last, contains('Engorde terminado'));

      ind.app('CTR,elegirTrabajo');
      ind.app('CTR,nextPage');
      expect(ind.trama, startsWith('11,2,7,7,RECE,Engorde,1,'));
    });

    test('ESC en la 12 vuelve a la lista', () {
      final _Indicador ind = _Indicador();
      ind.app('CTR,elegirTrabajo');
      ind.app('CTR,select,4');
      ind.app('CTR,boton1');
      ind.app('CTR,esc');
      expect(ind.pantalla, St456webScreen.trabajos);
    });

    test('GUIA: 15 -> DESCARGA -> 10 -> 3 por lotes -> 0', () {
      final _Indicador ind = _Indicador();
      ind.app('CTR,elegirTrabajo');
      ind.app('CTR,select,2');
      expect(ind.app('CTR,boton1'), contains('no tiene receta'));

      ind.app('CTR,boton2');
      expect(ind.trama, '10,1,Corrales A\r\n');

      ind.app('CTR,start');
      expect(ind.trama, '3,0,0,1000,Corral 1,0,0,0\r\n');
      ind.ticks(St456webProtocol.ticksPorPaso);
      ind.app('CTR,acum,Dario');
      expect(ind.trama, '3,1000,0,800,Corral 2,0,0,0\r\n');

      ind.descargarTodo();
      expect(ind.pantalla, St456webScreen.principal);
      expect(ind.logs.last, contains('Descarga Corrales A terminado'));
    });

    test('AUTO: 9 -> 1 -> 6 -> 3 -> 0', () {
      final _Indicador ind = _Indicador();
      ind.app('CTR,elegirTrabajo');
      ind.app('CTR,select,3');
      expect(ind.trama,
          '9,1,Autonomo Norte,01/09/2026,30/09/2026,Vacas Lecheras,'
          'Corrales A\r\n');

      ind.app('CTR,start');
      expect(ind.trama, '1,0,0,720,Maiz,0,0,0\r\n');
      ind.cargarTodo();
      ind.mezclar();
      expect(ind.trama, '3,0,0,1000,Corral 1,0,0,0\r\n');
      expect(ind.estado.totalCargado, 1800);

      ind.descargarTodo();
      expect(ind.pantalla, St456webScreen.principal);
      expect(ind.estado.totalCargado, 0);
      expect(ind.logs.last, contains('Autonomo Norte terminado'));
    });

    test('sin operario el select responde el 16 y vuelve a la lista', () {
      final _Indicador ind = _Indicador();
      ind.protocolo.setOptions(const St456webOptions(sinOperario: true));
      ind.app('CTR,elegirTrabajo');
      ind.app('CTR,select,2');
      expect(ind.trama, '16\r\n');
      ind.ticks(St456webProtocol.ticksPopup);
      expect(ind.pantalla, St456webScreen.trabajos);
    });
  });

  group('descarga pendiente (14 y 17)', () {
    /// Autónomo Norte cargado y mezclado, cortado con ESC antes de descargar.
    _Indicador conPendiente() {
      final _Indicador ind = _Indicador();
      ind.app('CTR,elegirTrabajo');
      ind.app('CTR,select,3');
      ind.app('CTR,start');
      ind.cargarTodo();
      ind.app('CTR,esc');
      expect(ind.pantalla, St456webScreen.principal);
      expect(ind.estado.descargaPendiente, 'Autonomo Norte');
      ind.app('CTR,elegirTrabajo');
      return ind;
    }

    test('elegir el mismo trabajo avisa con el 17 y sigue descargando', () {
      final _Indicador ind = conPendiente();
      ind.app('CTR,select,3');
      expect(ind.trama, '17\r\n');

      ind.ticks(St456webProtocol.ticksPopup);
      expect(ind.trama, '3,0,0,1000,Corral 1,0,0,0\r\n');
      expect(ind.estado.descargaPendiente, '');
    });

    test('ESC en la descarga lo vuelve a dejar pendiente en el mismo lote', () {
      final _Indicador ind = conPendiente();
      ind.app('CTR,select,3');
      ind.ticks(St456webProtocol.ticksPopup + St456webProtocol.ticksPorPaso);
      ind.app('CTR,acum,Dario');
      ind.app('CTR,esc');
      expect(ind.estado.descargaPendiente, 'Autonomo Norte');

      ind.app('CTR,elegirTrabajo');
      ind.app('CTR,select,3');
      ind.ticks(St456webProtocol.ticksPopup);
      expect(ind.trama, '3,1000,0,800,Corral 2,0,0,0\r\n');
    });

    test('elegir otro pregunta con el 14: CONTINUAR descarga el pendiente', () {
      final _Indicador ind = conPendiente();
      ind.app('CTR,select,6');
      expect(ind.trama, '14\r\n');

      ind.app('CTR,boton1');
      expect(ind.trama, '3,0,0,1000,Corral 1,0,0,0\r\n');
    });

    test('NUEVA descarta el pendiente y arranca el elegido', () {
      final _Indicador ind = conPendiente();
      ind.app('CTR,select,6');
      ind.app('CTR,boton2');
      expect(ind.trama,
          '9,2,Autonomo Sur,15/09/2026,15/10/2026,Terneros,Corrales B\r\n');
      expect(ind.estado.descargaPendiente, '');
    });

    test('ESC en el 14 vuelve a la lista y el pendiente sigue', () {
      final _Indicador ind = conPendiente();
      ind.app('CTR,select,6');
      ind.app('CTR,esc');
      expect(ind.pantalla, St456webScreen.trabajos);
      expect(ind.estado.descargaPendiente, 'Autonomo Norte');
    });
  });

  group('carga y descarga manual (8.5)', () {
    test('cargaManual abre la 2 con el ingrediente del catálogo y ACUM '
        'vuelve a la principal', () {
      final _Indicador ind = _Indicador();
      ind.app('CTR,cargaManual');
      expect(ind.trama, '2,0,0,500,1,Maiz,0,0,0\r\n');
      expect(ind.app('CTR,selectIngrediente'), contains('lo ignora'));

      ind.ticks(St456webProtocol.ticksPorPaso);
      expect(ind.trama, '2,500,500,500,1,Maiz,0,0,1\r\n');

      ind.app(r'CTR,acum,Juan\sPerez');
      expect(ind.pantalla, St456webScreen.principal);
      expect(ind.estado.totalCargado, 500);
      expect(ind.estado.operario, 'Juan Perez');
    });

    test('descargaManual con cantidad descuenta del mixer', () {
      final _Indicador ind = _Indicador();
      ind.app('CTR,cargaManual');
      ind.ticks(St456webProtocol.ticksPorPaso);
      ind.app('CTR,acum,Dario');

      ind.app('CTR,descargaManual,L01,200');
      expect(ind.trama, '4,500,0,200,L01,0,0,0\r\n');
      ind.ticks(St456webProtocol.ticksPorPaso);
      ind.app('CTR,acum');
      expect(ind.pantalla, St456webScreen.principal);
      expect(ind.estado.totalCargado, 300);
    });

    test('descargaManual en 0 descarga sin objetivo hasta vaciar el mixer',
        () {
      final _Indicador ind = _Indicador();
      ind.app('CTR,cargaManual');
      ind.ticks(St456webProtocol.ticksPorPaso);
      ind.app('CTR,acum,Dario');

      ind.app('CTR,descargaManual,L02,0');
      ind.ticks(1);
      expect(ind.trama, '4,500,50,0,L02,0,0,0\r\n');
      expect(ind.pesoMostrado, 50);

      ind.ticks(20);
      expect(ind.trama, '4,500,500,0,L02,0,0,0\r\n');
    });

    test('descargaManual sin cantidad se ignora', () {
      final _Indicador ind = _Indicador();
      expect(ind.app('CTR,descargaManual,L03'), contains('necesita lote'));
      expect(ind.pantalla, St456webScreen.principal);
    });
  });

  group('pantallas forzadas desde la UI', () {
    test('en la 15 sin trabajo cualquier botón vuelve a la principal', () {
      final _Indicador ind = _Indicador();
      ind.protocolo.goTo(St456webScreen.cargaODescarga);
      ind.app('CTR,boton1');
      expect(ind.pantalla, St456webScreen.principal);
    });

    test('la 12 forzada carga la receta vigente y su ESC va a la principal',
        () {
      final _Indicador ind = _Indicador();
      ind.protocolo.goTo(St456webScreen.usarParcial);
      expect(ind.trama, '12,1500\r\n');
      ind.app('CTR,esc');
      expect(ind.pantalla, St456webScreen.principal);

      ind.protocolo.goTo(St456webScreen.usarParcial);
      ind.app('CTR,start,1500');
      expect(ind.trama, '1,0,0,600,Maiz,0,0,0\r\n');
    });

    test('la 9 forzada carga y descarga su autónomo sin trabajo', () {
      final _Indicador ind = _Indicador();
      ind.protocolo.goTo(St456webScreen.elegirAutonomo);
      ind.app('CTR,next');
      ind.app('CTR,start');
      ind.cargarTodo();
      ind.mezclar();
      expect(ind.trama, '3,0,0,500,Corral 3,0,0,0\r\n');
    });

    test('salir del modo descarta la sesión', () {
      final _Indicador ind = _mezclaCortada();
      ind.protocolo.resetRunState();
      expect(ind.pantalla, St456webScreen.principal);
      expect(ind.estado.totalCargado, 0);
      expect(ind.estado.descargaPendiente, '');
    });
  });
}

_Indicador _mezclaCortada() {
  final _Indicador ind = _Indicador();
  ind.app('CTR,elegirTrabajo');
  ind.app('CTR,select,3');
  ind.app('CTR,start');
  ind.cargarTodo();
  ind.app('CTR,esc');
  return ind;
}
