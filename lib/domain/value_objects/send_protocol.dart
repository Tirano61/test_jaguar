enum SendProtocol {
  jaguarBle,
  st407Remote,
  manual,
  hidraulicoBle,
  st567,
  st456web;

  String get label {
    switch (this) {
      case SendProtocol.jaguarBle:
        return 'Jaguar BLE';
      case SendProtocol.st407Remote:
        return 'Remoto ST407';
      case SendProtocol.manual:
        return 'Manual';
      case SendProtocol.hidraulicoBle:
        return 'Hidráulico BLE';
      case SendProtocol.st567:
        return 'Remoto ST567';
      case SendProtocol.st456web:
        return 'Remoto ST456web';
    }
  }
}
