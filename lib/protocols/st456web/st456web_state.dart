import 'package:test_jaguar/protocols/st456web/st456web_screen.dart';

/// Cómo se comporta el indicador simulado ante algunos comandos. Las fija el
/// tester desde la UI y sobreviven a un cambio de protocolo.
class St456webOptions {
  const St456webOptions({
    this.sincronizacionFalla = false,
    this.sinTrabajos = false,
    this.sinOperario = false,
  });

  /// `CTR,sync` termina en `35` (falló) en vez de `36` (exitosa).
  final bool sincronizacionFalla;

  /// `CTR,elegirTrabajo` responde el popup `20` en vez de la lista.
  final bool sinTrabajos;

  /// El indicador no tiene operario elegido: arrancar una receta o elegir un
  /// trabajo responde el popup `16`. El operario que se elige en la tablet
  /// (`42`) no le llega: la app lo valida localmente.
  final bool sinOperario;

  St456webOptions copyWith({
    bool? sincronizacionFalla,
    bool? sinTrabajos,
    bool? sinOperario,
  }) {
    return St456webOptions(
      sincronizacionFalla: sincronizacionFalla ?? this.sincronizacionFalla,
      sinTrabajos: sinTrabajos ?? this.sinTrabajos,
      sinOperario: sinOperario ?? this.sinOperario,
    );
  }
}

/// Foto inmutable del modo Remoto ST456web para la UI.
class St456webState {
  const St456webState({
    required this.screen,
    required this.options,
    required this.totalCargado,
    required this.operario,
    required this.detalle,
    required this.descargaPendiente,
  });

  /// Pantalla que el simulador está notificando.
  final St456webScreen screen;
  final St456webOptions options;

  /// Kilos en el mixer: suben con cada `acum` de carga y bajan con cada
  /// `acum` de descarga.
  final int totalCargado;

  /// Último operario que mandó la app en `CTR,acum,<operario>`.
  final String operario;

  /// Una línea con lo que está haciendo el indicador ("Cargando Maiz 250/600
  /// kg"), o vacío en reposo.
  final String detalle;

  /// Nombre del trabajo que quedó cargado sin descargar, o vacío. Es el que
  /// decide si elegir un trabajo da el `17` o el `14`.
  final String descargaPendiente;

  static const St456webState initial = St456webState(
    screen: St456webScreen.principal,
    options: St456webOptions(),
    totalCargado: 0,
    operario: '',
    detalle: '',
    descargaPendiente: '',
  );
}
