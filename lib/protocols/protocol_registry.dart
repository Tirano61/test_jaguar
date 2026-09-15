import 'package:test_jaguar/domain/value_objects/send_protocol.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_protocol.dart';
import 'package:test_jaguar/protocols/jaguar_ble/jaguar_ble_protocol.dart';
import 'package:test_jaguar/protocols/manual/manual_protocol.dart';
import 'package:test_jaguar/protocols/simulator_protocol.dart';
import 'package:test_jaguar/protocols/st407_remote/st407_remote_protocol.dart';

/// Los protocolos que el simulador sabe hablar, indexados por su valor del
/// enum.
///
/// Guarda **una instancia por protocolo para toda la vida de la app**, no una
/// por activación: hay estado que tiene que sobrevivir a un cambio de modo (los
/// valores del modo Manual, la configuración de toma de fuerza del Hidráulico)
/// y comandos que llegan a un protocolo que no está activo.
///
/// Agregar un protocolo nuevo es crear su clase y sumarla a
/// [ProtocolRegistry.standard]; `protocol_registry_test.dart` verifica que no
/// quede ningún valor del enum sin implementación.
class ProtocolRegistry {
  ProtocolRegistry(List<SimulatorProtocol> protocols)
      : _byId = <SendProtocol, SimulatorProtocol>{
          for (final SimulatorProtocol protocol in protocols)
            protocol.id: protocol,
        };

  /// El juego completo de protocolos de la app.
  factory ProtocolRegistry.standard() {
    return ProtocolRegistry(const <SimulatorProtocol>[
      JaguarBleProtocol(),
      St407RemoteProtocol(),
      ManualProtocol(),
      HydraulicProtocol(),
    ]);
  }

  final Map<SendProtocol, SimulatorProtocol> _byId;

  Iterable<SimulatorProtocol> get all => _byId.values;

  SimulatorProtocol of(SendProtocol id) {
    final SimulatorProtocol? protocol = _byId[id];
    if (protocol == null) {
      throw StateError(
        'No hay implementación registrada para $id. Sumala a '
        'ProtocolRegistry.standard().',
      );
    }
    return protocol;
  }
}
