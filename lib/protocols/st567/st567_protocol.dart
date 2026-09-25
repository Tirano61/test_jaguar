import 'dart:math' as math;

import 'package:test_jaguar/core/constants/ble_constants.dart';
import 'package:test_jaguar/core/constants/payload_framing.dart';
import 'package:test_jaguar/domain/entities/scale_measurement.dart';
import 'package:test_jaguar/domain/value_objects/send_protocol.dart';
import 'package:test_jaguar/protocols/simulator_protocol.dart';
import 'package:test_jaguar/protocols/st567/st567_catalog.dart';
import 'package:test_jaguar/protocols/st567/st567_command.dart';
import 'package:test_jaguar/protocols/st567/st567_payload.dart';
import 'package:test_jaguar/protocols/st567/st567_screen.dart';
import 'package:test_jaguar/protocols/st567/st567_state.dart';

/// Protocolo Remoto ST567 (`docs/protocolo-simulador-st567.md`).
///
/// Comparte con el ST407 el perfil GATT (ABF3, notify en ABF5, write en ABF4)
/// y la cabecera binaria de 5 bytes, pero no el formato: las pantallas van de
/// `0` a `60` y cada una tiene sus propios campos.
///
/// El simulador hace de indicador: guarda en qué pantalla está, responde a
/// los `CTR,<comando>` de la app con la pantalla que sigue (los flujos de la
/// sección 8 del documento) y arma cada trama con los datos de
/// [St567Catalog].
///
/// Hay tres entradas y cada una tiene un solo trabajo:
///
/// * [apply] procesa un comando de la app y cambia de pantalla;
/// * [advance] es el reloj (un tick del motor): anima la carga y la descarga,
///   corre la cuenta regresiva de la mezcla y el progreso de la
///   sincronización, y cierra los popups;
/// * [encodePayload] arma la trama de la pantalla vigente. Es puro: llamarlo
///   de más no adelanta nada.
class St567Protocol implements SimulatorProtocol {
  St567Protocol({
    DateTime Function()? now,
    this.catalog = St567Catalog.demo,
  })  : _now = now ?? DateTime.now,
        _completos = <String>{
          for (final St567Trabajo t in catalog.trabajos)
            if (t.completo) t.indice,
        };

  /// Reloj de la pantalla principal, inyectable para poder fijar la cadena
  /// exacta en los tests.
  final DateTime Function() _now;

  final St567Catalog catalog;

  @override
  SendProtocol get id => SendProtocol.st567;

  @override
  BleUuids get bleUuids => BleConstants.remotoAbf3;

  @override
  PayloadFraming get framing => PayloadFraming.fiveByteHeader;

  /// Ítems por página en las listas. Es menor que los topes de la app (15
  /// trabajos, 30 recetas) para que el catálogo de prueba tenga más de una
  /// página.
  static const int itemsPorPagina = 5;

  /// Cuántos ticks queda un popup sin botones antes de volver a la principal.
  /// La app no tiene cómo cerrarlos; el `45` (indicador ocupado) no se cierra
  /// solo porque en el equipo real dura lo que el operador tarde en salir del
  /// menú.
  static const int ticksPopup = 3;

  /// En cuántos ticks se completa un paso de carga o descarga.
  static const int ticksPorPaso = 20;

  /// Kilos por tick de una descarga manual sin objetivo (`kg` en 0).
  static const int pasoDescargaLibre = 50;

  /// Cuánto avanza la sincronización por tick.
  static const int pasoSincronizacion = 25;

  /// Porcentaje del objetivo que falta cuando suena la sirena en las
  /// pantallas sin aviso propio (`2`, `4`, `39`).
  static const int avisoPorcentaje = 10;

  St567Options _options = const St567Options();

  St567Screen _screen = St567Screen.principal;
  int _pagina = 0;
  int _ticksEnPopup = 0;

  // --- Balanza ---

  /// Último peso del motor. `null` hasta el primer tick del modo.
  int? _pesoBalanza;
  bool _estable = true;

  /// Lo que restó `CTR,cero`.
  int _cero = 0;
  bool _levelLock = false;
  String _operario = '';

  // --- Pesaje en curso (pantallas 2, 4, 38 y 39) ---

  bool _lock = false;
  bool _level = false;

  /// Kilos en el mixer.
  int _totalCargado = 0;

  /// Lo cargado o descargado en el paso actual.
  int _parcial = 0;

  St567Ingrediente? _ingrediente;
  int _kgACargar = 0;

  String _lote = '';
  int _kgADescargar = 0;

  /// Carga por receta, sola o como parte de un trabajo.
  _Corrida? _corrida;

  int _segundosMezcla = 0;
  int _porcentajeSync = 0;

  // --- Trabajos ---

  final Set<String> _completos;

