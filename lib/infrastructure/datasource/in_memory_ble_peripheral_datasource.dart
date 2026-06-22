import 'dart:async';

import 'package:test_jaguar/core/constants/ble_constants.dart';
import 'package:test_jaguar/domain/entities/ble_peripheral_status.dart';
import 'package:test_jaguar/infrastructure/datasource/ble_peripheral_datasource.dart';

class InMemoryBlePeripheralDataSource implements BlePeripheralDataSource {
  final StreamController<BlePeripheralStatus> _statusController =
      StreamController<BlePeripheralStatus>.broadcast();

  BlePeripheralStatus _status = BlePeripheralStatus.initial.copyWith(
    adapterEnabled: true,
  );

  @override
  Stream<BlePeripheralStatus> watchStatus() async* {
    yield _status;
    yield* _statusController.stream;
  }

  @override
  Future<void> startAdvertising() async {
    _status = _status.copyWith(advertising: true);
    _statusController.add(_status);
  }

  @override
  Future<void> stopAdvertising() async {
    _status = _status.copyWith(advertising: false, connected: false);
    _statusController.add(_status);
  }

  @override
  Future<void> updateBleUuids(BleUuids uuids) async {
    // No-op en el datasource in-memory.
  }

  @override
  Future<void> notify(String utf8JsonPayload) async {
    // Stub: en PASO 6 se envía por GATT notify real usando BLE peripheral.
    _status = _status.copyWith(connected: _status.advertising);
    _statusController.add(_status);
  }

  @override
  Future<void> dispose() => _statusController.close();
}
