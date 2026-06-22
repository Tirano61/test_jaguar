import 'package:test_jaguar/core/constants/ble_constants.dart';
import 'package:test_jaguar/domain/entities/ble_peripheral_status.dart';
import 'package:test_jaguar/domain/repositories/ble_peripheral_repository.dart';
import 'package:test_jaguar/infrastructure/datasource/ble_peripheral_datasource.dart';

class BlePeripheralRepositoryImpl implements BlePeripheralRepository {
  BlePeripheralRepositoryImpl(this._dataSource);

  final BlePeripheralDataSource _dataSource;

  @override
  Stream<BlePeripheralStatus> watchStatus() => _dataSource.watchStatus();

  @override
  Future<void> startAdvertising() => _dataSource.startAdvertising();

  @override
  Future<void> stopAdvertising() => _dataSource.stopAdvertising();

  @override
  Future<void> notifyUtf8Json(String payload) => _dataSource.notify(payload);

  @override
  Future<void> dispose() => _dataSource.dispose();

  @override
  Future<void> updateBleUuids(BleUuids uuids) {
    // TODO: implement updateBleUuids
    return _dataSource.updateBleUuids(uuids);
  }
}
