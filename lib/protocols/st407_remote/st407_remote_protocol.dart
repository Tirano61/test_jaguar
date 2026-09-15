import 'package:test_jaguar/core/constants/ble_constants.dart';
import 'package:test_jaguar/domain/entities/scale_measurement.dart';
import 'package:test_jaguar/domain/value_objects/send_protocol.dart';
import 'package:test_jaguar/protocols/payload_framing.dart';
import 'package:test_jaguar/protocols/simulator_protocol.dart';
import 'package:test_jaguar/protocols/st407_remote/st407_payload.dart';
import 'package:test_jaguar/protocols/st407_remote/st407_screen.dart';

/// Protocolo Remoto ST407: el único que no manda JSON.
///
/// Notifica una cadena separada por coma por cada pantalla del indicador
/// (códigos 100-108), sobre el perfil ABF3 y con cabecera binaria de 5 bytes.
///
/// Tiene dos automatismos propios, ambos atados al ritmo de envío y no a un
/// timer: en las pantallas de carga el peso mostrado baja de a 1 kg mientras
/// "kg a cargar" queda fijo, y en la de mezclado corre una cuenta regresiva
/// desde 4:30.
class St407RemoteProtocol implements SimulatorProtocol {
  St407RemoteProtocol({DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Reloj de la pantalla principal, inyectable para poder fijar la cadena
  /// exacta en los tests.
  final DateTime Function() _now;

  @override
  SendProtocol get id => SendProtocol.st407Remote;

  @override
  BleUuids get bleUuids => BleConstants.remotoAbf3;

  @override
  PayloadFraming get framing => PayloadFraming.fiveByteHeader;

  /// Duración de la mezcla: 4:30, igual que el indicador real.
  static const int _mixingSeconds = 4 * 60 + 30;

  /// Cuánto baja por envío el peso mostrado en las pantallas de carga.
  static const double _loadingDecrementPerTick = 1.0;

  St407Screen _screen = St407Screen.main;

  /// "kg a cargar": se congela al entrar a una pantalla de carga y no se mueve
  /// mientras dure.
  double? _initialKgToLoad;

  /// Peso mostrado en la pantalla de carga, que va bajando.
  double _currentDisplayedPeso = 0.0;
  bool _loadingActive = false;
  bool _mixingCountdownActive = false;
  int _mixingCurrentSeconds = _mixingSeconds;

  St407Screen get screen => _screen;

  /// Selecciona la pantalla. Devuelve `false` si ya estaba en esa, que es
  /// cuando el orquestador no hace absolutamente nada.
  ///
  /// Sembrar sus contadores es un paso aparte ([seedScreenState]) porque el
  /// orquestador cambia y loguea la pantalla aunque este protocolo no esté
  /// activo, pero sólo siembra cuando sí lo está.
  bool selectScreen(St407Screen screen) {
    if (_screen == screen) {
      return false;
    }
    _screen = screen;
    return true;
  }

  /// Siembra los contadores de la pantalla vigente. [currentPeso] es el último
  /// peso emitido, de donde las pantallas de carga toman su "kg a cargar".
  void seedScreenState({required int currentPeso}) {
    if (_screen == St407Screen.loadingRecipe ||
        _screen == St407Screen.loadingManual) {
      _initialKgToLoad = currentPeso.toDouble();
      // El peso mostrado parte del peso actual y luego irá bajando.
      _currentDisplayedPeso = _initialKgToLoad ?? 0.0;
      _loadingActive = true;
      _mixingCountdownActive = false;
      _mixingCurrentSeconds = _mixingSeconds;
    } else if (_screen == St407Screen.mixing) {
      _resetLoading();
      _mixingCountdownActive = true;
      _mixingCurrentSeconds = _mixingSeconds;
    } else {
      _resetLoading();
      _mixingCountdownActive = false;
      _mixingCurrentSeconds = _mixingSeconds;
    }
  }

  /// Descarta los contadores al salir del modo.
  void resetRunState() {
    _resetLoading();
    _mixingCountdownActive = false;
    _mixingCurrentSeconds = _mixingSeconds;
  }

  /// `true` si la pantalla vigente anima el peso por su cuenta y por lo tanto
  /// ignora el que trae el motor de simulación.
  bool get isLoadingScreen =>
      _screen == St407Screen.loadingRecipe ||
      _screen == St407Screen.loadingManual;

  /// Un tick en una pantalla de carga: baja el peso mostrado de a 1 kg.
  ///
  /// [base] es la medición del motor, que sólo se usa para sembrar si todavía
  /// no se sembró; el peso que sale es el de la animación.
  ScaleMeasurement advanceLoading(ScaleMeasurement base) {
    _ensureLoadingSeeded(base.peso);

    double next = _currentDisplayedPeso - _loadingDecrementPerTick;
    if (next < 0.0) {
      next = 0.0;
    }
    _currentDisplayedPeso = next;

    return base.copyWith(peso: _currentDisplayedPeso.round());
  }

  /// Cadena que viaja por notify para la pantalla vigente.
  ///
  /// Ojo: **no es un formateador puro**. En la pantalla de mezclado éste es el
  /// único lugar donde avanza la cuenta regresiva, y en las de carga siembra
  /// los contadores si hicieran falta. Es el comportamiento original y hay un
  /// test que lo fija (`AT+CERO` en mezclado roba un segundo justamente porque
  /// dispara un envío extra).
  @override
  String encodePayload(ScaleMeasurement measurement) {
    if (isLoadingScreen) {
      _ensureLoadingSeeded(measurement.peso);

      // "kg a cargar" mantiene el valor inicial; el peso actual es el que llega
      // ya animado, y "parcial" es lo que se descargó (inicial - actual).
      final double initial = _initialKgToLoad ?? measurement.peso.toDouble();
      final double pesoActual = measurement.peso.toDouble();
      final int parcial =
          (initial - pesoActual).clamp(0.0, double.infinity).round();
      final int kgACargar = initial.round();

      if (_screen == St407Screen.loadingRecipe) {
        // pantalla,peso_actual,parcial,kg_a_cargar,ingrediente
        return '${_screen.code},${pesoActual.round()},$parcial,$kgACargar,Maiz\r\n';
      }
      // La pantalla manual manda un identificador en vez del ingrediente.
      return '${_screen.code},${pesoActual.round()},$parcial,$kgACargar,1\r\n';
    }

    if (_screen == St407Screen.mixing) {
      if (!_mixingCountdownActive) {
        _mixingCountdownActive = true;
        _mixingCurrentSeconds = _mixingSeconds;
      }

      // formato pantalla,minutos,segundos — arranca en 4,30 y baja como reloj.
      final int minutes = _mixingCurrentSeconds ~/ 60;
      final int seconds = _mixingCurrentSeconds % 60;
      final String payload =
          '${_screen.code},$minutes,${seconds.toString().padLeft(2, '0')}\r\n';

      if (_mixingCurrentSeconds > 0) {
        _mixingCurrentSeconds -= 1;
      }
      return payload;
    }

    return St407PayloadDto(
      screen: _screen,
      measurement: measurement,
      now: _now(),
    ).toProtocolString();
  }

  /// Las pantallas de carga se siembran en dos lugares distintos, uno por cada
  /// camino de envío: el del tick y el de los envíos fuera del tick. Duplicarlo
  /// era el comportamiento original y hay que conservarlo, porque cada camino
  /// es el único que corre en su situación.
  void _ensureLoadingSeeded(int peso) {
    if (!_loadingActive || _initialKgToLoad == null) {
      _initialKgToLoad = peso.toDouble();
      _currentDisplayedPeso = _initialKgToLoad ?? peso.toDouble();
      _loadingActive = true;
    }
  }

  void _resetLoading() {
    _loadingActive = false;
    _initialKgToLoad = null;
    _currentDisplayedPeso = 0.0;
  }
}
