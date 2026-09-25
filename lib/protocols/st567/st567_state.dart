import 'package:test_jaguar/protocols/st567/st567_screen.dart';

/// Cómo se comporta el indicador simulado ante algunos comandos. Las fija el
/// tester desde la UI y sobreviven a un cambio de protocolo.
class St567Options {
  const St567Options({
    this.recetasConPreset = true,
    this.sincronizacionFalla = false,
    this.sinTrabajos = false,
    this.sinOperario = false,
  });

  /// Firmware ≥ 1.36.3: `CTR,elegirReceta` responde `60` (con preset) en vez
  /// de `30`.
  final bool recetasConPreset;

  /// `CTR,sync` termina en `35` (falló) en vez de `36` (exitosa).
  final bool sincronizacionFalla;

  /// `CTR,elegirTrabajo` responde el popup `20` en vez de la lista.
  final bool sinTrabajos;

  /// El indicador no tiene operario elegido: elegir una receta o un trabajo
  /// responde el popup `16`. El ST567 exige operario para cargar, y el que se
  /// elige en la tablet (`42`) no le llega: la app lo valida localmente.
  final bool sinOperario;

  St567Options copyWith({
    bool? recetasConPreset,
    bool? sincronizacionFalla,
    bool? sinTrabajos,
    bool? sinOperario,
  }) {
    return St567Options(
      recetasConPreset: recetasConPreset ?? this.recetasConPreset,
      sincronizacionFalla: sincronizacionFalla ?? this.sincronizacionFalla,
      sinTrabajos: sinTrabajos ?? this.sinTrabajos,
      sinOperario: sinOperario ?? this.sinOperario,
    );
  }
}

/// Foto inmutable del modo Remoto ST567 para la UI.
class St567State {
  const St567State({
    required this.screen,
    required this.options,
    required this.levelLock,
    required this.totalCargado,
    required this.operario,
    required this.detalle,
  });

  /// Pantalla que el simulador está notificando.
  final St567Screen screen;
  final St567Options options;
  final bool levelLock;

  /// Kilos en el mixer: suben con cada `acum` de carga y bajan con cada
  /// `acum` de descarga.
  final int totalCargado;

  /// Último operario que mandó la app en `CTR,acum,<operario>`.
  final String operario;

  /// Una línea con lo que está haciendo el indicador ("Cargando Maiz 250/600
  /// kg"), o vacío en reposo.
  final String detalle;

  static const St567State initial = St567State(
    screen: St567Screen.principal,
    options: St567Options(),
    levelLock: false,
    totalCargado: 0,
    operario: '',
    detalle: '',
  );
}
