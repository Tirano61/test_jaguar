/// Comando `AT+MOVIMIENTO(<tipo>)` recibido por characteristic write en el
/// modo Hidráulico BLE.
///
/// tipo: 1 abrir tubo, 2 cerrar tubo, 3 abrir guillotina, 4 cerrar guillotina.
class HydraulicMovementCommand {
  const HydraulicMovementCommand({required this.tipo});

  final int tipo;

  static final RegExp _pattern = RegExp(r'^AT\+MOVIMIENTO\((\d+)\)$');

  /// [normalizedCommand] debe venir ya en mayúsculas y sin espacios/CRLF
  /// (mismo formato que produce `_normalizeIncomingCommand` en el
  /// orquestador). Devuelve `null` si no matchea el formato esperado.
  static HydraulicMovementCommand? tryParse(String normalizedCommand) {
    final RegExpMatch? match = _pattern.firstMatch(normalizedCommand);
    if (match == null) {
      return null;
    }

    final int? tipo = int.tryParse(match.group(1)!);
    if (tipo == null) {
      return null;
    }

    return HydraulicMovementCommand(tipo: tipo);
  }

  bool get affectsTube => tipo == 1 || tipo == 2;
  bool get affectsGuillotine => tipo == 3 || tipo == 4;

  /// `true` para abrir (tipo 1 o 3), `false` para cerrar (tipo 2 o 4),
  /// `null` si el tipo no es uno de los 4 valores conocidos.
  bool? get opens {
    switch (tipo) {
      case 1:
      case 3:
        return true;
      case 2:
      case 4:
        return false;
      default:
        return null;
    }
  }

  String get label {
    switch (tipo) {
      case 1:
        return 'Abrir tubo';
      case 2:
        return 'Cerrar tubo';
      case 3:
        return 'Abrir guillotina';
      case 4:
        return 'Cerrar guillotina';
      default:
        return 'Desconocido ($tipo)';
    }
  }
}
