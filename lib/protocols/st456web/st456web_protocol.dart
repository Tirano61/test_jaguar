import 'dart:math' as math;

import 'package:test_jaguar/core/constants/ble_constants.dart';
import 'package:test_jaguar/core/constants/payload_framing.dart';
import 'package:test_jaguar/domain/entities/scale_measurement.dart';
import 'package:test_jaguar/domain/value_objects/send_protocol.dart';
import 'package:test_jaguar/protocols/shared/ctr_command.dart';
import 'package:test_jaguar/protocols/simulator_protocol.dart';
import 'package:test_jaguar/protocols/st456web/st456web_catalog.dart';
import 'package:test_jaguar/protocols/st456web/st456web_payload.dart';
import 'package:test_jaguar/protocols/st456web/st456web_screen.dart';
import 'package:test_jaguar/protocols/st456web/st456web_state.dart';

/// Protocolo Remoto ST456web (`docs/protocolo-simulador-st456web.md`).
///
/// Comparte con el ST407 y el ST567 el perfil GATT (ABF3, notify en ABF5,
/// write en ABF4) y la cabecera binaria de 5 bytes. Las pantallas son las
/// originales del remoto (`0`-`20`, `35`, `36`, `42`-`45`), cada una con sus
/// propios campos.
///
/// El simulador hace de indicador: guarda en qué pantalla está, responde a
/// los `CTR,<comando>` de la app con la pantalla que sigue (la máquina de
/// estados de la sección 9 del documento) y arma cada trama con los datos de
/// [St456webCatalog].
///
/// Hay tres entradas y cada una tiene un solo trabajo:
///
/// * [apply] procesa un comando de la app y cambia de pantalla;
/// * [advance] es el reloj (un tick del motor): anima la carga y la descarga,
///   corre la cuenta regresiva de la mezcla y el progreso de la
///   sincronización, y cierra los popups;
/// * [encodePayload] arma la trama de la pantalla vigente. Es puro: llamarlo
///   de más no adelanta nada.
///
/// Qué pantalla sigue a cada comando lo decide el firmware, que no tenemos:
/// donde el documento no lo dice, las decisiones están comentadas en el
/// handler.
class St456webProtocol implements SimulatorProtocol {
  St456webProtocol({
    DateTime Function()? now,
    this.catalog = St456webCatalog.demo,
  })  : _now = now ?? DateTime.now,
        _completos = <String>{
          for (final St456webTrabajo t in catalog.trabajos)
            if (t.completo) t.indice,
        };

  /// Reloj de la pantalla principal, inyectable para poder fijar la cadena
  /// exacta en los tests.
  final DateTime Function() _now;

  final St456webCatalog catalog;

  @override
  SendProtocol get id => SendProtocol.st456web;

  @override
  BleUuids get bleUuids => BleConstants.remotoAbf3;

  @override
  PayloadFraming get framing => PayloadFraming.fiveByteHeader;

  /// Trabajos por página en la `11`: el tope de la app.
  static const int itemsPorPagina = St456webPayload.maxTrabajos;

  /// Cuántos ticks queda un popup sin botones antes de cerrarse. La app no
  /// tiene cómo cerrarlos; el `45` (indicador ocupado) no se cierra solo
  /// porque en el equipo real dura lo que el operador tarde en salir del menú.
  static const int ticksPopup = 3;

  /// En cuántos ticks se completa un paso de carga o descarga.
  static const int ticksPorPaso = 20;

  /// Kilos por tick de una descarga manual sin objetivo (`kg` en 0).
  static const int pasoDescargaLibre = 50;

  /// Cuánto avanza la sincronización por tick.
  static const int pasoSincronizacion = 25;

  /// Porcentaje del objetivo que falta cuando suena la sirena.
  static const int avisoPorcentaje = 10;

  St456webOptions _options = const St456webOptions();

  St456webScreen _screen = St456webScreen.principal;
  int _pagina = 0;
  int _ticksEnPopup = 0;

  /// A dónde pasa el popup vigente cuando se cierra solo.
  St456webScreen _trasPopup = St456webScreen.principal;

  // --- Balanza ---

  /// Último peso del motor. `null` hasta el primer tick del modo.
  int? _pesoBalanza;
  bool _estable = true;

  /// Lo que restó `CTR,cero`.
  int _cero = 0;
  String _operario = '';

  // --- Pesaje en curso (pantallas 1 a 4) ---

  bool _lock = false;
  bool _level = false;

  /// Kilos en el mixer.
  int _totalCargado = 0;

  /// Lo cargado o descargado en el paso actual.
  int _parcial = 0;

  /// Carga por receta y/o descarga por guía en curso.
  _Corrida? _corrida;

  /// Kilos que tenía el mixer al empezar la descarga manual: el `total` de la
  /// `4`.
  int _mixerAlDescargar = 0;
  String _loteManual = '';
  int _kgDescargaManual = 0;

  int _segundosMezcla = 0;
  int _porcentajeSync = 0;

  // --- Selección de a un ítem (pantallas 8, 9 y 10) ---

  int _receta = 0;
  int _autonomo = 0;
  int _guia = 0;

  /// Lo que precarga la `12`.
  int _kgParcial = 0;

  // --- Trabajos ---

