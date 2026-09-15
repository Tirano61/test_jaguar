/// Estados de la toma de fuerza que viajan en la key `tomaFuerza` del JSON
/// del modo Hidráulico BLE.
abstract final class HydraulicPtoState {
  /// Apagada.
  static const int off = 0;

  /// Encendida: el único estado en el que el JSON manda rpm reales.
  static const int on = 1;

  /// Pedido a la app: encienda la toma de fuerza.
  static const int requestOn = 2;

  /// Pedido a la app: apague la toma de fuerza.
  static const int requestOff = 3;

  static bool isOn(int value) => value == on;
}

/// RPM simuladas de la toma de fuerza.
///
/// El simulador deja elegir un valor dentro de [min] - [max]; ese valor solo
/// viaja en la key `rpm` cuando la toma de fuerza está encendida
/// ([HydraulicPtoState.on]). En el resto de los estados el protocolo manda
/// `rpm: 0`.
abstract final class HydraulicPtoRpm {
  /// Mínimo simulable.
  static const int min = 200;

  /// Máximo simulable.
  static const int max = 1200;

  /// Régimen estándar de toma de fuerza, usado como valor inicial.
  static const int defaultValue = 540;

  /// Salto entre posiciones del slider del simulador.
  static const int step = 10;

  static int clamp(int value) => value.clamp(min, max);
}
