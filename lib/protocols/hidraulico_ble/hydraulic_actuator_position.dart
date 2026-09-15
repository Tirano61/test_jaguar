/// Posición discreta de un actuador hidráulico (tubo o guillotina).
///
/// El recorrido entre totalmente cerrado y totalmente abierto se divide en
/// [steps] pasos: cada `AT+MOVIMIENTO` de abrir/cerrar mueve un paso y la
/// posición queda topeada en [closed] y [open].
abstract final class HydraulicActuatorPosition {
  /// Cantidad de pasos entre cerrado y abierto.
  static const int steps = 5;

  /// Tope inferior: totalmente cerrado.
  static const int closed = 0;

  /// Tope superior: totalmente abierto.
  static const int open = steps;

  /// Primer paso de apertura (la posición mínima que ya no es "cerrado").
  static const int firstOpenStep = 1;

  static int clamp(int value) => value.clamp(closed, open);

  /// Mueve un paso: `opening == true` abre, `false` cierra. Nunca pasa los
  /// topes.
  static int stepped(int value, {required bool opening}) =>
      clamp(value + (opening ? 1 : -1));

  /// Fracción 0.0 - 1.0 para dibujar la barra de progreso.
  static double fraction(int value) => clamp(value) / steps;

  static bool isClosed(int value) => clamp(value) == closed;

  static bool isFullyOpen(int value) => clamp(value) == open;

  static String label(int value) {
    final int position = clamp(value);
    if (position == closed) {
      return 'CERRADO';
    }
    if (position == open) {
      return 'ABIERTO';
    }
    return 'PASO $position/$steps';
  }
}
