/// Valores del campo `modo` de `AT+INICIO`.
abstract final class HydraulicDischargeMode {
  static const int unaDescarga = 1;

  /// Dos descargas: la primera cierra con `AT+GUARDARDOS` en lugar de
  /// `AT+GUARDAR`, y la app manda un segundo `AT+INICIO` con modo
  /// [unaDescarga] para el tramo restante.
  static const int dosDescargas = 2;

  static const int total = 3;

  static const int noria = 4;
}

/// Comando `AT+INICIO=<kgDescarga>,<kgTubo>,<kgPrecierre>,<modo>,<velocidad>`
/// recibido por characteristic write en el modo Hidráulico BLE.
class HydraulicDischargeCommand {
  const HydraulicDischargeCommand({
    required this.kgDescarga,
    required this.kgTubo,
    required this.kgPrecierre,
    required this.modo,
    required this.velocidad,
  });

  final int kgDescarga;
  final int kgTubo;
  final int kgPrecierre;
  final int modo;
  final int velocidad;

  static final RegExp _pattern =
      RegExp(r'^AT\+INICIO=(-?\d+),(-?\d+),(-?\d+),(\d+),(\d+)$');

  /// [normalizedCommand] debe venir ya en mayúsculas y sin espacios/CRLF
  /// (mismo formato que produce `_normalizeIncomingCommand` en el
  /// orquestador). Devuelve `null` si no matchea el formato esperado.
  static HydraulicDischargeCommand? tryParse(String normalizedCommand) {
    final RegExpMatch? match = _pattern.firstMatch(normalizedCommand);
    if (match == null) {
      return null;
    }

    final int? kgDescarga = int.tryParse(match.group(1)!);
    final int? kgTubo = int.tryParse(match.group(2)!);
    final int? kgPrecierre = int.tryParse(match.group(3)!);
    final int? modo = int.tryParse(match.group(4)!);
    final int? velocidad = int.tryParse(match.group(5)!);

    if (kgDescarga == null ||
        kgTubo == null ||
        kgPrecierre == null ||
        modo == null ||
        velocidad == null) {
      return null;
    }

    return HydraulicDischargeCommand(
      kgDescarga: kgDescarga,
      kgTubo: kgTubo,
      kgPrecierre: kgPrecierre,
      modo: modo,
      velocidad: velocidad,
    );
  }

  /// Regla de negocio documentada por el protocolo: la descarga sólo es
  /// consistente si kgDescarga es mayor que kgTubo. La otra regla (kgDescarga
  /// <= peso actual en tolva, con el igual reservado a la descarga total)
  /// depende del estado en el momento de recibir el comando y se valida en el
  /// orquestador.
  bool get hasValidRange => kgDescarga > kgTubo;

  /// Modo 2: al completar la descarga la caja manda `AT+GUARDARDOS` en lugar
  /// de `AT+GUARDAR`, para que la app guarde/imprima/envíe igual pero se quede
  /// en descarga y pida el segundo tramo con un `AT+INICIO` en modo 1.
  /// Cualquier otro modo (incluido uno desconocido) cierra con `AT+GUARDAR`.
  bool get isDosDescargas => modo == HydraulicDischargeMode.dosDescargas;

  String get modoLabel {
    switch (modo) {
      case HydraulicDischargeMode.unaDescarga:
        return 'Una descarga';
      case HydraulicDischargeMode.dosDescargas:
        return 'Dos descargas';
      case HydraulicDischargeMode.total:
        return 'Total';
      case HydraulicDischargeMode.noria:
        return 'Noria';
      default:
        return 'Desconocido ($modo)';
    }
  }

  String get velocidadLabel {
    switch (velocidad) {
      case 1:
        return 'Lenta';
      case 2:
        return 'Normal';
      case 3:
        return 'Rápida';
      case 4:
        return 'Variable';
      default:
        return 'Desconocida ($velocidad)';
    }
  }

  String get summary =>
      'descarga=$kgDescarga kg, tubo=$kgTubo kg, precierre=$kgPrecierre kg, '
      'modo=$modoLabel, velocidad=$velocidadLabel';
}
