import 'package:test_jaguar/protocols/st456web/st456web_screen.dart';

/// Foto inmutable del modo Remoto ST456web para la UI.
class St456webState {
  const St456webState({required this.screen});

  /// Pantalla que el simulador está notificando.
  final St456webScreen screen;

  static const St456webState initial =
      St456webState(screen: St456webScreen.principal);
}
