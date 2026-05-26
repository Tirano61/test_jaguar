enum SendProtocol {
  jaguarBle,
  manual;

  String get label {
    switch (this) {
      case SendProtocol.jaguarBle:
        return 'Jaguar BLE';
      case SendProtocol.manual:
        return 'Manual';
    }
  }
}
