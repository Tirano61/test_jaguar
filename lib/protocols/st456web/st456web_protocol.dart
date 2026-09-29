import 'dart:math' as math;

import 'package:test_jaguar/core/constants/ble_constants.dart';
import 'package:test_jaguar/core/constants/payload_framing.dart';
import 'package:test_jaguar/domain/entities/scale_measurement.dart';
import 'package:test_jaguar/domain/value_objects/send_protocol.dart';
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
/// El simulador hace de indicador: guarda en qué pantalla está y arma cada
/// trama con los datos de [St456webCatalog].
class St456webProtocol implements SimulatorProtocol {
  St456webProtocol({
    DateTime Function()? now,
    this.catalog = St456webCatalog.demo,
  }) : _now = now ?? DateTime.now;

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

  /// Cuántos ticks queda un popup sin botones antes de volver a la principal.
  /// La app no tiene cómo cerrarlos; el `45` (indicador ocupado) no se cierra
  /// solo porque en el equipo real dura lo que el operador tarde en salir del
  /// menú.
  static const int ticksPopup = 3;

  St456webScreen _screen = St456webScreen.principal;
  int _pagina = 0;
  int _ticksEnPopup = 0;

  /// Peso del tick anterior: la balanza está estable si no cambió.
  int? _pesoAnterior;
  bool _estable = true;

  // Lo que muestran las pantallas de selección de a un ítem (`8`, `9`, `10`).
  int _receta = 0;
  int _autonomo = 0;
  int _guia = 0;

  St456webScreen get screen => _screen;

  St456webState get state => St456webState(screen: _screen);

  /// Salta a [screen] a pedido del tester. Devuelve la línea de log, o `null`
  /// si ya estaba en esa pantalla.
  String? goTo(St456webScreen screen) {
    if (_screen == screen) {
      return null;
    }
    _entrar(screen);
    return 'Pantalla ST456web seleccionada: ${screen.label}';
  }

  /// Un tick del motor. [base] es la medición de la balanza; sale igual,
  /// porque el peso de la pantalla principal es el del motor.
  ScaleMeasurement advance(
    ScaleMeasurement base, {
    required void Function(String line) log,
  }) {
    _estable = _pesoAnterior == null || _pesoAnterior == base.peso;
    _pesoAnterior = base.peso;

    if (_screen.isPopup && _screen != St456webScreen.indicadorOcupado) {
      _ticksEnPopup += 1;
      if (_ticksEnPopup >= ticksPopup) {
        log('ST456web: se cierra el popup ${_screen.code} y vuelve a la '
            'principal');
        _entrar(St456webScreen.principal);
      }
    }
    return base;
  }

  /// Descarta lo que dure una sesión al salir del modo.
  void resetRunState() {
    _entrar(St456webScreen.principal);
    _pesoAnterior = null;
    _estable = true;
    _receta = 0;
    _autonomo = 0;
    _guia = 0;
  }

  @override
  String encodePayload(ScaleMeasurement measurement) {
    switch (_screen) {
      case St456webScreen.principal:
        return St456webPayload.principal(
          peso: measurement.peso,
          estable: _estable,
          operario: '',
          fecha: _now(),
        );
      case St456webScreen.elegirReceta:
        return St456webPayload.receta(catalog.recetas[_receta]);
      case St456webScreen.elegirAutonomo:
        return St456webPayload.autonomo(catalog.autonomos[_autonomo]);
      case St456webScreen.elegirGuia:
        return St456webPayload.guia(catalog.guias[_guia]);
      case St456webScreen.trabajos:
        return St456webPayload.trabajos(
          _paginaDe(catalog.trabajos),
          completo: (St456webTrabajo t) => t.completo,
        );
      case St456webScreen.usarParcial:
        return St456webPayload.parcial(catalog.recetas[_receta].cantidad);
      case St456webScreen.detalle:
        return _detalle(catalog.trabajos.first);
      case St456webScreen.sincronizando:
        return St456webPayload.sincronizando(0);
      case St456webScreen.cambioOperario:
        return St456webPayload.operarios(catalog.operarios);
      case St456webScreen.cargaReceta:
      case St456webScreen.cargaManual:
      case St456webScreen.descargaGuia:
      case St456webScreen.descargaManual:
      case St456webScreen.mezclando:
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
  String _detalle(St456webTrabajo trabajo) {
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

  void _entrar(St456webScreen screen) {
    _screen = screen;
    _pagina = 0;
    _ticksEnPopup = 0;
  }

  List<T> _paginaDe<T>(List<T> items) {
    final int desde = _pagina * itemsPorPagina;
    if (desde >= items.length) {
      return <T>[];
    }
    final int hasta = math.min(desde + itemsPorPagina, items.length);
    return items.sublist(desde, hasta);
  }
}
