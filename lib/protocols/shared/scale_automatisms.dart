import 'package:test_jaguar/domain/entities/scale_measurement.dart';

/// Los automatismos que imitan a una balanza real: congelar el peso cuando el
/// sensor cambia y reportar si está estable.
///
/// Los comparten **Jaguar BLE y Remoto ST407** (este último fuera de sus
/// pantallas de carga, que animan el peso por su cuenta). Manual los tiene
/// apagados y el Hidráulico no los usa.
///
/// El orquestador guarda **una sola instancia** y se la presta al protocolo
/// activo. No puede haber una por protocolo: el peso que se congela sale del
/// último peso emitido *globalmente*, así que después de un cambio de Manual a
/// Jaguar lo que queda congelado es el peso manual. Y [reset] corre en cada
/// cambio de protocolo, para cualquiera que entre.
class ScaleAutomatisms {
  ScaleAutomatisms({required int sensorInduc}) : _lastSensorInduc = sensorInduc;

  /// Cuántos ticks queda congelado el peso tras un cambio de `sensorInduc`.
  static const int holdTicksAfterSensorChange = 5;

  int _lastSensorInduc;
  int _ticksRemaining = 0;
  int? _heldWeight;

  /// Lo que la UI muestra como "peso congelado: Ns".
  ///
  /// Arranca en 4 y no en 5: el contador se decrementa dentro del mismo tick
  /// en que se dispara, antes de reportarse.
  int get holdSecondsRemaining => _ticksRemaining;

  /// Cancela un congelado en curso. Lo llama el cambio de protocolo, porque el
  /// peso congelado pertenece al modo que se está dejando.
  void reset({required int sensorInduc}) {
    _ticksRemaining = 0;
    _heldWeight = null;
    _lastSensorInduc = sensorInduc;
  }

  /// Aplica el congelado y después la estabilidad, en ese orden.
  ///
  /// [lastEmitted] es la última medición que salió por notify, de cualquier
  /// protocolo: de ahí sale tanto el peso a congelar como la comparación de
  /// estabilidad.
  ScaleMeasurement apply(
    ScaleMeasurement measurement, {
    required ScaleMeasurement lastEmitted,
    required void Function(String) log,
  }) {
    return _withStability(
      _withHold(measurement, lastEmitted: lastEmitted, log: log),
      lastEmitted: lastEmitted,
    );
  }

  ScaleMeasurement _withHold(
    ScaleMeasurement measurement, {
    required ScaleMeasurement lastEmitted,
    required void Function(String) log,
  }) {
    final int previousSensorInduc = _lastSensorInduc;
    if (measurement.sensorInduc != previousSensorInduc) {
      _lastSensorInduc = measurement.sensorInduc;
      _ticksRemaining = holdTicksAfterSensorChange;
      _heldWeight = lastEmitted.peso;
      log(
        'Cambio sensorInduc $previousSensorInduc -> ${measurement.sensorInduc}: '
        'peso congelado ${holdTicksAfterSensorChange}s',
      );
    }

    if (_ticksRemaining > 0 && _heldWeight != null) {
      _ticksRemaining -= 1;
      return measurement.copyWith(peso: _heldWeight);
    }

    return measurement;
  }

  /// `estBalanza` 0 si el peso se movió respecto del anterior, 1 si no.
  ///
  /// Se compara contra el peso **ya emitido**, que durante un congelado es el
  /// peso congelado: por eso reporta "estable" mientras el sensor se mueve.
  /// Comportamiento heredado, fijado por `weight_hold_automatism_test.dart`.
  ScaleMeasurement _withStability(
    ScaleMeasurement measurement, {
    required ScaleMeasurement lastEmitted,
  }) {
    final bool weightChanged = measurement.peso != lastEmitted.peso;
    return measurement.copyWith(estBalanza: weightChanged ? 0 : 1);
  }
}