  final Set<String> _completos;

  /// El trabajo elegido en la `11` mientras se decide cómo arrancarlo (`15`,
  /// `12`, `9`, `10`). `null` si se llegó a esas pantallas de otro lado.
  St456webTrabajo? _trabajo;

  /// Un trabajo que quedó cargado sin descargar, con los lotes donde quedó.
  _Corrida? _pendiente;

  /// El trabajo elegido cuando saltó el `14`: NUEVA lo arranca.
  St456webTrabajo? _trabajoElegido;

  St456webTrabajo? _trabajoDetalle;
  St456webScreen _volverDeOperario = St456webScreen.principal;

  St456webScreen get screen => _screen;

  St456webState get state => St456webState(
        screen: _screen,
        options: _options,
        totalCargado: _totalCargado,
        operario: _operario,
        detalle: _detalle(),
        descargaPendiente: _pendiente?.trabajo?.nombre ?? '',
      );

  // --- Configuración desde la UI ---

  /// Salta a [screen] a pedido del tester. Devuelve la línea de log, o `null`
  /// si ya estaba en esa pantalla.
  String? goTo(St456webScreen screen) {
    if (_screen == screen) {
      return null;
    }
    // Forzada desde la UI, ninguna pantalla viene de un trabajo ni de una
    // carga: los ESC y los botones vuelven a la principal.
    _trabajo = null;
    _trabajoElegido = null;
    _volverDeOperario = St456webScreen.principal;
    switch (screen) {
      case St456webScreen.usarParcial:
        _kgParcial = catalog.recetas[_receta].cantidad;
      case St456webScreen.detalle:
        _trabajoDetalle ??= catalog.trabajos.first;
      case St456webScreen.sincronizando:
        _porcentajeSync = 0;
      default:
        break;
    }
    _entrar(screen);
    return 'Pantalla ST456web seleccionada: ${screen.label}';
  }

  String setOptions(St456webOptions options) {
    _options = options;
    return 'Opciones ST456web: '
        'sincronización ${options.sincronizacionFalla ? 'falla' : 'exitosa'}, '
        '${options.sinTrabajos ? 'sin trabajos' : 'con trabajos'}, '
        '${options.sinOperario ? 'sin operario' : 'con operario'}';
  }

  /// Descarta la sesión al salir del modo. Las opciones se conservan: son
  /// configuración, no estado.
  void resetRunState() {
    _entrar(St456webScreen.principal);
    _pesoBalanza = null;
    _estable = true;
    _cero = 0;
    _operario = '';
    _lock = false;
    _level = false;
    _totalCargado = 0;
    _parcial = 0;
    _corrida = null;
    _mixerAlDescargar = 0;
    _receta = 0;
    _autonomo = 0;
    _guia = 0;
    _trabajo = null;
    _pendiente = null;
    _trabajoElegido = null;
    _trabajoDetalle = null;
    _volverDeOperario = St456webScreen.principal;
    _completos
      ..clear()
      ..addAll(<String>{
        for (final St456webTrabajo t in catalog.trabajos)
          if (t.completo) t.indice,
      });
  }

  // --- Reloj ---

  /// Un tick del motor. [base] es la medición de la balanza; sale con el peso
  /// que muestra el indicador en la pantalla vigente (ver [outgoing]).
  ScaleMeasurement advance(
    ScaleMeasurement base, {
    required void Function(String line) log,
  }) {
    _estable = _pesoBalanza == null || _pesoBalanza == base.peso;
    _pesoBalanza = base.peso;

    switch (_screen) {
      case St456webScreen.cargaReceta:
        _parcial = _avanzar(_parcial, _corrida!.item.kg);
      case St456webScreen.cargaManual:
        _parcial = _avanzar(_parcial, catalog.cargaManual.kg);
      case St456webScreen.descargaGuia:
        _parcial = _avanzar(_parcial, _corrida!.lote.kg);
      case St456webScreen.descargaManual:
        _parcial = _kgDescargaManual > 0
            ? _avanzar(_parcial, _kgDescargaManual)
            // Sin objetivo descarga hasta vaciar el mixer.
            : math.min(_totalCargado, _parcial + pasoDescargaLibre);
      case St456webScreen.mezclando:
        if (_segundosMezcla > 0) {
          _segundosMezcla -= 1;
        } else {
          log(_terminarMezcla());
        }
      case St456webScreen.sincronizando:
        _porcentajeSync = math.min(100, _porcentajeSync + pasoSincronizacion);
        if (_porcentajeSync >= 100) {
          final St456webScreen fin = _options.sincronizacionFalla
              ? St456webScreen.sincronizacionFallida
              : St456webScreen.sincronizacionExitosa;
          _entrar(fin);
          log('ST456web: sincronización terminada -> ${fin.label}');
        }
      default:
        if (_screen.isPopup && _screen != St456webScreen.indicadorOcupado) {
          _ticksEnPopup += 1;
          if (_ticksEnPopup >= ticksPopup) {
            final St456webScreen popup = _screen;
            _entrar(_trasPopup, mantenerPagina: true);
            log('ST456web: se cierra el popup ${popup.code} -> '
                '${_screen.label}');
          }
        }
    }
    return outgoing(base);
  }

