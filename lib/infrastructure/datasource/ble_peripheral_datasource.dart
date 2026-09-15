import 'package:test_jaguar/domain/entities/ble_peripheral_status.dart';
import 'package:test_jaguar/core/constants/ble_constants.dart';
import 'package:test_jaguar/core/constants/payload_framing.dart';

abstract interface class BlePeripheralDataSource {
  Stream<BlePeripheralStatus> watchStatus();

  Future<void> startAdvertising();

  Future<void> stopAdvertising();

  /// Cambia el perfil GATT que se anuncia y como se enmarca el payload.
  ///
  /// Van juntos porque los dos los declara el protocolo activo: el transporte
  /// no tiene que deducir el framing comparando UUIDs.
  Future<void> updateBleProfile({
    required BleUuids uuids,
    required PayloadFraming framing,
  });

  Future<void> notify(String utf8JsonPayload);

  Future<void> dispose();
}
