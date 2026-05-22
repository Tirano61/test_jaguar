import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:test_jaguar/core/constants/ble_constants.dart';
import 'package:test_jaguar/domain/entities/ble_peripheral_status.dart';
import 'package:test_jaguar/infrastructure/datasource/ble_peripheral_datasource.dart';

class BluetoothLowEnergyBlePeripheralDataSource
    implements BlePeripheralDataSource {
  BluetoothLowEnergyBlePeripheralDataSource({
    PeripheralManager? manager,
  }) : _manager = manager ?? PeripheralManager() {
    _status = BlePeripheralStatus.initial.copyWith(
      adapterEnabled: _manager.state == BluetoothLowEnergyState.poweredOn,
    );

    _subscriptions.add(_manager.stateChanged.listen(_onStateChanged));
    _subscriptions.add(
      _manager.connectionStateChanged.listen(_onConnectionStateChanged),
    );
    _subscriptions.add(
      _manager.characteristicNotifyStateChanged.listen(
        _onCharacteristicNotifyStateChanged,
      ),
    );
    _subscriptions.add(
      _manager.characteristicReadRequested.listen(_onCharacteristicReadRequested),
    );
    _subscriptions.add(
      _manager.characteristicWriteRequested.listen(
        _onCharacteristicWriteRequested,
      ),
    );
  }

  final PeripheralManager _manager;
  final StreamController<BlePeripheralStatus> _statusController =
      StreamController<BlePeripheralStatus>.broadcast();
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];

  final Set<String> _subscribedCentralIds = <String>{};
  final Map<String, Central> _subscribedCentrals = <String, Central>{};

  BlePeripheralStatus _status = BlePeripheralStatus.initial;
  bool _advertising = false;
  String _lastPayload = '{}';

  late final GATTCharacteristic _notifyCharacteristic =
      GATTCharacteristic.mutable(
        uuid: UUID.fromString(BleConstants.characteristicUuid),
        properties: <GATTCharacteristicProperty>[
          GATTCharacteristicProperty.read,
          GATTCharacteristicProperty.write,
          GATTCharacteristicProperty.writeWithoutResponse,
          GATTCharacteristicProperty.notify,
          GATTCharacteristicProperty.indicate,
        ],
        permissions: <GATTCharacteristicPermission>[
          GATTCharacteristicPermission.read,
          GATTCharacteristicPermission.write,
        ],
        descriptors: <GATTDescriptor>[],
      );

  @override
  Stream<BlePeripheralStatus> watchStatus() async* {
    yield _status;
    yield* _statusController.stream;
  }

  @override
  Future<void> startAdvertising() async {
    if (_advertising) {
      return;
    }

    await _ensureAuthorizedAndPoweredOn();

    await _manager.removeAllServices();
    final GATTService service = GATTService(
      uuid: UUID.fromString(BleConstants.serviceUuid),
      isPrimary: true,
      includedServices: <GATTService>[],
      characteristics: <GATTCharacteristic>[_notifyCharacteristic],
    );
    await _manager.addService(service);

    final Advertisement advertisement = Advertisement(
      name: Platform.isWindows ? null : 'JaguarScaleSim',
      serviceUUIDs: <UUID>[UUID.fromString(BleConstants.serviceUuid)],
      serviceData: <UUID, Uint8List>{},
      manufacturerSpecificData: <ManufacturerSpecificData>[],
    );

    await _manager.startAdvertising(advertisement);
    _advertising = true;
    _emitStatus(
      _status.copyWith(
        advertising: true,
        connected: _subscribedCentralIds.isNotEmpty,
      ),
    );
  }

  @override
  Future<void> stopAdvertising() async {
    if (_advertising) {
      await _manager.stopAdvertising();
    }
    _advertising = false;
    _subscribedCentralIds.clear();
    _subscribedCentrals.clear();
    _emitStatus(
      _status.copyWith(
        advertising: false,
        connected: false,
        connectedDeviceId: null,
      ),
    );
  }

  @override
  Future<void> notify(String utf8JsonPayload) async {
    _lastPayload = utf8JsonPayload;

    if (!_advertising || _subscribedCentrals.isEmpty) {
      return;
    }

    final List<int> bytes = utf8.encode(utf8JsonPayload);

    for (final Central central in _subscribedCentrals.values) {
      final int maxLength = await _safeMaximumNotifyLength(central);
      if (bytes.length <= maxLength) {
        await _manager.notifyCharacteristic(
          central,
          _notifyCharacteristic,
          value: Uint8List.fromList(bytes),
        );
        continue;
      }

      for (int start = 0; start < bytes.length; start += maxLength) {
        final int end = (start + maxLength < bytes.length)
            ? start + maxLength
            : bytes.length;
        await _manager.notifyCharacteristic(
          central,
          _notifyCharacteristic,
          value: Uint8List.fromList(bytes.sublist(start, end)),
        );
      }
    }
  }

  @override
  Future<void> dispose() async {
    await stopAdvertising();
    for (final StreamSubscription<dynamic> subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _statusController.close();
  }

  Future<void> _ensureAuthorizedAndPoweredOn() async {
    final BluetoothLowEnergyState state = _manager.state;
    if (state == BluetoothLowEnergyState.unauthorized && Platform.isAndroid) {
      await _manager.authorize();
    }
  }

  void _onStateChanged(BluetoothLowEnergyStateChangedEventArgs event) {
    _emitStatus(
      _status.copyWith(
        adapterEnabled: event.state == BluetoothLowEnergyState.poweredOn,
      ),
    );
  }

  void _onConnectionStateChanged(CentralConnectionStateChangedEventArgs event) {
    final String centralId = event.central.uuid.toString();

    if (event.state == ConnectionState.connected) {
      _subscribedCentrals[centralId] = event.central;
      _subscribedCentralIds.add(centralId);
    } else {
      _subscribedCentrals.remove(centralId);
      _subscribedCentralIds.remove(centralId);
    }

    _emitStatus(
      _status.copyWith(
        connected: _subscribedCentralIds.isNotEmpty,
        connectedDeviceId:
            _subscribedCentralIds.isEmpty ? null : _subscribedCentralIds.first,
      ),
    );
  }

  void _onCharacteristicNotifyStateChanged(
    GATTCharacteristicNotifyStateChangedEventArgs event,
  ) {
    final String centralId = event.central.uuid.toString();

    if (event.state) {
      _subscribedCentrals[centralId] = event.central;
      _subscribedCentralIds.add(centralId);
    } else {
      _subscribedCentrals.remove(centralId);
      _subscribedCentralIds.remove(centralId);
    }

    _emitStatus(
      _status.copyWith(
        connected: _subscribedCentralIds.isNotEmpty,
        connectedDeviceId:
            _subscribedCentralIds.isEmpty ? null : _subscribedCentralIds.first,
      ),
    );
  }

  Future<void> _onCharacteristicReadRequested(
    GATTCharacteristicReadRequestedEventArgs event,
  ) async {
    if (event.characteristic.uuid.toString().toUpperCase() !=
        BleConstants.characteristicUuid) {
      await _manager.respondReadRequestWithError(
        event.request,
        error: GATTError.requestNotSupported,
      );
      return;
    }

    final List<int> payload = utf8.encode(_lastPayload);
    final int offset = event.request.offset;
    if (offset < 0 || offset > payload.length) {
      await _manager.respondReadRequestWithError(
        event.request,
        error: GATTError.invalidOffset,
      );
      return;
    }

    await _manager.respondReadRequestWithValue(
      event.request,
      value: Uint8List.fromList(payload.sublist(offset)),
    );
  }

  Future<void> _onCharacteristicWriteRequested(
    GATTCharacteristicWriteRequestedEventArgs event,
  ) async {
    if (event.characteristic.uuid.toString().toUpperCase() !=
        BleConstants.characteristicUuid) {
      await _manager.respondWriteRequestWithError(
        event.request,
        error: GATTError.requestNotSupported,
      );
      return;
    }

    await _manager.respondWriteRequest(event.request);
  }

  Future<int> _safeMaximumNotifyLength(Central central) async {
    try {
      final int length = await _manager.getMaximumNotifyLength(central);
      return length > 0 ? length : 20;
    } catch (_) {
      return 20;
    }
  }

  void _emitStatus(BlePeripheralStatus next) {
    _status = next;
    if (!_statusController.isClosed) {
      _statusController.add(next);
    }
  }
}