  /// [base] con el peso que muestra el indicador: en las pantallas de peso el
  /// número grande (`objetivo - parcial`), en el resto el de la balanza menos
  /// el cero. Es lo que el orquestador publica para la UI.
  ScaleMeasurement outgoing(ScaleMeasurement base) {
    final St456webPesaje? pesaje = _pesaje();
    if (pesaje != null) {
      return base.copyWith(
        peso: pesaje.objetivo > 0
            ? pesaje.objetivo - pesaje.parcial
            : pesaje.parcial.abs(),
      );
    }
    return base.copyWith(peso: (_pesoBalanza ?? base.peso) - _cero);
  }

  // --- Comandos ---

  /// Procesa un comando de la app y devuelve la línea de log. Un comando que
  /// no corresponde a la pantalla vigente no cambia nada, pero se loguea
  /// igual: es justamente lo que el tester necesita ver.
  String apply(CtrCommand command) {
    final String? log = switch (command.nombre.toLowerCase()) {
      'sync' => _sync(),
      'levellock' => _enPrincipal(
          () => 'CTR,levelLock es del ST567: el ST456web lo ignora'),
      'cero' => _enPrincipal(_hacerCero),
      'elegirreceta' => _enPrincipal(_elegirReceta),
      'elegirtrabajo' => _enPrincipal(_elegirTrabajo),
      'cargamanual' => _enPrincipal(_cargaManual),
      'descargamanual' => _enPrincipal(() => _descargaManual(command)),
      'cambiaroperario' => _cambiarOperario(),
      'esc' => _esc(),
      'next' => _rotar(1),
      'prev' => _rotar(-1),
      'start' => _start(command),
      'nextpage' => _paginar(1),
      'prevpage' => _paginar(-1),
      'detail' => _detail(command.arg(0)),
      'select' => _select(command.arg(0)),
      'boton1' => _boton(1),
      'boton2' => _boton(2),
      'acum' => _acum(command.arg(0)),
      'lock' => _toggleLock(),
      'level' => _toggleLevel(),
      'rotate' => _rotate(),
      'selectingrediente' => _screen == St456webScreen.cargaManual
          ? 'CTR,selectIngrediente es del ST567: el ST456web lo ignora'
          : null,
      _ => 'CTR,${command.nombre} no lo usa el ST456web: se ignora',
    };
    return log ??
        'CTR,${command.nombre} se ignora en la pantalla ${_screen.label}';
  }

  // Cada handler devuelve el log si aplicó el comando, o `null` si no
  // corresponde a la pantalla vigente.

  String? _enPrincipal(String Function() handler) =>
      _screen == St456webScreen.principal ? handler() : null;

  String? _sync() {
    if (_screen != St456webScreen.principal) {
      return null;
    }
    _porcentajeSync = 0;
    _entrar(St456webScreen.sincronizando);
    return 'Comando aplicado: CTR,sync -> sincronizando';
  }

  String _hacerCero() {
    _cero = _pesoBalanza ?? _cero;
    return 'Comando aplicado: CTR,cero -> se descuentan $_cero kg';
  }

  String _elegirReceta() {
    _trabajo = null;
    _receta = 0;
    _entrar(St456webScreen.elegirReceta);
    return 'Comando aplicado -> ${St456webScreen.elegirReceta.label}';
  }

  String _elegirTrabajo() {
    if (_options.sinTrabajos || catalog.trabajos.isEmpty) {
      _popup(St456webScreen.sinTrabajos);
      return 'Comando aplicado: no hay trabajos -> '
          '${St456webScreen.sinTrabajos.label}';
    }
    _entrar(St456webScreen.trabajos);
    return 'Comando aplicado -> ${St456webScreen.trabajos.label}';
  }

  /// La carga manual es del ST567: el ST456web la simula con el ingrediente y
  /// la cantidad fijos del catálogo, porque la app no manda ninguno.
  String _cargaManual() {
    _parcial = 0;
    _entrar(St456webScreen.cargaManual);
    return 'Comando aplicado: carga manual de '
        '${catalog.cargaManual.ingrediente}, ${catalog.cargaManual.kg} kg';
  }

  String _descargaManual(CtrCommand command) {
    final String lote = command.arg(0);
    final int? kg = _parseKg(command.arg(1));
    if (lote.isEmpty || kg == null) {
      return 'CTR,descargaManual necesita lote y cantidad: '
          '"${command.texto}" se ignora';
    }
    _loteManual = lote;
    _kgDescargaManual = kg;
    _mixerAlDescargar = _totalCargado;
    _parcial = 0;
    _entrar(St456webScreen.descargaManual);
    return 'Comando aplicado: descarga manual del lote $lote, '
        '${kg > 0 ? '$kg kg' : 'sin objetivo'}';
  }

  String? _cambiarOperario() {
    if (_screen != St456webScreen.principal &&
        _screen != St456webScreen.cargaReceta &&
        _screen != St456webScreen.cargaManual) {
      return null;
    }
    _volverDeOperario = _screen;
    _entrar(St456webScreen.cambioOperario);
    return 'Comando aplicado -> ${St456webScreen.cambioOperario.label}';
  }

