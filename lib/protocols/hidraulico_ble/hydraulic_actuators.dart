import 'dart:math';

/// Estado del tubo tal como lo ve la app conectada.
///
/// En el equipo real el tubo tiene **un sensor de fin de carrera, no un
/// encoder**: sólo se sabe si está abierto o cerrado. Los otros dos valores
/// dicen que se está moviendo. Por eso el JSON manda el estado y no una
/// posición: el recorrido se simula por tiempo.
abstract final class TubeState {
  static const int cerrado = 0;
  static const int abierto = 1;
  static const int abriendo = 2;
  static const int cerrando = 3;

  static String label(int value) {
    switch (value) {
      case cerrado:
        return 'CERRADO';
      case abierto:
        return 'ABIERTO';
      case abriendo:
        return 'ABRIENDO';
      case cerrando:
        return 'CERRANDO';
      default:
        return 'DESCONOCIDO ($value)';
    }
  }
}

/// Un actuador que recorre de cerrado (0.0) a abierto (1.0) en un tiempo dado.
///
/// El recorrido se guarda como fracción, no como tiempo transcurrido, para que
/// invertir la marcha a mitad de camino funcione solo: si viene abriendo hace
/// 7 s de 15 y le llega "cerrar", cierra desde donde quedó y tarda esos mismos
/// 7 s en volver.
class _LinearActuator {
  double _progress = 0.0;
  double? _target;
  double _ratePerSecond = 0.0;

  double get progress => _progress;

  bool get isMoving => _target != null;

  /// `true` si se está abriendo, `false` si se está cerrando, `null` si está
  /// quieto.
  bool? get opening => _target == null ? null : _target! > _progress;

  /// Manda el actuador a [target] (0.0 - 1.0) recorriendo el trayecto completo
  /// en [fullTravel]. Desde una posición intermedia tarda proporcionalmente
  /// menos.
  void moveTo(double target, {required Duration fullTravel}) {
    final double clamped = target.clamp(0.0, 1.0);
    if (_progress == clamped) {
      _target = null;
      return;
    }
    _target = clamped;
    _ratePerSecond = 1000.0 / fullTravel.inMilliseconds;
  }

  /// Corta el movimiento donde esté.
  void freeze() {
    _target = null;
  }

  /// Salta a [value] sin animación.
  void jumpTo(double value) {
    _progress = value.clamp(0.0, 1.0);
    _target = null;
  }

  /// Lo deja cerrado y quieto, sin animación.
  void reset() {
    _progress = 0.0;
    _target = null;
  }

  /// Avanza [elapsed]. Devuelve `true` si en este paso llegó al destino.
  bool advance(Duration elapsed) {
    final double? target = _target;
    if (target == null) {
      return false;
    }

    final double step = _ratePerSecond * elapsed.inMilliseconds / 1000.0;
    // La tolerancia no es cosmética: sumar 1/6 seis veces no da exactamente
    // 1.0, y sin ella el recorrido tardaría un paso de más (7 s en vez de 6).
    if ((target - _progress).abs() <= step + 1e-9) {
      _progress = target;
      _target = null;
      return true;
    }
    _progress += target > _progress ? step : -step;
    return false;
  }
}

/// El tubo de descarga.
///
/// Dos velocidades, porque son dos cosas distintas: el ciclo automático de la
/// descarga lo abre y lo cierra en 6 s, y el movimiento manual por
/// `AT+MOVIMIENTO` tarda 15 s de recorrido completo.
class HydraulicTube {
  /// Lo que tarda el ciclo de descarga en abrirlo o cerrarlo.
  static const Duration dischargeTravel = Duration(seconds: 6);

  /// Lo que tarda un `AT+MOVIMIENTO` en recorrerlo entero.
  static const Duration manualTravel = Duration(seconds: 15);

  final _LinearActuator _actuator = _LinearActuator();

  /// El valor que viaja en la key `tubo` del JSON.
  int get state {
    final bool? opening = _actuator.opening;
    if (opening != null) {
      return opening ? TubeState.abriendo : TubeState.cerrando;
    }
    return _actuator.progress >= 1.0 ? TubeState.abierto : TubeState.cerrado;
  }

  bool get isMoving => _actuator.isMoving;

  bool get isOpen => state == TubeState.abierto;

  /// Sólo para la barra de la UI del simulador: la app conectada no recibe
  /// esto, porque el equipo real no lo sabe.
  double get progress => _actuator.progress;

  void openForDischarge() =>
      _actuator.moveTo(1.0, fullTravel: dischargeTravel);

  void closeAfterDischarge() =>
      _actuator.moveTo(0.0, fullTravel: dischargeTravel);

  void moveManually({required bool opening}) =>
      _actuator.moveTo(opening ? 1.0 : 0.0, fullTravel: manualTravel);

  void reset() => _actuator.reset();

  bool advance(Duration elapsed) => _actuator.advance(elapsed);
}

/// La guillotina, que sí reporta posición: la key `gillo` va de 0 (cerrada) a
/// 100 (totalmente abierta).
class HydraulicGuillotine {
  HydraulicGuillotine({Random? random}) : _random = random ?? Random();

  /// Recorrido completo, igual para el movimiento manual y para las aperturas
  /// y cierres del ciclo de descarga.
  static const Duration travel = Duration(seconds: 15);

  /// A cuánto se abre al arrancar una descarga.
  static const int dischargeOpenPercent = 25;

  /// Entre qué valores va variando mientras dura la descarga.
  static const int dischargeMinPercent = 25;
  static const int dischargeMaxPercent = 80;

  /// Cada cuánto elige un valor nuevo durante la descarga.
  static const Duration dischargeShuffleInterval = Duration(seconds: 5);

  final Random _random;
  final _LinearActuator _actuator = _LinearActuator();
  Duration _sinceLastShuffle = Duration.zero;

  /// El valor que viaja en la key `gillo` del JSON.
  int get percent => (_actuator.progress * 100).round();

  bool get isMoving => _actuator.isMoving;

  void openForDischarge() {
    _sinceLastShuffle = Duration.zero;
    _moveToPercent(dischargeOpenPercent);
  }

  void close() => _moveToPercent(0);

  void moveManually({required bool opening}) =>
      _actuator.moveTo(opening ? 1.0 : 0.0, fullTravel: travel);

  void reset() {
    _actuator.reset();
    _sinceLastShuffle = Duration.zero;
  }

  bool advance(Duration elapsed) => _actuator.advance(elapsed);

  /// Vaivén de la descarga: cada [dischargeShuffleInterval] salta a un valor al
  /// azar entre [dischargeMinPercent] y [dischargeMaxPercent].
  ///
  /// Salta en vez de animar porque es una válvula regulando caudal, no una
  /// apertura completa. Devuelve el valor nuevo, o `null` si todavía no tocaba.
  int? shuffleDuringDischarge(Duration elapsed) {
    _sinceLastShuffle += elapsed;
    if (_sinceLastShuffle < dischargeShuffleInterval) {
      return null;
    }
    _sinceLastShuffle = Duration.zero;

    final int next = dischargeMinPercent +
        _random.nextInt(dischargeMaxPercent - dischargeMinPercent + 1);
    _actuator.jumpTo(next / 100.0);
    return next;
  }

  void _moveToPercent(int target) =>
      _actuator.moveTo(target / 100.0, fullTravel: travel);
}
