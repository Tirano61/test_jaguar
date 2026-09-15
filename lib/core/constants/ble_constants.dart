class BleConstants {
  BleConstants._();

    /// Perfil Jaguar tradicional.
    static const BleUuids jaguar = BleUuids(
        serviceUuid: '0000ABF0-0000-1000-8000-00805F9B34FB',
        writeServiceUuid: '0000ABF6-0000-1000-8000-00805F9B34FB',
        notifyUuid: '0000ABF1-0000-1000-8000-00805F9B34FB',
        writeUuid: '0000ABF2-0000-1000-8000-00805F9B34FB',
    );

    /// Perfil remoto ABF3: lo comparten el ST407 y los futuros ST456web y
    /// ST567. Es un perfil GATT, no un protocolo — el protocolo lo define el
    /// formato de las tramas, no estos UUIDs.
    static const BleUuids remotoAbf3 = BleUuids(
        serviceUuid: '0000ABF3-0000-1000-8000-00805F9B34FB',
        writeServiceUuid: '0000ABF3-0000-1000-8000-00805F9B34FB',
        notifyUuid: '0000ABF5-0000-1000-8000-00805F9B34FB',
        writeUuid: '0000ABF4-0000-1000-8000-00805F9B34FB',
    );

    // Compatibilidad con la UI y codigo legado.
    static const String serviceUuid = '0000ABF0-0000-1000-8000-00805F9B34FB';
    static const String characteristicUuid =
        '0000ABF1-0000-1000-8000-00805F9B34FB';
    static const String serviceWriteUuid =
        '0000ABF6-0000-1000-8000-00805F9B34FB';
    static const String characteristicWriteUuid =
        '0000ABF2-0000-1000-8000-00805F9B34FB';
}

class BleUuids {
    const BleUuids({
        required this.serviceUuid,
        required this.writeServiceUuid,
        required this.notifyUuid,
        required this.writeUuid,
    });

    final String serviceUuid;
    final String writeServiceUuid;
    final String notifyUuid;
    final String writeUuid;
}
