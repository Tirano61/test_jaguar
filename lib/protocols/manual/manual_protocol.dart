import 'package:test_jaguar/core/constants/ble_constants.dart';
import 'package:test_jaguar/domain/value_objects/send_protocol.dart';
import 'package:test_jaguar/protocols/payload_framing.dart';
import 'package:test_jaguar/protocols/simulator_protocol.dart';

/// Protocolo Manual: mismo JSON y mismo perfil GATT que Jaguar BLE, pero los
/// valores los fija el tester desde la UI en vez del motor de simulación.
class ManualProtocol implements SimulatorProtocol {
  const ManualProtocol();

  @override
  SendProtocol get id => SendProtocol.manual;

  @override
  BleUuids get bleUuids => BleConstants.jaguar;

  @override
  PayloadFraming get framing => PayloadFraming.plain;
}
