import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:test_jaguar/core/constants/ble_constants.dart';
import 'package:test_jaguar/core/constants/payload_framing.dart';
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
  String _lastReceivedCommand = '';
  BleUuids _activeUuids = BleConstants.jaguar;
  PayloadFraming _activeFraming = PayloadFraming.plain;
  int _packetId = 0;
  int _commandSequence = 0;

  GATTCharacteristic? _notifyCharacteristic;
  GATTCharacteristic? _commandWriteCharacteristic;

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

    _notifyCharacteristic = _buildNotifyCharacteristic();
    _commandWriteCharacteristic = _buildCommandWriteCharacteristic();

    await _manager.removeAllServices();
    final GATTService notifyService = GATTService(
      uuid: UUID.fromString(_activeUuids.serviceUuid),
      isPrimary: true,
      includedServices: <GATTService>[],
      characteristics: _activeUuids.writeServiceUuid == _activeUuids.serviceUuid
          ? <GATTCharacteristic>[
              _notifyCharacteristic!,
              _commandWriteCharacteristic!,
            ]
          : <GATTCharacteristic>[_notifyCharacteristic!],
    );
    await _manager.addService(notifyService);

    if (_activeUuids.writeServiceUuid != _activeUuids.serviceUuid) {
      final GATTService writeService = GATTService(
        uuid: UUID.fromString(_activeUuids.writeServiceUuid),
        isPrimary: true,
        includedServices: <GATTService>[],
        characteristics: <GATTCharacteristic>[_commandWriteCharacteristic!],
      );
      await _manager.addService(writeService);
    }

    final Advertisement advertisement = Advertisement(
      name: Platform.isWindows ? null : 'JaguarScaleSim',
      serviceUUIDs: _activeUuids.writeServiceUuid == _activeUuids.serviceUuid
          ? <UUID>[UUID.fromString(_activeUuids.serviceUuid)]
          : <UUID>[
              UUID.fromString(_activeUuids.serviceUuid),
              UUID.fromString(_activeUuids.writeServiceUuid),
            ],
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
        lastReceivedCommand: null,
      ),
    );
  }

  @override
  Future<void> updateBleProfile({
    required BleUuids uuids,
    required PayloadFraming framing,
  }) async {
    // El framing se guarda siempre: dos protocolos pueden compartir perfil GATT
    // y enmarcar distinto, y en ese caso no hay que rearmar el advertising.
    _activeFraming = framing;

    final bool didChange = _activeUuids.serviceUuid != uuids.serviceUuid ||
        _activeUuids.writeServiceUuid != uuids.writeServiceUuid ||
        _activeUuids.notifyUuid != uuids.notifyUuid ||
        _activeUuids.writeUuid != uuids.writeUuid;
    if (!didChange) {
      return;
    }

    _activeUuids = uuids;

    if (_advertising) {
      await stopAdvertising();
      await startAdvertising();
    }
  }

  @override
  Future<void> notify(String utf8JsonPayload) async {
    _lastPayload = utf8JsonPayload;

    if (!_advertising || _subscribedCentrals.isEmpty) {
      return;
    }

    final GATTCharacteristic? notifyCharacteristic = _notifyCharacteristic;
    if (notifyCharacteristic == null) {
      return;
    }

    // El protocolo activo declara como enmarcar; el transporte ya no lo deduce
    // comparando UUIDs.
    if (_activeFraming == PayloadFraming.fiveByteHeader) {
      // Ensure termination CRLF and send framed ASCII payloads per-central.
      String full = utf8JsonPayload;
      if (!full.endsWith('\r\n')) {
        full = full.replaceAll('\r', '').replaceAll('\n', '');
        full = '$full\r\n';
      }

      final List<int> fullBytes = ascii.encode(full);
      final int length = fullBytes.length;

      for (final Central central in _subscribedCentrals.values) {
        final int mtu = await _safeMaximumNotifyLength(central);
        int chunkPayloadSize = mtu - 3 - 5;
        if (chunkPayloadSize <= 0) {
          chunkPayloadSize = (mtu - 8) > 0 ? (mtu - 8) : 1;
        }

        final int totalTramas = (length + chunkPayloadSize - 1) ~/ chunkPayloadSize;

        for (int trama = 0; trama < totalTramas; trama++) {
          final int offset = trama * chunkPayloadSize;
          final int toSend = (length - offset) < chunkPayloadSize ? (length - offset) : chunkPayloadSize;
          final Uint8List buffer = Uint8List(5 + toSend);
          buffer[0] = _packetId & 0xFF;
          buffer[1] = totalTramas & 0xFF;
          buffer[2] = (trama + 1) & 0xFF;
          buffer[3] = (length >> 8) & 0xFF;
          buffer[4] = length & 0xFF;
          buffer.setRange(5, 5 + toSend, fullBytes, offset);

          await _manager.notifyCharacteristic(
            central,
            notifyCharacteristic,
            value: buffer,
          );
        }
      }

      _packetId = (_packetId + 1) & 0xFF;
      return;
    }

    // Default behaviour: chunk by maxLength and send raw utf8 bytes.
    final List<int> bytes = utf8.encode(utf8JsonPayload);
    for (final Central central in _subscribedCentrals.values) {
      final int maxLength = await _safeMaximumNotifyLength(central);
      if (bytes.length <= maxLength) {
        await _manager.notifyCharacteristic(
          central,
          notifyCharacteristic,
          value: Uint8List.fromList(bytes),
        );
        continue;
      }

      for (int start = 0; start < bytes.length; start += maxLength) {
        final int end = (start + maxLength < bytes.length) ? start + maxLength : bytes.length;
        await _manager.notifyCharacteristic(
          central,
          notifyCharacteristic,
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
    final String characteristicUuid =
        event.characteristic.uuid.toString().toUpperCase();

    if (characteristicUuid == _activeUuids.notifyUuid.toUpperCase()) {
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
      return;
    }

    if (characteristicUuid == _activeUuids.writeUuid.toUpperCase()) {
      final List<int> payload = utf8.encode(_lastReceivedCommand);
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
      return;
    }

    await _manager.respondReadRequestWithError(
      event.request,
      error: GATTError.requestNotSupported,
    );
  }

  Future<void> _onCharacteristicWriteRequested(
    GATTCharacteristicWriteRequestedEventArgs event,
  ) async {
    final String characteristicUuid =
        event.characteristic.uuid.toString().toUpperCase();

    if (characteristicUuid != _activeUuids.writeUuid.toUpperCase()) {
      await _manager.respondWriteRequestWithError(
        event.request,
        error: GATTError.requestNotSupported,
      );
      return;
    }

    final String decoded = _decodeCommand(event.request.value);
    _lastReceivedCommand = decoded;
    _commandSequence += 1;
    _emitStatus(
      _status.copyWith(
        lastReceivedCommand: decoded,
        commandSequence: _commandSequence,
      ),
    );

    if (event.request.offset < 0) {
      await _manager.respondWriteRequestWithError(
        event.request,
        error: GATTError.invalidOffset,
      );
      return;
    }

    await _manager.respondWriteRequest(event.request);
  }

  String _decodeCommand(Uint8List value) {
    try {
      final String decoded = utf8.decode(value, allowMalformed: true);
      if (decoded.isNotEmpty) {
        return _escapeControlChars(decoded);
      }
    } catch (_) {
      // Fallback to hex below.
    }

    return value.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
  }

  String _escapeControlChars(String input) {
    final StringBuffer buffer = StringBuffer();
    for (final int codeUnit in input.codeUnits) {
      switch (codeUnit) {
        case 0x5C:
          buffer.write(r'\\');
          break;
        case 0x0D:
          buffer.write(r'\r');
          break;
        case 0x0A:
          buffer.write(r'\n');
          break;
        case 0x09:
          buffer.write(r'\t');
          break;
        case 0x20:
          buffer.write(r'\s');
          break;
        default:
          if (codeUnit < 0x20 || codeUnit == 0x7F) {
            buffer.write('\\x${codeUnit.toRadixString(16).padLeft(2, '0')}');
          } else {
            buffer.writeCharCode(codeUnit);
          }
      }
    }
    return buffer.toString();
  }

  Future<int> _safeMaximumNotifyLength(Central central) async {
    try {
      final int length = await _manager.getMaximumNotifyLength(central);
      return length > 0 ? length : 20;
    } catch (_) {
      return 20;
    }
  }

  GATTCharacteristic _buildNotifyCharacteristic() {
    return GATTCharacteristic.mutable(
      uuid: UUID.fromString(_activeUuids.notifyUuid),
      properties: <GATTCharacteristicProperty>[
        GATTCharacteristicProperty.read,
        GATTCharacteristicProperty.notify,
        GATTCharacteristicProperty.indicate,
      ],
      permissions: <GATTCharacteristicPermission>[
        GATTCharacteristicPermission.read,
      ],
      descriptors: <GATTDescriptor>[],
    );
  }

  GATTCharacteristic _buildCommandWriteCharacteristic() {
    return GATTCharacteristic.mutable(
      uuid: UUID.fromString(_activeUuids.writeUuid),
      properties: <GATTCharacteristicProperty>[
        GATTCharacteristicProperty.read,
        GATTCharacteristicProperty.write,
        GATTCharacteristicProperty.writeWithoutResponse,
      ],
      permissions: <GATTCharacteristicPermission>[
        GATTCharacteristicPermission.read,
        GATTCharacteristicPermission.write,
      ],
      descriptors: <GATTDescriptor>[],
    );
  }

  void _emitStatus(BlePeripheralStatus next) {
    _status = next;
    if (!_statusController.isClosed) {
      _statusController.add(next);
    }
  }
}