  String _esc() {
    final St456webScreen desde = _screen;
    if (desde.isPopup) {
      return 'CTR,esc en el popup ${desde.code}: no tiene ESC, se ignora';
    }
    switch (desde) {
      case St456webScreen.principal:
        return 'CTR,esc en la pantalla principal: no hay a dónde volver';
      case St456webScreen.cambioOperario:
        _entrar(_volverDeOperario);
      case St456webScreen.detalle:
        _entrar(St456webScreen.trabajos, mantenerPagina: true);
      case St456webScreen.descargaPendiente:
        _trabajoElegido = null;
        _entrar(St456webScreen.trabajos, mantenerPagina: true);
      case St456webScreen.cargaODescarga:
      case St456webScreen.usarParcial:
      case St456webScreen.elegirAutonomo:
      case St456webScreen.elegirGuia:
        // Desde un trabajo vuelve a la lista; forzadas desde la UI, a la
        // principal.
        final bool deTrabajo = _trabajo != null;
        _trabajo = null;
        _entrar(deTrabajo ? St456webScreen.trabajos : St456webScreen.principal,
            mantenerPagina: true);
      case St456webScreen.mezclando:
        return _cortarMezcla();
      case St456webScreen.cargaReceta:
      case St456webScreen.cargaManual:
      case St456webScreen.descargaGuia:
      case St456webScreen.descargaManual:
        _abandonar();
        _entrar(St456webScreen.principal);
      default:
        _entrar(St456webScreen.principal);
    }
    return 'Comando aplicado: CTR,esc -> ${_screen.label}';
  }

  /// `next`/`prev` en las pantallas de a un ítem. La `9` y la `10` no tienen
  /// botón *prev* en la app, pero se tolera.
  String? _rotar(int delta) {
    // Da la vuelta en los dos sentidos: en Dart `%` nunca es negativo.
    int rotar(int actual, int total) => (actual + delta) % total;

    switch (_screen) {
      case St456webScreen.elegirReceta:
        _receta = rotar(_receta, catalog.recetas.length);
        return 'Comando aplicado: receta ${catalog.recetas[_receta].nombre}';
      case St456webScreen.elegirAutonomo:
        _autonomo = rotar(_autonomo, catalog.autonomos.length);
        return 'Comando aplicado: autónomo '
            '${catalog.autonomos[_autonomo].nombre}';
      case St456webScreen.elegirGuia:
        _guia = rotar(_guia, catalog.guias.length);
        return 'Comando aplicado: guía ${catalog.guias[_guia].nombre}';
      default:
        return null;
    }
  }

  String? _start(CtrCommand command) {
    switch (_screen) {
      case St456webScreen.elegirReceta:
        final St456webReceta receta = catalog.recetas[_receta];
        if (_options.sinOperario) {
          _popup(St456webScreen.sinOperario,
              despues: St456webScreen.elegirReceta);
          return 'CTR,start: el indicador no tiene operario -> '
              '${St456webScreen.sinOperario.label}';
        }
        // La app puede mandar la cantidad vacía o en 0 (sección 7.7): se usa
        // la que se había precargado.
        final int kg = _kgOr(command.arg(0), receta.cantidad);
        _iniciarCarga(_Corrida.carga(receta, kg: kg));
        return 'Comando aplicado: carga de ${receta.nombre}, $kg kg';
      case St456webScreen.usarParcial:
        final St456webTrabajo? trabajo = _trabajo;
        final St456webReceta receta = trabajo == null
            ? catalog.recetas[_receta]
            : catalog.recetaDe(trabajo)!;
        final int kg = _kgOr(command.arg(0), _kgParcial);
        _iniciarCarga(_Corrida.carga(receta, kg: kg, trabajo: trabajo));
        return 'Comando aplicado: carga de ${receta.nombre}, $kg kg'
            '${trabajo == null ? '' : ' (${trabajo.nombre})'}';
      case St456webScreen.elegirAutonomo:
        final St456webAutonomo autonomo = catalog.autonomos[_autonomo];
        final St456webReceta receta = catalog.receta(autonomo.receta)!;
        final St456webGuia guia = catalog.guia(autonomo.guia)!;
        _iniciarCarga(_Corrida.carga(
          receta,
          kg: autonomo.kg,
          guia: guia,
          trabajo: _trabajo,
        ));
        return 'Comando aplicado: autónomo ${autonomo.nombre}, carga de '
            '${receta.nombre} y descarga por ${guia.nombre}';
      case St456webScreen.elegirGuia:
        final St456webGuia guia = catalog.guias[_guia];
        _corrida = _Corrida.descarga(guia, trabajo: _trabajo);
        _trabajo = null;
        _parcial = 0;
        _entrar(St456webScreen.descargaGuia);
        return 'Comando aplicado: descarga por ${guia.nombre}';
      default:
        return null;
    }
  }

  String? _paginar(int delta) {
    if (_screen != St456webScreen.trabajos) {
      return null;
    }
    final int ultima =
        math.max(0, (catalog.trabajos.length - 1) ~/ itemsPorPagina);
    final int siguiente = (_pagina + delta).clamp(0, ultima);
    if (siguiente == _pagina) {
      return 'CTR,${delta > 0 ? 'nextPage' : 'prevPage'}: no hay más páginas';
    }
    _pagina = siguiente;
    return 'Comando aplicado: página ${_pagina + 1} de ${ultima + 1}';
  }