  /// Trabajos que se abandonaron con ESC a mitad de camino, por índice. Si la
  /// app vuelve a elegir uno, el indicador pregunta si reanudarlo (`41`).
  final Map<String, _Corrida> _pausadas = <String, _Corrida>{};
  String? _trabajoPorReanudar;

  // --- Navegación ---

  St567Receta? _recetaDetalle;
  St567Trabajo? _trabajoDetalle;
  St567Screen _volverDeOperario = St567Screen.principal;

  /// El trabajo cuya guía muestra la `18` y a dónde vuelve su ESC.
  St567Trabajo? _trabajoGuia;
  St567Screen _volverDeGuia = St567Screen.principal;

  St567Screen get screen => _screen;

  St567State get state => St567State(
        screen: _screen,
        options: _options,
        levelLock: _levelLock,
        totalCargado: _totalCargado,
        operario: _operario,
        detalle: _detalle(),
      );

  // --- Configuración desde la UI ---

  /// Salta a [screen] a pedido del tester. Devuelve la línea de log, o `null`
  /// si ya estaba en esa pantalla.
  String? goTo(St567Screen screen) {
    if (_screen == screen) {
      return null;
    }
    // Forzada desde la UI, la 42 no viene de ninguna carga: el ESC vuelve a la
    // principal.
    _volverDeOperario = St567Screen.principal;
    if (screen == St567Screen.detalleGuia) {
      return _verGuia();
    }
    _entrar(screen);
    return 'Pantalla ST567 seleccionada: ${screen.label}';
  }

  /// La `18` no la pide ningún comando del ST567: la fuerza el tester para ver
  /// una guía sola. Muestra la del trabajo en curso, o la del último detalle
  /// que se abrió, o la del primero del catálogo.
  String _verGuia() {
    final St567Trabajo? trabajo = _corrida?.trabajo ??
        _trabajoDetalle ??
        (catalog.trabajos.isEmpty ? null : catalog.trabajos.first);
    if (trabajo == null) {
      return 'ST567: no hay trabajos, no hay guía para mostrar';
    }
    _trabajoGuia = trabajo;
    // Desde la lista, el detalle o la descarga, el ESC vuelve ahí; desde
    // cualquier otra, a la principal.
    _volverDeGuia = const <St567Screen>{
      St567Screen.trabajos,
      St567Screen.detalleTrabajo,
      St567Screen.descargaGuia,
    }.contains(_screen)
        ? _screen
        : St567Screen.principal;
    _entrar(St567Screen.detalleGuia, mantenerPagina: true);
    return 'Pantalla ST567 seleccionada: ${St567Screen.detalleGuia.label} '
        '"${trabajo.guia}" (${trabajo.nombre})';
  }

  String setOptions(St567Options options) {
    _options = options;
    return 'Opciones ST567: '
        'recetas ${options.recetasConPreset ? 'con preset (60)' : 'sin preset (30)'}, '
        'sincronización ${options.sincronizacionFalla ? 'falla' : 'exitosa'}, '
        '${options.sinTrabajos ? 'sin trabajos' : 'con trabajos'}';
  }

