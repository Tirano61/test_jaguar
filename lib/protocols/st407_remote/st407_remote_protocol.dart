import 'package:test_jaguar/core/constants/ble_constants.dart';
import 'package:test_jaguar/domain/value_objects/send_protocol.dart';
import 'package:test_jaguar/protocols/payload_framing.dart';
import 'package:test_jaguar/protocols/simulator_protocol.dart';

/// Protocolo Remoto ST407: el único que no manda JSON. Notifica cadenas
/// separadas por coma (una por pantalla, códigos 100-108) sobre el perfil
/// ABF3 y con cabecera binaria de 5 bytes.
class St407RemoteProtocol implements SimulatorProtocol {
  const St407RemoteProtocol();

  @override
  SendProtocol get id => SendProtocol.st407Remote;

  @override
  BleUuids get bleUuids => BleConstants.remotoAbf3;

  @override
  PayloadFraming get framing => PayloadFraming.fiveByteHeader;
}