  /// `detail` recibe el `indice` del trabajo, no la fila.
  String? _detail(String indice) {
    if (_screen != St456webScreen.trabajos) {
      return null;
    }
    final St456webTrabajo? trabajo = catalog.trabajo(indice);
    if (trabajo == null) {
      return 'CTR,detail: no existe el trabajo $indice';
    }
    _trabajoDetalle = trabajo;
    _entrar(St456webScreen.detalle, mantenerPagina: true);
    return 'Comando aplicado: detalle de ${trabajo.nombre}';
  }

  /// `select` recibe la fila tocada en la página vigente (1..6), no el
  /// `indice` del trabajo (sección 7.10).
  String? _select(String posicion) {
    if (_screen != St456webScreen.trabajos) {
      return null;
    }
    final List<St456webTrabajo> pagina = _paginaDe(catalog.trabajos);
    final int? fila = int.tryParse(posicion.trim());
    if (fila == null || fila < 1 || fila > pagina.length) {
      return 'CTR,select: no hay trabajo en la fila "$posicion" de la página '
          '${_pagina + 1}';
    }
    final St456webTrabajo trabajo = pagina[fila - 1];
    if (_options.sinOperario) {
      _popup(St456webScreen.sinOperario, despues: St456webScreen.trabajos);
      return 'CTR,select: el indicador no tiene operario -> '
          '${St456webScreen.sinOperario.label}';
    }

    // Suposición (el documento no lo dice): con un trabajo cargado sin
    // descargar, elegir ese mismo avisa con el 17 y sigue descargando; elegir
    // otro pregunta con el 14.
    final _Corrida? pendiente = _pendiente;
    if (pendiente != null) {
      if (pendiente.trabajo!.indice == trabajo.indice) {
        _reanudarPendiente();
        _popup(St456webScreen.cargaRealizada,
            despues: St456webScreen.descargaGuia);
        return 'Comando aplicado: ${trabajo.nombre} ya tiene la carga hecha '
            '-> ${St456webScreen.cargaRealizada.label}';
      }
      _trabajoElegido = trabajo;
      _entrar(St456webScreen.descargaPendiente, mantenerPagina: true);
      return 'Comando aplicado: ${pendiente.trabajo!.nombre} tiene la descarga '
          'pendiente -> ${St456webScreen.descargaPendiente.label}';
    }
    return _arrancarTrabajo(trabajo);
  }

  /// Un `RECE` o un `GUIA` pregunta qué hacer (`15`); un `AUTO` va directo a
  /// su autónomo (`9`), que carga y después descarga.
  String _arrancarTrabajo(St456webTrabajo trabajo) {
    _trabajo = trabajo;
    if (trabajo.tipo == St456webTipoTrabajo.autonomo) {
      _autonomo = math.max(
        0,
        catalog.autonomos.indexWhere((a) => a.numero == trabajo.autonomo),
      );
      _entrar(St456webScreen.elegirAutonomo, mantenerPagina: true);
      return 'Comando aplicado: inicia ${trabajo.nombre} -> '
          '${St456webScreen.elegirAutonomo.label}';
    }
    _entrar(St456webScreen.cargaODescarga, mantenerPagina: true);
    return 'Comando aplicado: inicia ${trabajo.nombre} -> '
        '${St456webScreen.cargaODescarga.label}';
  }

  String? _boton(int boton) {
    switch (_screen) {
      case St456webScreen.cargaODescarga:
        final St456webTrabajo? trabajo = _trabajo;
        if (trabajo == null) {
          _entrar(St456webScreen.principal);
          return 'CTR,boton$boton sin un trabajo elegido -> '
              '${St456webScreen.principal.label}';
        }
        if (boton == 1) {
          // CARGA: propone los kg del trabajo en la 12.
          if (catalog.recetaDe(trabajo) == null) {
            return 'CTR,boton1 (CARGA): ${trabajo.nombre} no tiene receta, '
                'se ignora';
          }
          _kgParcial = catalog.kgDe(trabajo);
          _entrar(St456webScreen.usarParcial, mantenerPagina: true);
          return 'Comando aplicado: CARGA -> ${St456webScreen.usarParcial.label}';
        }
        // DESCARGA: muestra la guía del trabajo en la 10.
        final St456webGuia? guia = catalog.guiaDe(trabajo);
        if (guia == null) {
          return 'CTR,boton2 (DESCARGA): ${trabajo.nombre} no tiene guía, '
              'se ignora';
        }
        _guia = math.max(0, catalog.guias.indexOf(guia));
        _entrar(St456webScreen.elegirGuia, mantenerPagina: true);
        return 'Comando aplicado: DESCARGA -> ${St456webScreen.elegirGuia.label}';
      case St456webScreen.descargaPendiente:
        final St456webTrabajo? elegido = _trabajoElegido;
        _trabajoElegido = null;
        if (_pendiente == null || elegido == null) {
          _entrar(St456webScreen.principal);
          return 'CTR,boton$boton sin una descarga pendiente -> '
              '${St456webScreen.principal.label}';
        }
        if (boton == 1) {
          final String nombre = _pendiente!.trabajo!.nombre;
          _reanudarPendiente();
          _entrar(St456webScreen.descargaGuia);
          return 'Comando aplicado: CONTINUAR -> sigue la descarga de $nombre';
        }
        final String descartado = _pendiente!.trabajo!.nombre;
        _pendiente = null;
        return 'Comando aplicado: NUEVA -> se descarta la descarga de '
            '$descartado; ${_arrancarTrabajo(elegido)}';
      default:
        return null;
    }
  }

