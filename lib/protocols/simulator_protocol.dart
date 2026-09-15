import 'package:test_jaguar/core/constants/ble_constants.dart';
import 'package:test_jaguar/domain/value_objects/send_protocol.dart';
import 'package:test_jaguar/protocols/payload_framing.dart';

/// Lo que cada protocolo del simulador sabe de sí mismo.
///
/// El contrato es deliberadamente chico: los protocolos son polimórficos en el
/// **formato del payload** y en el **perfil BLE**, no en su superficie de
/// comandos. Los comandos `AT+` que hoy acepta el simulador o tocan estado
/// compartido (`AT+RSTHOLD`, `AT+TARA`, `AT+CERO`) o son exclusivos de un
/// protocolo, y los protocolos que vienen (ST456web, ST567) usan otra gramática
/// (`CTR,<comando>`), así que no hay nada que generalizar ahí. Cada módulo
/// expone además su propia API de configuración, que no pasa por acá.
///
/// Va a crecer un miembro por paso a medida que se migre cada protocolo: hoy
/// sólo cubre lo que el orquestador ya puede delegar.
abstract class SimulatorProtocol {
  /// Valor del enum que selecciona este protocolo en la UI.
  SendProtocol get id;

  /// Perfil GATT que hay que anunciar mientras este protocolo esté activo.
  BleUuids get bleUuids;

  /// Cómo enmarcar el payload en el aire.
  PayloadFraming get framing;
}
