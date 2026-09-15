import 'package:test_jaguar/core/constants/ble_constants.dart';
import 'package:test_jaguar/domain/entities/scale_measurement.dart';
import 'package:test_jaguar/domain/value_objects/send_protocol.dart';
import 'package:test_jaguar/protocols/payload_framing.dart';
import 'package:test_jaguar/protocols/shared/scale_payload.dart';
import 'package:test_jaguar/protocols/simulator_protocol.dart';

/// Protocolo Manual: misma trama y mismo perfil GATT que Jaguar BLE, pero los
/// valores los fija el tester desde la UI en vez del motor de simulación.
///
/// Los automatismos están deliberadamente apagados acá: el tick del motor no
/// pisa los valores manuales y el congelado de peso reporta siempre 0. Todo lo
/// que se manda es lo que se ve en los sliders.
///
/// Su estado **vive aunque el protocolo no esté activo**: `AT+RSTHOLD` no tiene
/// guard de protocolo y lo modifica desde cualquier modo (comportamiento
/// heredado, ver `at_command_routing_test.dart`).
class ManualProtocol implements SimulatorProtocol {
  ManualProtocol();

  @override
  SendProtocol get id => SendProtocol.manual;

  @override
  BleUuids get bleUuids => BleConstants.jaguar;

  @override
  PayloadFraming get framing => PayloadFraming.plain;

  ScaleMeasurement _measurement = ScaleMeasurement.baseline;

  /// Los valores que el tester dejó configurados. Es también lo que viaja en
  /// el DTO de estado, así que no hace falta una clase de estado aparte.
  ScaleMeasurement get measurement => _measurement;

  /// Fija los valores del modo, recortados a los rangos que acepta el
  /// protocolo.
  void set(ScaleMeasurement measurement) {
    _measurement = _normalize(measurement);
  }

  String encodePayload(ScaleMeasurement measurement) =>
      ScalePayloadDto(measurement: measurement).toJsonUtf8String();

  // --- Comandos ---
  // Devuelven la línea de log, o null si no cambió nada: en ese caso el
  // orquestador tampoco reenvía el payload.

  /// `AT+RSTHOLD` suelta el hold y vuelve la balanza a estable.
  ///
  /// Es el único comando sin guard de protocolo: llega acá aunque el modo
  /// activo sea otro.
  String? applyResetHold() {
    final ScaleMeasurement next = _normalize(
      _measurement.copyWith(hold: 0, estBalanza: 1),
    );
    if (next.hold == _measurement.hold &&
        next.estBalanza == _measurement.estBalanza) {
      return null;
    }
    _measurement = next;
    return 'Comando aplicado: AT+RSTHOLD -> hold=0';
  }

  /// `AT+TARA` alterna la tara: al activarla el peso actual pasa a tara y el
  /// peso queda en 0; al desactivarla se devuelve la tara al peso.
  String? applyToggleTare() {
    final bool activateTare = _measurement.tara == 0;
    final ScaleMeasurement toggled = activateTare
        ? _measurement.copyWith(tara: _measurement.peso, peso: 0)
        : _measurement.copyWith(
            tara: 0,
            peso: (_measurement.peso + _measurement.tara).clamp(0, 22000).toInt(),
          );
    final ScaleMeasurement next = _normalize(toggled);

    if (next.tara == _measurement.tara && next.peso == _measurement.peso) {
      return null;
    }
    _measurement = next;
    return activateTare
        ? 'Comando aplicado: AT+TARA -> tara activada'
        : 'Comando aplicado: AT+TARA -> tara desactivada';
  }

  /// `AT+CERO` pone el peso en cero. Con una tara puesta no hace nada: primero
  /// hay que sacarla con `AT+TARA`.
  String? applyZeroWeight() {
    if (_measurement.tara > 0 || _measurement.peso == 0) {
      return null;
    }
    _measurement = _normalize(_measurement.copyWith(peso: 0));
    return 'Comando aplicado: AT+CERO -> peso=0 (manual)';
  }

  ScaleMeasurement _normalize(ScaleMeasurement measurement) {
    final double normalizedHumidity =
        double.parse(measurement.humedad.clamp(0.0, 22.0).toStringAsFixed(1));
    final double normalizedVbat =
        double.parse(measurement.vbat.clamp(0.0, 5.0).toStringAsFixed(1));

    return measurement.copyWith(
      tara: measurement.tara.clamp(0, 22000),
      hold: measurement.hold.clamp(0, 1),
      vbat: normalizedVbat,
      peso: measurement.peso.clamp(0, 22000),
      estBalanza: measurement.estBalanza.clamp(0, 5),
      humedad: normalizedHumidity,
      sensorInduc: measurement.sensorInduc.clamp(0, 1),
    );
  }
}
