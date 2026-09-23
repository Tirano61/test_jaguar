import 'package:test_jaguar/core/constants/ble_constants.dart';
import 'package:test_jaguar/core/constants/payload_framing.dart';
import 'package:test_jaguar/domain/entities/scale_measurement.dart';
import 'package:test_jaguar/domain/value_objects/send_protocol.dart';
import 'package:test_jaguar/protocols/simulator_protocol.dart';
import 'package:test_jaguar/protocols/st567/st567_catalog.dart';
import 'package:test_jaguar/protocols/st567/st567_payload.dart';
import 'package:test_jaguar/protocols/st567/st567_screen.dart';
import 'package:test_jaguar/protocols/st567/st567_state.dart';

/// Protocolo Remoto ST567 (`docs/protocolo-simulador-st567.md`).
///
/// Comparte con el ST407 el perfil GATT (ABF3, notify en ABF5, write en ABF4)
/// y la cabecera binaria de 5 bytes, pero no el formato: las pantallas van de
/// `0` a `60` y cada una tiene sus propios campos.
///
/// El simulador hace de indicador: guarda en qué pantalla está y arma su trama
/// con los datos de [St567Catalog]. [encodePayload] es puro; lo que avanza con
/// el tiempo (estabilidad, popups que se cierran solos) avanza en [advance],
/// que el orquestador llama una vez por tick del motor.
class St567Protocol implements SimulatorProtocol {
  St567Protocol({
    DateTime Function()? now,
    this.catalog = St567Catalog.demo,
  }) : _now = now ?? DateTime.now;

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

  St567Screen _screen = St567Screen.principal;
  int _pagina = 0;
  int _ticksEnPopup = 0;

  /// Peso del tick anterior: la balanza está estable si no cambió.
  int? _pesoAnterior;
  bool _estable = true;

  St567State get state => St567State(screen: _screen);

  St567Screen get screen => _screen;

  /// Salta a [screen] a pedido del tester. Devuelve la línea de log, o `null`
  /// si ya estaba en esa pantalla.
  String? goTo(St567Screen screen) {
    if (_screen == screen) {
      return null;
    }
    _entrar(screen);
    return 'Pantalla ST567 seleccionada: ${screen.label}';
  }

  /// Un tick del motor. [base] es la medición de la balanza; sale igual, porque
  /// el peso de la pantalla principal es el del motor.
  ScaleMeasurement advance(
    ScaleMeasurement base, {
    required void Function(String line) log,
  }) {
    _estable = _pesoAnterior == null || _pesoAnterior == base.peso;
    _pesoAnterior = base.peso;

    if (_screen.isPopup && _screen != St567Screen.indicadorOcupado) {
      _ticksEnPopup += 1;
      if (_ticksEnPopup >= ticksPopup) {
        log('ST567: se cierra el popup ${_screen.code} y vuelve a la principal');
        _entrar(St567Screen.principal);
      }
    }
    return base;
  }

  /// Descarta lo que dure una sesión al salir del modo.
  void resetRunState() {
    _entrar(St567Screen.principal);
    _pesoAnterior = null;
    _estable = true;
  }

  @override
  String encodePayload(ScaleMeasurement measurement) {
    switch (_screen) {
      case St567Screen.principal:
        return St567Payload.principal(
          peso: measurement.peso,
          estable: _estable,
          operario: '',
          fecha: _now(),
          levelLock: false,
        );
      case St567Screen.elegirReceta:
        return St567Payload.recetas(_paginaDe(catalog.recetas));
      case St567Screen.elegirRecetaPreset:
        return St567Payload.recetasConPreset(_paginaDe(catalog.recetas));
      case St567Screen.elegirIngrediente:
        return St567Payload.ingredientes(_paginaDe(catalog.ingredientes));
      case St567Screen.trabajos:
        return St567Payload.trabajos(
          _paginaDe(catalog.trabajos),
          completo: (St567Trabajo t) => t.completo,
        );
      case St567Screen.cambioOperario:
        return St567Payload.operarios(catalog.operarios);
      case St567Screen.cargaManual:
      case St567Screen.descargaManual:
      case St567Screen.mezclando:
      case St567Screen.sincronizando:
      case St567Screen.detalleTrabajo:
      case St567Screen.detalleReceta:
      case St567Screen.cargaReceta:
      case St567Screen.descargaGuia:
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

  void _entrar(St567Screen screen) {
    _screen = screen;
    _pagina = 0;
    _ticksEnPopup = 0;
  }

  List<T> _paginaDe<T>(List<T> items) {
    final int desde = _pagina * itemsPorPagina;
    if (desde >= items.length) {
      return <T>[];
    }
    final int hasta = (desde + itemsPorPagina).clamp(0, items.length);
    return items.sublist(desde, hasta);
  }
}
