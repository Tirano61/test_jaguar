import 'package:test_jaguar/core/constants/ble_constants.dart';
import 'package:test_jaguar/domain/entities/scale_measurement.dart';
import 'package:test_jaguar/domain/value_objects/send_protocol.dart';
import 'package:test_jaguar/protocols/payload_framing.dart';
import 'package:test_jaguar/protocols/shared/scale_payload.dart';
import 'package:test_jaguar/protocols/simulator_protocol.dart';

/// Protocolo Jaguar BLE: el modo clásico y el que menos hace.
///
/// El peso lo genera el motor de simulación siguiendo el ciclo de fases, los
/// automatismos de balanza son los compartidos (`ScaleAutomatisms`, que vive en
/// el orquestador porque el ST407 también los usa) y la trama es el JSON de 7
/// claves. No tiene estado propio, por eso es `const`.
class JaguarBleProtocol implements SimulatorProtocol {
  const JaguarBleProtocol();

  @override
  SendProtocol get id => SendProtocol.jaguarBle;

  @override
  BleUuids get bleUuids => BleConstants.jaguar;

  @override
  PayloadFraming get framing => PayloadFraming.plain;

  @override
  String encodePayload(ScaleMeasurement measurement) =>
      ScalePayloadDto(measurement: measurement).toJsonUtf8String();
}