  String? _acum(String operario) {
    final String quien =
        operario.isEmpty ? 'sin operario' : 'operario $operario';
    switch (_screen) {
      case St456webScreen.cargaReceta:
        _operario = operario;
        final _Corrida corrida = _corrida!;
        final String log = 'Comando aplicado: ACUM $_parcial kg de '
            '${corrida.item.nombre} ($quien)';
        _totalCargado += _parcial;
        corrida.cargado += _parcial;
        _parcial = 0;
        if (corrida.itemActual + 1 < corrida.items.length) {
          corrida.itemActual += 1;
          return log;
        }
        _segundosMezcla = corrida.receta!.minutosMezcla * 60;
        _entrar(St456webScreen.mezclando);
        return '$log -> receta completa, mezclando';
      case St456webScreen.descargaGuia:
        _operario = operario;
        final _Corrida corrida = _corrida!;
        final _Lote lote = corrida.lote;
        final String log =
            'Comando aplicado: ACUM $_parcial kg en ${lote.nombre} ($quien)';
        lote.descargado = _parcial;
        _totalCargado = math.max(0, _totalCargado - _parcial);
        _parcial = 0;
        if (corrida.loteActual + 1 < corrida.lotes.length) {
          corrida.loteActual += 1;
          return log;
        }
        _corrida = null;
        _entrar(St456webScreen.principal);
        return '$log -> guía terminada${_completar(corrida)}';
      case St456webScreen.cargaManual:
        _operario = operario;
        final String log = 'Comando aplicado: ACUM $_parcial kg de '
            '${catalog.cargaManual.ingrediente} ($quien)';
        _totalCargado += _parcial;
        _parcial = 0;
        _entrar(St456webScreen.principal);
        return log;
      case St456webScreen.descargaManual:
        final String log =
            'Comando aplicado: ACUM $_parcial kg en el lote $_loteManual';
        _totalCargado = math.max(0, _totalCargado - _parcial);
        _parcial = 0;
        _entrar(St456webScreen.principal);
        return log;
      default:
        return null;
    }
  }

  String? _toggleLock() {
    if (_pesaje() == null) {
      return null;
    }
    _lock = !_lock;
    return 'Comando aplicado: CTR,lock -> ${_lock ? 'activo' : 'inactivo'}';
  }

  String? _toggleLevel() {
    if (_pesaje() == null) {
      return null;
    }
    _level = !_level;
    return 'Comando aplicado: CTR,level -> ${_level ? 'activo' : 'inactivo'}';
  }

  String? _rotate() {
    if (_screen != St456webScreen.cargaReceta &&
        _screen != St456webScreen.descargaGuia) {
      return null;
    }
    return 'Comando aplicado: CTR,rotate (acción del mixer, sin cambio de '
        'pantalla)';
  }

  // --- Corridas ---

  void _iniciarCarga(_Corrida corrida) {
    _corrida = corrida;
    _trabajo = null;
    _parcial = 0;
    _entrar(St456webScreen.cargaReceta);
  }

  /// Al terminar la mezcla sigue la descarga si la corrida tiene guía (un
  /// autónomo); si no, la carga termina ahí.
  String _terminarMezcla() {
    final _Corrida corrida = _corrida!;
    if (corrida.lotes.isNotEmpty) {
      _parcial = 0;
      _entrar(St456webScreen.descargaGuia);
      return 'ST456web: mezcla terminada -> descarga por ${corrida.guia!.nombre}';
    }
    _corrida = null;
    _entrar(St456webScreen.principal);
    return 'ST456web: mezcla terminada -> principal${_completar(corrida)}';
  }

  /// ESC en la mezcla: la carga ya está hecha, así que no se pierde. Si
  /// faltaba descargar un trabajo, queda pendiente.
  String _cortarMezcla() {
    final _Corrida corrida = _corrida!;
    _corrida = null;
    _entrar(St456webScreen.principal);
    if (corrida.lotes.isEmpty) {
      return 'Comando aplicado: CTR,esc corta la mezcla -> principal'
          '${_completar(corrida)}';
    }
    if (corrida.trabajo != null) {
      _pendiente = corrida;
      return 'Comando aplicado: CTR,esc corta la mezcla -> principal; '
          '${corrida.trabajo!.nombre} queda con la descarga pendiente';
    }
    return 'Comando aplicado: CTR,esc corta la mezcla -> principal';
  }

  /// ESC en una pantalla de peso. Lo pesado sin ACUM se pierde; un trabajo
  /// que ya cargó y estaba descargando queda pendiente.
  void _abandonar() {
    final _Corrida? corrida = _corrida;
    if (_screen == St456webScreen.descargaGuia &&
        corrida != null &&
        corrida.trabajo != null &&
        corrida.items.isNotEmpty) {
      _pendiente = corrida;
    }
    _corrida = null;
    _parcial = 0;
    _lock = false;
    _level = false;
    _volverDeOperario = St456webScreen.principal;
  }