  /// Descarta la sesión al salir del modo. Las opciones se conservan: son
  /// configuración, no estado.
  void resetRunState() {
    _entrar(St567Screen.principal);
    _pesoBalanza = null;
    _estable = true;
    _cero = 0;
    _levelLock = false;
    _operario = '';
    _lock = false;
    _level = false;
    _totalCargado = 0;
    _parcial = 0;
    _corrida = null;
    _pausadas.clear();
    _trabajoPorReanudar = null;
    _volverDeOperario = St567Screen.principal;
    _completos
      ..clear()
      ..addAll(<String>{
        for (final St567Trabajo t in catalog.trabajos)
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
      case St567Screen.cargaManual:
        _parcial = _avanzar(_parcial, tope: _kgACargar, objetivo: _kgACargar);
      case St567Screen.cargaReceta:
        final int cantidad = _corrida!.item.cantidad;
        _parcial = _avanzar(_parcial, tope: cantidad, objetivo: cantidad);
      case St567Screen.descargaManual:
        // Nunca se descarga más de lo que hay en el mixer.
        final int tope = _kgADescargar > 0
            ? math.min(_kgADescargar, _totalCargado)
            : _totalCargado;
        _parcial = _kgADescargar > 0
            ? _avanzar(_parcial, tope: tope, objetivo: _kgADescargar)
            : math.min(tope, _parcial + pasoDescargaLibre);
      case St567Screen.descargaGuia:
        final _LoteDescarga lote = _corrida!.lote;
        _parcial = _avanzar(
          _parcial,
          tope: math.min(lote.total, _totalCargado),
          objetivo: lote.total,
        );
      case St567Screen.mezclando:
        if (_segundosMezcla > 0) {
          _segundosMezcla -= 1;
        } else {
          log(_terminarMezcla());
        }
      case St567Screen.sincronizando:
        _porcentajeSync = math.min(100, _porcentajeSync + pasoSincronizacion);
        if (_porcentajeSync >= 100) {
          final St567Screen fin = _options.sincronizacionFalla
              ? St567Screen.sincronizacionFallida
              : St567Screen.sincronizacionExitosa;
          _entrar(fin);
          log('ST567: sincronización terminada -> ${fin.label}');
        }
      default:
        if (_screen.isPopup && _screen != St567Screen.indicadorOcupado) {
          _ticksEnPopup += 1;
          if (_ticksEnPopup >= ticksPopup) {
            log('ST567: se cierra el popup ${_screen.code} y vuelve a la '
                'principal');
            _entrar(St567Screen.principal);
          }
        }
    }
    return outgoing(base);
  }

  /// [base] con el peso que muestra el indicador: en las pantallas de peso el
  /// número grande (`objetivo - parcial`), en el resto el de la balanza menos
  /// el cero. Es lo que el orquestador publica para la UI.
  ScaleMeasurement outgoing(ScaleMeasurement base) {
    final St567Pesaje? pesaje = _pesaje();
    if (pesaje != null) {
      return base.copyWith(peso: _pesoGrande(pesaje));
    }
    return base.copyWith(peso: (_pesoBalanza ?? base.peso) - _cero);
  }

  // --- Comandos ---

  /// Procesa un comando de la app y devuelve la línea de log. Un comando que
  /// no corresponde a la pantalla vigente no cambia nada, pero se loguea
  /// igual: es justamente lo que el tester necesita ver.
  String apply(St567Command command) {
    final String nombre = command.nombre.toLowerCase();
    final String? log = switch (nombre) {
      'sync' => _sync(),
      'levellock' => _toggleLevelLock(),
      'cero' => _hacerCero(),
      'cargamanual' => _desdePrincipal(St567Screen.elegirIngrediente),
      'elegirreceta' => _desdePrincipal(_options.recetasConPreset
          ? St567Screen.elegirRecetaPreset
          : St567Screen.elegirReceta),
      'elegirtrabajo' => _desdePrincipal(_options.sinTrabajos
          ? St567Screen.sinTrabajos
          : St567Screen.trabajos),
      'descargamanual' => _descargaManual(command),
      'cambiaroperario' => _cambiarOperario(),
      'esc' => _esc(),
      'nextpage' => _paginar(1),
      'prevpage' => _paginar(-1),
      'detail' => _detail(command.arg(0)),
      'select' => _select(command),
      'selectingrediente' => _selectIngrediente(),
      'acum' => _acum(command),
      'lock' => _toggleLock(),
      'level' => _toggleLevel(),
      'rotate' => _rotate(),
      'boton1' => _boton(1),
      'boton2' => _boton(2),
      _ => 'CTR,${command.nombre} no lo usa el ST567: se ignora',
    };
    return log ??
        'CTR,${command.nombre} se ignora en la pantalla ${_screen.label}';
  }

  // Cada handler devuelve el log si aplicó el comando, o `null` si no
  // corresponde a la pantalla vigente.

  String? _sync() {
    if (_screen != St567Screen.principal) {
      return null;
    }
    _entrar(St567Screen.sincronizando);
    _porcentajeSync = 0;
    return 'Comando aplicado: CTR,sync -> sincronizando';
  }

  String? _toggleLevelLock() {
    if (_screen != St567Screen.principal) {
      return null;
    }
    _levelLock = !_levelLock;
    return 'Comando aplicado: CTR,levelLock -> ${_levelLock ? 'activo' : 'inactivo'}';
  }

  String? _hacerCero() {
    if (_screen != St567Screen.principal) {
      return null;
    }
    _cero = _pesoBalanza ?? _cero;
    return 'Comando aplicado: CTR,cero -> se descuentan $_cero kg';
  }

  String? _desdePrincipal(St567Screen destino) {
    if (_screen != St567Screen.principal) {
      return null;
    }
    _entrar(destino);
    return 'Comando aplicado -> ${destino.label}';
  }

  String? _descargaManual(St567Command command) {
    if (_screen != St567Screen.principal &&
        _screen != St567Screen.loteYCantidad) {
      return null;
    }
    final String lote = command.arg(0);
    final int? kg = _parseKg(command.arg(1));
    if (lote.isEmpty || kg == null) {
      return 'CTR,descargaManual necesita lote y cantidad: '
          '"${command.texto}" se ignora';
    }
    _lote = lote;
    _kgADescargar = kg;
    _parcial = 0;
    _entrar(St567Screen.descargaManual);
    return 'Comando aplicado: descarga manual del lote $lote, $kg kg';
  }

  String? _cambiarOperario() {
    if (_screen != St567Screen.principal &&
        _screen != St567Screen.cargaManual &&
        _screen != St567Screen.cargaReceta) {
      return null;
    }
    _volverDeOperario = _screen;
    _entrar(St567Screen.cambioOperario);
    return 'Comando aplicado -> ${St567Screen.cambioOperario.label}';
  }

  String _esc() {
    final St567Screen desde = _screen;
    switch (desde) {
      case St567Screen.principal:
        return 'CTR,esc en la pantalla principal: no hay a dónde volver';
      case St567Screen.detalleReceta:
        _entrar(
          _options.recetasConPreset
              ? St567Screen.elegirRecetaPreset
              : St567Screen.elegirReceta,
          mantenerPagina: true,
        );
      case St567Screen.detalleTrabajo:
      case St567Screen.reanudarTrabajo:
        _trabajoPorReanudar = null;
        _entrar(St567Screen.trabajos, mantenerPagina: true);
      case St567Screen.cambioOperario:
        _entrar(_volverDeOperario);
      case St567Screen.detalleGuia:
        _entrar(_volverDeGuia, mantenerPagina: true);
      case St567Screen.cargaManual:
      case St567Screen.descargaManual:
      case St567Screen.cargaReceta:
      case St567Screen.descargaGuia:
      case St567Screen.mezclando:
      case St567Screen.masCarga:
        _abandonar();
        _entrar(St567Screen.principal);
      default:
        _entrar(St567Screen.principal);
    }
    return 'Comando aplicado: CTR,esc -> ${_screen.label}';
  }

  String? _paginar(int delta) {
    final int? total = switch (_screen) {
      St567Screen.elegirReceta ||
      St567Screen.elegirRecetaPreset =>
        catalog.recetas.length,
      St567Screen.elegirIngrediente => catalog.ingredientes.length,
      St567Screen.trabajos => catalog.trabajos.length,
      _ => null,
    };
    if (total == null) {
      return null;
    }
    final int ultima = math.max(0, (total - 1) ~/ itemsPorPagina);
    final int siguiente = (_pagina + delta).clamp(0, ultima);
    if (siguiente == _pagina) {
      return 'CTR,${delta > 0 ? 'nextPage' : 'prevPage'}: no hay más páginas';
    }
    _pagina = siguiente;
    return 'Comando aplicado: página ${_pagina + 1} de ${ultima + 1}';
  }

  String? _detail(String indice) {
    switch (_screen) {
      case St567Screen.elegirReceta:
      case St567Screen.elegirRecetaPreset:
        final St567Receta? receta = catalog.receta(indice);
        if (receta == null) {
          return 'CTR,detail: no existe la receta $indice';
        }
        _recetaDetalle = receta;
        _entrar(St567Screen.detalleReceta, mantenerPagina: true);
        return 'Comando aplicado: detalle de la receta ${receta.nombre}';
      case St567Screen.trabajos:
        final St567Trabajo? trabajo = catalog.trabajo(indice);
        if (trabajo == null) {
          return 'CTR,detail: no existe el trabajo $indice';
        }
        _trabajoDetalle = trabajo;
        _entrar(St567Screen.detalleTrabajo, mantenerPagina: true);
        return 'Comando aplicado: detalle del trabajo ${trabajo.nombre}';
      default:
        return null;
    }
  }

  String? _select(St567Command command) {
    final String indice = command.arg(0);
    switch (_screen) {
      case St567Screen.elegirReceta:
      case St567Screen.elegirRecetaPreset:
        final St567Receta? receta = catalog.receta(indice);
        if (receta == null) {
          return 'CTR,select: no existe la receta $indice';
        }
        final int kg = _parseKg(command.arg(1)) ?? 0;
        _iniciarCarga(_Corrida.receta(receta, kg: kg > 0 ? kg : receta.preset));
        return 'Comando aplicado: carga de ${receta.nombre}, '
            '${_corrida!.totalReceta} kg';
      case St567Screen.elegirIngrediente:
        final St567Ingrediente? ingrediente = catalog.ingrediente(indice);
        final int? kg = _parseKg(command.arg(1));
        if (ingrediente == null || kg == null) {
          return 'CTR,select necesita un ingrediente y una cantidad: '
              '"${command.texto}" se ignora';
        }
        _ingrediente = ingrediente;
        _kgACargar = kg;
        _parcial = 0;
        _entrar(St567Screen.cargaManual);
        return 'Comando aplicado: carga manual de ${ingrediente.nombre}, $kg kg';
      case St567Screen.trabajos:
        final St567Trabajo? trabajo = catalog.trabajo(indice);
        if (trabajo == null) {
          return 'CTR,select: no existe el trabajo $indice';
        }
        if (_pausadas.containsKey(trabajo.indice)) {
          _trabajoPorReanudar = trabajo.indice;
          _entrar(St567Screen.reanudarTrabajo, mantenerPagina: true);
          return 'Comando aplicado: ${trabajo.nombre} quedó a medias -> '
              '¿reanudar?';
        }
        _iniciarTrabajo(trabajo);
        return 'Comando aplicado: inicia ${trabajo.nombre}';
      default:
        return null;
    }
  }

  String? _selectIngrediente() {
    if (_screen != St567Screen.cargaManual) {
      return null;
    }
    // Lo pesado del ingrediente anterior no se acumula: se cambió sin ACUM.
    _parcial = 0;
    _entrar(St567Screen.elegirIngrediente);
    return 'Comando aplicado -> ${St567Screen.elegirIngrediente.label}';
  }

  String? _acum(St567Command command) {
    final String operario = command.arg(0);
    final String quien = operario.isEmpty ? 'sin operario' : 'operario $operario';

    switch (_screen) {
      case St567Screen.cargaManual:
        _operario = operario;
        final int cargado = _parcial;
        _totalCargado += cargado;
        _parcial = 0;
        _entrar(St567Screen.elegirIngrediente);
        return 'Comando aplicado: ACUM $cargado kg de '
            '${_ingrediente?.nombre ?? '-'} ($quien)';
      case St567Screen.cargaReceta:
        _operario = operario;
        final _Corrida corrida = _corrida!;
        final _ItemCarga item = corrida.item;
        item.cargado = true;
        _totalCargado += _parcial;
        final String log =
            'Comando aplicado: ACUM $_parcial kg de ${item.ingrediente.nombre} '
            '($quien)';
        _parcial = 0;
        if (corrida.itemActual + 1 < corrida.items.length) {
          corrida.itemActual += 1;
        } else {
          _segundosMezcla = corrida.receta.mezclaSeg;
          _entrar(St567Screen.mezclando);
          return '$log -> receta completa, mezclando';
        }
        return log;
      case St567Screen.descargaGuia:
        _operario = operario;
        final _Corrida corrida = _corrida!;
        final _LoteDescarga lote = corrida.lote;
        lote.descargado = _parcial;
        _totalCargado = math.max(0, _totalCargado - _parcial);
        final String log =
            'Comando aplicado: ACUM $_parcial kg en ${lote.nombre} ($quien)';
        _parcial = 0;
        if (corrida.loteActual + 1 >= corrida.lotes.length) {
          final St567Trabajo trabajo = corrida.trabajo!;
          _completos.add(trabajo.indice);
          _pausadas.remove(trabajo.indice);
          _corrida = null;
          _entrar(St567Screen.principal);
          return '$log -> ${trabajo.nombre} terminado';
        }
        corrida.loteActual += 1;
        if (_totalCargado <= 0) {
          _entrar(St567Screen.masCarga);
          return '$log -> el mixer quedó vacío, hay que preparar más carga';
        }
        return log;
      case St567Screen.descargaManual:
        final int descargado = _parcial;
        _totalCargado = math.max(0, _totalCargado - descargado);
        _parcial = 0;
        _entrar(St567Screen.loteYCantidad);
        return 'Comando aplicado: ACUM $descargado kg en el lote $_lote -> '
            'pedir lote y cantidad';
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
    if (_screen != St567Screen.cargaReceta &&
        _screen != St567Screen.descargaGuia) {
      return null;
    }
    return 'Comando aplicado: CTR,rotate (acción del mixer, sin cambio de '
        'pantalla)';
  }

  String? _boton(int boton) {
    // Los diálogos 40 y 41 se pueden forzar desde la UI sin un trabajo detrás:
    // ahí cualquier botón vuelve a la principal.
    final bool sinTrabajo = switch (_screen) {
      St567Screen.masCarga => _corrida == null,
      St567Screen.reanudarTrabajo => _trabajoPorReanudar == null,
      _ => false,
    };
    if (sinTrabajo) {
      _entrar(St567Screen.principal);
      return 'CTR,boton$boton sin un trabajo en curso -> '
          '${St567Screen.principal.label}';
    }

    switch (_screen) {
      case St567Screen.masCarga:
        if (boton == 1) {
          // CONTINUAR: sigue con el próximo lote aunque el mixer esté vacío.
          _entrar(St567Screen.descargaGuia);
          return 'Comando aplicado: CONTINUAR -> sigue con '
              '${_corrida!.lote.nombre}';
        }
        // NUEVA: una carga nueva de la misma receta, por lo que falta
        // descargar; después de mezclar vuelve a los lotes pendientes.
        final _Corrida anterior = _corrida!;
        _iniciarCarga(anterior.recarga());
        return 'Comando aplicado: NUEVA -> carga de '
            '${_corrida!.totalReceta} kg para los lotes pendientes';
      case St567Screen.reanudarTrabajo:
        final String indice = _trabajoPorReanudar!;
        _trabajoPorReanudar = null;
        final _Corrida pausada = _pausadas.remove(indice)!;
        if (boton == 1) {
          _corrida = pausada;
          _parcial = pausada.parcialGuardado;
          _segundosMezcla = pausada.segundosMezclaGuardados;
          _entrar(pausada.pantallaGuardada);
          return 'Comando aplicado: CONTINUAR -> ${pausada.trabajo!.nombre} '
              'retoma en ${_screen.label}';
        }
        _iniciarTrabajo(pausada.trabajo!);
        return 'Comando aplicado: REINICIAR -> ${pausada.trabajo!.nombre} '
            'desde el principio';
      default:
        return null;
    }
  }

  // --- Corridas ---

  void _iniciarTrabajo(St567Trabajo trabajo) {
    final St567Receta? receta = catalog.receta(trabajo.receta);
    _iniciarCarga(_Corrida.trabajo(trabajo, receta: receta!));
  }

  void _iniciarCarga(_Corrida corrida) {
    _corrida = corrida;
    _parcial = 0;
    _entrar(St567Screen.cargaReceta);
  }

  /// Al terminar la mezcla un trabajo pasa a descargar sus lotes; una receta
  /// suelta termina ahí.
  String _terminarMezcla() {
    final _Corrida? corrida = _corrida;
    if (corrida != null && corrida.trabajo != null) {
      _parcial = 0;
      _entrar(St567Screen.descargaGuia);
      return 'ST567: mezcla terminada -> descarga de '
          '${corrida.trabajo!.nombre}';
    }
    _corrida = null;
    _entrar(St567Screen.principal);
    return 'ST567: mezcla terminada -> principal';
  }

  /// ESC en medio de una operación. Un trabajo queda en pausa para poder
  /// reanudarlo; lo demás se descarta. Lo que ya entró o salió del mixer con
  /// ACUM no se toca.
  void _abandonar() {
    final _Corrida? corrida = _corrida;
    final St567Trabajo? trabajo = corrida?.trabajo;
    if (corrida != null && trabajo != null) {
      corrida
        ..pantallaGuardada =
            _screen == St567Screen.masCarga ? St567Screen.descargaGuia : _screen
        ..parcialGuardado = _parcial
        ..segundosMezclaGuardados = _segundosMezcla;
      _pausadas[trabajo.indice] = corrida;
    }
    _corrida = null;
    _parcial = 0;
    _lock = false;
    _level = false;
    _volverDeOperario = St567Screen.principal;
  }

  // --- Tramas ---

  @override
  String encodePayload(ScaleMeasurement measurement) {
    final St567Pesaje? pesaje = _pesaje();
    switch (_screen) {
      case St567Screen.principal:
        return St567Payload.principal(
          peso: measurement.peso,
          estable: _estable,
          operario: _operario,
          fecha: _now(),
          levelLock: _levelLock,
        );
      case St567Screen.cargaManual:
        return St567Payload.cargaManual(
          pesaje!,
          nroIngrediente: _ingrediente?.indice ?? '',
          ingrediente: _ingrediente?.nombre ?? '',
        );
      case St567Screen.descargaManual:
        return St567Payload.descargaManual(pesaje!, lote: _lote);
      case St567Screen.cargaReceta:
        final _Corrida corrida = _corrida!;
        return St567Payload.cargaReceta(
          pesaje!,
          ingredienteActual: corrida.item.ingrediente.nombre,
          items: <({St567IngredienteReceta ingrediente, bool cargado})>[
            for (final _ItemCarga item in corrida.items)
              (ingrediente: item.ingrediente, cargado: item.cargado),
          ],
        );
      case St567Screen.descargaGuia:
        final _Corrida corrida = _corrida!;
        return St567Payload.descargaGuia(
          pesaje!,
          loteActual: corrida.lote.nombre,
          lotes: <({String nombre, int descargado, int total})>[
            for (int i = 0; i < corrida.lotes.length; i++)
              (
                nombre: corrida.lotes[i].nombre,
                // El lote en curso muestra lo que va descargando.
                descargado: i == corrida.loteActual
                    ? _parcial
                    : corrida.lotes[i].descargado,
                total: corrida.lotes[i].total,
              ),
          ],
        );
      case St567Screen.mezclando:
        return St567Payload.mezclando(_segundosMezcla);
      case St567Screen.sincronizando:
        return St567Payload.sincronizando(_porcentajeSync);
      case St567Screen.detalleReceta:
        return St567Payload.detalleReceta(_recetaDetalle!);
      case St567Screen.detalleTrabajo:
        final St567Trabajo trabajo = _trabajoDetalle!;
        final St567Receta receta = catalog.receta(trabajo.receta)!;
        return St567Payload.detalleTrabajo(
          trabajo,
          receta: receta,
          ingredientes: _escalar(receta, trabajo.kg),
        );
      case St567Screen.detalleGuia:
        final St567Trabajo trabajo = _trabajoGuia!;
        return St567Payload.detalleGuia(trabajo.guia, trabajo.lotes);
      case St567Screen.elegirReceta:
        return St567Payload.recetas(_paginaDe(catalog.recetas));
      case St567Screen.elegirRecetaPreset:
        return St567Payload.recetasConPreset(_paginaDe(catalog.recetas));
      case St567Screen.elegirIngrediente:
        return St567Payload.ingredientes(_paginaDe(catalog.ingredientes));
      case St567Screen.trabajos:
        return St567Payload.trabajos(
          _paginaDe(catalog.trabajos),
          completo: (St567Trabajo t) => _completos.contains(t.indice),
        );
      case St567Screen.cambioOperario:
        return St567Payload.operarios(catalog.operarios);
      case St567Screen.sinOperario:
      case St567Screen.cargaRealizada:
      case St567Screen.sinTrabajos:
      case St567Screen.loteYCantidad:
      case St567Screen.sincronizacionFallida:
      case St567Screen.sincronizacionExitosa:
      case St567Screen.masCarga:
      case St567Screen.reanudarTrabajo:
      case St567Screen.operarioNoEncontrado:
      case St567Screen.claveIncorrecta:
      case St567Screen.indicadorOcupado:
        return St567Payload.frame(_screen);
    }
  }

  /// Los campos de peso de la pantalla vigente, o `null` si no es una de las
  /// cuatro pantallas de peso.
  St567Pesaje? _pesaje() {
    switch (_screen) {
      case St567Screen.cargaManual:
        return _armarPesaje(
          total: _totalCargado + _parcial,
          objetivo: _kgACargar,
          avisoKg: _kgACargar * avisoPorcentaje ~/ 100,
        );
      case St567Screen.cargaReceta:
        final _ItemCarga item = _corrida!.item;
        return _armarPesaje(
          total: _totalCargado + _parcial,
          objetivo: item.cantidad,
          avisoKg: item.avisoKg,
        );
      case St567Screen.descargaManual:
        return _armarPesaje(
          total: _totalCargado - _parcial,
          objetivo: _kgADescargar,
          avisoKg: _kgADescargar * avisoPorcentaje ~/ 100,
        );
      case St567Screen.descargaGuia:
        final _LoteDescarga lote = _corrida!.lote;
        return _armarPesaje(
          total: _totalCargado - _parcial,
          objetivo: lote.total,
          avisoKg: lote.total * avisoPorcentaje ~/ 100,
        );
      default:
        return null;
    }
  }

  St567Pesaje _armarPesaje({
    required int total,
    required int objetivo,
    required int avisoKg,
  }) {
    return St567Pesaje(
      total: total,
      parcial: _parcial,
      objetivo: objetivo,
      lock: _lock,
      level: _level,
      // Sin objetivo (descarga manual con kg en 0) no hay a qué avisar.
      sirena: objetivo > 0 && objetivo - _parcial <= avisoKg,
    );
  }

  /// El número grande de la app: lo que falta, o lo descargado si no hay
  /// objetivo.
  int _pesoGrande(St567Pesaje pesaje) => pesaje.objetivo > 0
      ? pesaje.objetivo - pesaje.parcial
      : pesaje.parcial.abs();

  String _detalle() {
    final St567Pesaje? pesaje = _pesaje();
    switch (_screen) {
      case St567Screen.cargaManual:
        return 'Cargando ${_ingrediente?.nombre ?? '-'}: '
            '${pesaje!.parcial}/${pesaje.objetivo} kg';
      case St567Screen.cargaReceta:
        return 'Cargando ${_corrida!.item.ingrediente.nombre} '
            '(${_corrida!.receta.nombre}): '
            '${pesaje!.parcial}/${pesaje.objetivo} kg';
      case St567Screen.descargaManual:
        return 'Descargando lote $_lote: ${pesaje!.parcial}/'
            '${pesaje.objetivo > 0 ? pesaje.objetivo : '-'} kg';
      case St567Screen.descargaGuia:
        return 'Descargando ${_corrida!.lote.nombre}: '
            '${pesaje!.parcial}/${pesaje.objetivo} kg';
      case St567Screen.mezclando:
        return 'Mezclando: quedan $_segundosMezcla s';
      case St567Screen.sincronizando:
        return 'Sincronizando: $_porcentajeSync %';
      default:
        return '';
    }
  }

  // --- Utilidades ---

  void _entrar(St567Screen screen, {bool mantenerPagina = false}) {
    _screen = screen;
    if (!mantenerPagina) {
      _pagina = 0;
    }
    _ticksEnPopup = 0;
  }

  /// Un paso de la animación de carga o descarga: [objetivo] se completa en
  /// [ticksPorPaso] ticks, sin pasarse de [tope].
  int _avanzar(int actual, {required int tope, required int objetivo}) {
    if (actual >= tope) {
      return actual;
    }
    final int paso = math.max(1, (objetivo / ticksPorPaso).ceil());
    return math.min(tope, actual + paso);
  }

  List<T> _paginaDe<T>(List<T> items) {
    final int desde = _pagina * itemsPorPagina;
    if (desde >= items.length) {
      return <T>[];
    }
    final int hasta = math.min(desde + itemsPorPagina, items.length);
    return items.sublist(desde, hasta);
  }

  /// Los kilos que manda la app (`CTR,select,<i>,<kg>`). El diálogo sólo deja
  /// cargar dígitos, pero se tolera un decimal por las dudas.
  static int? _parseKg(String value) {
    final double? kg = double.tryParse(value.trim());
    if (kg == null || kg < 0) {
      return null;
    }
    return kg.round();
  }
}

/// Las cantidades de [receta] llevadas a [kg] kilos. El redondeo se lo come el
/// último ingrediente, para que la suma dé exacto.
List<St567IngredienteReceta> _escalar(St567Receta receta, int kg) {
  final int base = receta.ingredientes
      .fold<int>(0, (int suma, St567IngredienteReceta i) => suma + i.cantidad);
  if (kg <= 0 || base <= 0 || kg == base) {
    return receta.ingredientes;
  }
  int asignado = 0;
  final List<St567IngredienteReceta> escalados = <St567IngredienteReceta>[];
  for (int i = 0; i < receta.ingredientes.length; i++) {
    final St567IngredienteReceta ing = receta.ingredientes[i];
    final bool ultimo = i == receta.ingredientes.length - 1;
    final int cantidad =
        ultimo ? kg - asignado : (ing.cantidad * kg / base).round();
    asignado += cantidad;
    escalados.add(St567IngredienteReceta(
      ing.nombre,
      cantidad,
      tipoAviso: ing.tipoAviso,
      aviso: ing.aviso,
      mezclaSeg: ing.mezclaSeg,
    ));
  }
  return escalados;
}

class _ItemCarga {
  _ItemCarga(this.ingrediente);

  final St567IngredienteReceta ingrediente;
  bool cargado = false;

  int get cantidad => ingrediente.cantidad;

  /// El aviso anticipado en kilos: tal cual si es en kg, o como porcentaje de
  /// la cantidad.
  int get avisoKg => ingrediente.tipoAviso == 0
      ? ingrediente.aviso
      : cantidad * ingrediente.aviso ~/ 100;
}

class _LoteDescarga {
  _LoteDescarga(this.nombre, this.total);

  final String nombre;
  final int total;
  int descargado = 0;
}

/// Una carga por receta y, si viene de un trabajo, la descarga de sus lotes.
class _Corrida {
  _Corrida._({
    required this.receta,
    required this.items,
    required this.trabajo,
    required this.lotes,
  });

  factory _Corrida.receta(St567Receta receta, {required int kg}) {
    return _Corrida._(
      receta: receta,
      items: <_ItemCarga>[
        for (final St567IngredienteReceta i in _escalar(receta, kg))
          _ItemCarga(i),
      ],
      trabajo: null,
      lotes: const <_LoteDescarga>[],
    );
  }

  factory _Corrida.trabajo(St567Trabajo trabajo, {required St567Receta receta}) {
    return _Corrida._(
      receta: receta,
      items: <_ItemCarga>[
        for (final St567IngredienteReceta i in _escalar(receta, trabajo.kg))
          _ItemCarga(i),
      ],
      trabajo: trabajo,
      lotes: <_LoteDescarga>[
        for (final St567Lote l in trabajo.lotes) _LoteDescarga(l.nombre, l.kg),
      ],
    );
  }

  final St567Receta receta;
  final List<_ItemCarga> items;
  final St567Trabajo? trabajo;
  final List<_LoteDescarga> lotes;
  int itemActual = 0;
  int loteActual = 0;

  // Dónde estaba al pausarse con ESC, para CONTINUAR desde el diálogo 41.
  St567Screen pantallaGuardada = St567Screen.cargaReceta;
  int parcialGuardado = 0;
  int segundosMezclaGuardados = 0;

  _ItemCarga get item => items[itemActual];
  _LoteDescarga get lote => lotes[loteActual];

  int get totalReceta =>
      items.fold<int>(0, (int suma, _ItemCarga i) => suma + i.cantidad);

  /// Carga nueva de la misma receta por lo que falta descargar, conservando
  /// los lotes y el lote en curso.
  _Corrida recarga() {
    int falta = 0;
    for (int i = loteActual; i < lotes.length; i++) {
      falta += lotes[i].total - lotes[i].descargado;
    }
    return _Corrida._(
      receta: receta,
      items: <_ItemCarga>[
        for (final St567IngredienteReceta i in _escalar(receta, falta))
          _ItemCarga(i),
      ],
      trabajo: trabajo,
      lotes: lotes,
    )..loteActual = loteActual;
  }
}
