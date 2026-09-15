import 'package:test_jaguar/core/constants/ble_constants.dart';
import 'package:test_jaguar/domain/value_objects/send_protocol.dart';
import 'package:test_jaguar/protocols/payload_framing.dart';
import 'package:test_jaguar/protocols/simulator_protocol.dart';

/// Protocolo Jaguar BLE: el modo clásico. El motor de simulación genera el
/// peso siguiendo el ciclo de fases y el simulador lo manda como JSON.
class JaguarBleProtocol implements SimulatorProtocol {
  const JaguarBleProtocol();

  @override
  SendProtocol get id => SendProtocol.jaguarBle;

  @override
  BleUuids get bleUuids => BleConstants.jaguar;

  @override
  PayloadFraming get framing => PayloadFraming.plain;
}
