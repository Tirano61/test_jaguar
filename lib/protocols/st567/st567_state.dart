import 'package:test_jaguar/protocols/st567/st567_screen.dart';

/// Foto inmutable del modo Remoto ST567 para la UI.
class St567State {
  const St567State({required this.screen});

  /// Pantalla que el simulador está notificando.
  final St567Screen screen;

  static const St567State initial = St567State(screen: St567Screen.principal);
}
