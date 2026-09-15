import 'package:flutter_test/flutter_test.dart';
import 'package:test_jaguar/core/constants/ble_constants.dart';
import 'package:test_jaguar/domain/value_objects/send_protocol.dart';
import 'package:test_jaguar/core/constants/payload_framing.dart';
import 'package:test_jaguar/protocols/protocol_registry.dart';
import 'package:test_jaguar/protocols/simulator_protocol.dart';

void main() {
  final ProtocolRegistry registry = ProtocolRegistry.standard();

  test('todos los valores del enum tienen implementación registrada', () {
    // El selector de la UI se arma desde SendProtocol.values, así que agregar
    // un valor al enum sin sumarlo al registro rompe la app al seleccionarlo.
    for (final SendProtocol id in SendProtocol.values) {
      expect(registry.of(id).id, id, reason: 'falta el protocolo $id');
    }
    expect(registry.all, hasLength(SendProtocol.values.length));
  });

  test('sólo el Remoto ST407 usa el perfil ABF3 y cabecera de 5 bytes', () {
    final SimulatorProtocol st407 = registry.of(SendProtocol.st407Remote);
    expect(st407.bleUuids, same(BleConstants.remotoAbf3));
    expect(st407.framing, PayloadFraming.fiveByteHeader);

    for (final SendProtocol id in <SendProtocol>[
      SendProtocol.jaguarBle,
      SendProtocol.manual,
      SendProtocol.hidraulicoBle,
    ]) {
      expect(registry.of(id).bleUuids, same(BleConstants.jaguar),
          reason: '$id comparte el perfil Jaguar');
      expect(registry.of(id).framing, PayloadFraming.plain, reason: '$id');
    }
  });

  test('un registro incompleto falla con un mensaje que dice qué hacer', () {
    final ProtocolRegistry vacio = ProtocolRegistry(const <SimulatorProtocol>[]);
    expect(
      () => vacio.of(SendProtocol.jaguarBle),
      throwsA(
        isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          contains('ProtocolRegistry.standard()'),
        ),
      ),
    );
  });
}