  /// Retoma la descarga pendiente desde el lote donde quedó. La pantalla la
  /// elige el que llama.
  void _reanudarPendiente() {
    _corrida = _pendiente;
    _pendiente = null;
    _parcial = 0;
  }

  /// Marca como realizado el trabajo de [corrida], si tiene. Devuelve el
  /// sufijo para el log.
  String _completar(_Corrida corrida) {
    final St456webTrabajo? trabajo = corrida.trabajo;
    if (trabajo == null) {
      return '';
    }
    _completos.add(trabajo.indice);
    return ', ${trabajo.nombre} terminado';
  }

  // --- Tramas ---

  @override
  String encodePayload(ScaleMeasurement measurement) {
    final St456webPesaje? pesaje = _pesaje();
    switch (_screen) {
      case St456webScreen.principal:
        return St456webPayload.principal(
          peso: measurement.peso,
          estable: _estable,
          operario: _operario,
          fecha: _now(),
        );
      case St456webScreen.cargaReceta:
        return St456webPayload.cargaReceta(
          pesaje!,
          ingrediente: _corrida!.item.nombre,
        );
      case St456webScreen.cargaManual:
        return St456webPayload.cargaManual(
          pesaje!,
          nroIngrediente: catalog.cargaManual.nroIngrediente,
          ingrediente: catalog.cargaManual.ingrediente,
        );
      case St456webScreen.descargaGuia:
        return St456webPayload.descargaGuia(pesaje!, lote: _corrida!.lote.nombre);
      case St456webScreen.descargaManual:
        return St456webPayload.descargaManual(pesaje!, lote: _loteManual);
      case St456webScreen.mezclando:
        return St456webPayload.mezclando(_segundosMezcla);
      case St456webScreen.elegirReceta:
        return St456webPayload.receta(catalog.recetas[_receta]);
      case St456webScreen.elegirAutonomo:
        return St456webPayload.autonomo(catalog.autonomos[_autonomo]);
      case St456webScreen.elegirGuia:
        return St456webPayload.guia(catalog.guias[_guia]);
      case St456webScreen.trabajos:
        return St456webPayload.trabajos(
          _paginaDe(catalog.trabajos),
          completo: (St456webTrabajo t) => _completos.contains(t.indice),
        );
      case St456webScreen.usarParcial:
        return St456webPayload.parcial(_kgParcial);
      case St456webScreen.detalle:
        return _detalleTrabajo(_trabajoDetalle!);
      case St456webScreen.sincronizando:
        return St456webPayload.sincronizando(_porcentajeSync);
      case St456webScreen.cambioOperario:
        return St456webPayload.operarios(catalog.operarios);
      case St456webScreen.descargaPendiente:
      case St456webScreen.cargaODescarga:
      case St456webScreen.sinOperario:
      case St456webScreen.cargaRealizada:
      case St456webScreen.sinTrabajos:
      case St456webScreen.sincronizacionFallida:
      case St456webScreen.sincronizacionExitosa:
      case St456webScreen.operarioNoEncontrado:
      case St456webScreen.claveIncorrecta:
      case St456webScreen.indicadorOcupado:
        return St456webPayload.frame(_screen);
    }
  }

  /// La `18` de [trabajo]: tipo 1 si sólo carga, 2 si sólo descarga, 3 si
  /// hace las dos cosas. Los kg de la receta son los del trabajo.
  String _detalleTrabajo(St456webTrabajo trabajo) {
    final St456webReceta? receta = catalog.recetaDe(trabajo);
    final St456webGuia? guia = catalog.guiaDe(trabajo);
    final List<St456webIngrediente> ingredientes =
        receta?.escalada(catalog.kgDe(trabajo)) ?? const <St456webIngrediente>[];
    if (receta != null && guia != null) {
      return St456webPayload.detalleRecetaYGuia(receta, ingredientes, guia);
    }
    if (guia != null) {
      return St456webPayload.detalleGuia(guia);
    }
    return St456webPayload.detalleReceta(receta!, ingredientes);
  }

  /// Los campos de peso de la pantalla vigente, o `null` si no es una de las
  /// cuatro pantallas de peso.
  St456webPesaje? _pesaje() {
    switch (_screen) {
      case St456webScreen.cargaReceta:
        final _Corrida corrida = _corrida!;
        return _armarPesaje(
          total: corrida.cargado + _parcial,
          objetivo: corrida.item.kg,
        );
      case St456webScreen.cargaManual:
        return _armarPesaje(
          total: _totalCargado + _parcial,
          objetivo: catalog.cargaManual.kg,
        );
      case St456webScreen.descargaGuia:
        final _Corrida corrida = _corrida!;
        return _armarPesaje(
          total: corrida.descargadoGuia + _parcial,
          objetivo: corrida.lote.kg,
        );
      case St456webScreen.descargaManual:
        return _armarPesaje(
          total: _mixerAlDescargar,
          objetivo: _kgDescargaManual,
        );
      default:
        return null;
    }
  }

