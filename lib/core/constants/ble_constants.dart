class BleConstants {
  BleConstants._();

  /// Service principal que contiene la characteristic de NOTIFY.
  static const String serviceUuid =
      '0000ABF0-0000-1000-8000-00805F9B34FB';

  /// Characteristic de NOTIFY.
  static const String characteristicUuid =
      '0000ABF1-0000-1000-8000-00805F9B34FB';

  /// Service que contiene la characteristic de WRITE para comandos.
  static const String serviceWriteUuid =
      '0000ABF6-0000-1000-8000-00805F9B34FB';

  /// Characteristic WRITE para comandos.
  static const String characteristicWriteUuid =
      '0000ABF2-0000-1000-8000-00805F9B34FB';
}
