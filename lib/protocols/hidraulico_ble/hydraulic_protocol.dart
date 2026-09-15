import 'package:test_jaguar/core/constants/ble_constants.dart';
import 'package:test_jaguar/domain/value_objects/send_protocol.dart';
import 'package:test_jaguar/protocols/payload_framing.dart';
import 'package:test_jaguar/protocols/simulator_protocol.dart';

/// Protocolo Hidráulico BLE: comparte el perfil GATT de Jaguar, pero agrega al
/// JSON los campos de la caja de manejo (`tomaFuerza`, `rpm`, `errorEcu`) y es
/// el único que procesa la familia de comandos de descarga (`AT+INICIO`,
/// `AT+DETENER`, `AT+REANUDAR`, `AT+FINALIZAR`, `AT+MOVIMIENTO`).
class HydraulicProtocol implements SimulatorProtocol {
  const HydraulicProtocol();

  @override
  SendProtocol get id => SendProtocol.hidraulicoBle;

  @override
  BleUuids get bleUuids => BleConstants.jaguar;

  @override
  PayloadFraming get framing => PayloadFraming.plain;
}