  St456webPesaje _armarPesaje({required int total, required int objetivo}) {
    return St456webPesaje(
      total: total,
      parcial: _parcial,
      objetivo: objetivo,
      lock: _lock,
      level: _level,
      // Sin objetivo (descarga manual con kg en 0) no hay a qué avisar.
      sirena: objetivo > 0 &&
          objetivo - _parcial <= objetivo * avisoPorcentaje ~/ 100,
    );
  }

  String _detalle() {
    final St456webPesaje? pesaje = _pesaje();
    switch (_screen) {
      case St456webScreen.cargaReceta:
        return 'Cargando ${_corrida!.item.nombre} '
            '(${_corrida!.receta!.nombre}): '
            '${pesaje!.parcial}/${pesaje.objetivo} kg';
      case St456webScreen.cargaManual:
        return 'Cargando ${catalog.cargaManual.ingrediente}: '
            '${pesaje!.parcial}/${pesaje.objetivo} kg';
      case St456webScreen.descargaGuia:
        return 'Descargando ${_corrida!.lote.nombre}: '
            '${pesaje!.parcial}/${pesaje.objetivo} kg';
      case St456webScreen.descargaManual:
        return 'Descargando lote $_loteManual: ${pesaje!.parcial}/'
            '${pesaje.objetivo > 0 ? pesaje.objetivo : '-'} kg';
      case St456webScreen.mezclando:
        return 'Mezclando: quedan $_segundosMezcla s';
      case St456webScreen.sincronizando:
        return 'Sincronizando: $_porcentajeSync %';
      default:
        return '';
    }
  }

  // --- Utilidades ---

  void _entrar(St456webScreen screen, {bool mantenerPagina = false}) {
    _screen = screen;
    if (!mantenerPagina) {
      _pagina = 0;
    }
    _ticksEnPopup = 0;
    _trasPopup = St456webScreen.principal;
  }

  /// Muestra un popup sin botones que al cerrarse solo pasa a [despues].
  void _popup(
    St456webScreen popup, {
    St456webScreen despues = St456webScreen.principal,
  }) {
    _entrar(popup, mantenerPagina: true);
    _trasPopup = despues;
  }

  /// Un paso de la animación de carga o descarga: [objetivo] se completa en
  /// [ticksPorPaso] ticks.
  int _avanzar(int actual, int objetivo) {
    if (actual >= objetivo) {
      return actual;
    }
    final int paso = math.max(1, (objetivo / ticksPorPaso).ceil());
    return math.min(objetivo, actual + paso);
  }

  List<T> _paginaDe<T>(List<T> items) {
    final int desde = _pagina * itemsPorPagina;
    if (desde >= items.length) {
      return <T>[];
    }
    final int hasta = math.min(desde + itemsPorPagina, items.length);
    return items.sublist(desde, hasta);
  }

  /// Los kilos de `CTR,start,<kg>`, o [porDefecto] si llegan vacíos, en 0 o
  /// con basura: el campo de la `12` no tiene filtro (sección 7.11).
  static int _kgOr(String value, int porDefecto) {
    final int? kg = _parseKg(value);
    return kg == null || kg == 0 ? porDefecto : kg;
  }

  static int? _parseKg(String value) {
    final double? kg = double.tryParse(value.trim());
    if (kg == null || kg < 0) {
      return null;
    }
    return kg.round();
  }
}

class _Lote {
  _Lote(this.nombre, this.kg);

  final String nombre;
  final int kg;
  int descargado = 0;
}

/// Una carga por receta, una descarga por guía, o las dos (autónomo).
class _Corrida {
  _Corrida._({
    required this.receta,
    required this.items,
    required this.guia,
    required this.lotes,
    required this.trabajo,
  });

  factory _Corrida.carga(
    St456webReceta receta, {
    required int kg,
    St456webGuia? guia,
    St456webTrabajo? trabajo,
  }) {
    return _Corrida._(
      receta: receta,
      items: receta.escalada(kg),
      guia: guia,
      lotes: <_Lote>[
        if (guia != null)
          for (final St456webLote l in guia.lotes) _Lote(l.nombre, l.kg),
      ],
      trabajo: trabajo,
    );
  }

  factory _Corrida.descarga(St456webGuia guia, {St456webTrabajo? trabajo}) {
    return _Corrida._(
      receta: null,
      items: const <St456webIngrediente>[],
      guia: guia,
      lotes: <_Lote>[
        for (final St456webLote l in guia.lotes) _Lote(l.nombre, l.kg),
      ],
      trabajo: trabajo,
    );
  }

  final St456webReceta? receta;
  final List<St456webIngrediente> items;
  final St456webGuia? guia;
  final List<_Lote> lotes;
  final St456webTrabajo? trabajo;
  int itemActual = 0;
  int loteActual = 0;

  /// Lo acumulado con ACUM en esta carga: el `total` de la `1`.
  int cargado = 0;

  St456webIngrediente get item => items[itemActual];
  _Lote get lote => lotes[loteActual];

  /// Lo descargado en los lotes ya pasados: con el parcial del lote en curso
  /// es el `total` de la `3`.
  int get descargadoGuia {
    int suma = 0;
    for (int i = 0; i < loteActual && i < lotes.length; i++) {
      suma += lotes[i].descargado;
    }
    return suma;
  }
}
