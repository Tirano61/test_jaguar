import 'package:test_jaguar/domain/entities/ble_peripheral_status.dart';

abstract interface class BlePeripheralDataSource {
  Stream<BlePeripheralStatus> watchStatus();

  Future<void> startAdvertising();

  Future<void> stopAdvertising();

  Future<void> notify(String utf8JsonPayload);

  Future<void> dispose();
}
