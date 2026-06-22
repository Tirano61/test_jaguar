import 'package:test_jaguar/domain/entities/ble_peripheral_status.dart';
import 'package:test_jaguar/core/constants/ble_constants.dart';

abstract interface class BlePeripheralRepository {
  Stream<BlePeripheralStatus> watchStatus();

  Future<void> startAdvertising();

  Future<void> stopAdvertising();

  Future<void> updateBleUuids(BleUuids uuids);

  Future<void> notifyUtf8Json(String payload);

  Future<void> dispose();
}
