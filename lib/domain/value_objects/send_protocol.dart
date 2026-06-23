enum SendProtocol {
  jaguarBle,
  st456Remote,
  manual;

  String get label {
    switch (this) {
      case SendProtocol.jaguarBle:
        return 'Jaguar BLE';
      case SendProtocol.st456Remote:
        return 'Remoto ST407';
      case SendProtocol.manual:
        return 'Manual';
    }
  }
}
