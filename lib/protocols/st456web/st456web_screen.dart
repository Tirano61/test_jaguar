/// Pantallas del indicador ST456web, con el código que viaja como primer campo
/// de la trama (`docs/protocolo-simulador-st456web.md`, sección 6).
///
/// No incluye las del ST567 (`30`-`41`, `60`) ni las reservadas: `13` y el
/// rango `100`-`110`, que es del ST407.
enum St456webScreen {
  principal(0, 'Principal'),
  cargaReceta(1, 'Carga por receta'),
  cargaManual(2, 'Carga manual'),
  descargaGuia(3, 'Descarga por guía'),
  descargaManual(4, 'Descarga manual'),
  mezclando(6, 'Mezclando'),
  elegirReceta(8, 'Elegir receta'),
  elegirAutonomo(9, 'Elegir autónomo'),
  elegirGuia(10, 'Elegir guía'),
  trabajos(11, 'Trabajos'),
  usarParcial(12, 'Usar parcial'),
  descargaPendiente(14, 'Diálogo: descarga pendiente'),
  cargaODescarga(15, 'Diálogo: ¿carga o descarga?'),
  sinOperario(16, 'Popup: seleccionar operario'),
  cargaRealizada(17, 'Popup: ya realizó la carga'),
  detalle(18, 'Detalle de receta / guía'),
  sincronizando(19, 'Sincronizando'),
  sinTrabajos(20, 'Popup: no hay trabajos'),
  sincronizacionFallida(35, 'Sincronización fallida'),
  sincronizacionExitosa(36, 'Sincronización exitosa'),
  cambioOperario(42, 'Cambio de operario'),
  operarioNoEncontrado(43, 'Popup: operario no encontrado'),
  claveIncorrecta(44, 'Popup: clave incorrecta'),
  indicadorOcupado(45, 'Popup: indicador ocupado');

  const St456webScreen(this.code, this.name);

  final int code;
  final String name;

  String get label => '$code - $name';

  /// Popups sin botones: la app no tiene cómo salir de ellos, así que el
  /// indicador los tiene que reemplazar por otra pantalla.
  bool get isPopup => const <St456webScreen>{
        sinOperario,
        cargaRealizada,
        sinTrabajos,
        operarioNoEncontrado,
        claveIncorrecta,
        indicadorOcupado,
      }.contains(this);

  /// Pantallas a las que el tester puede saltar desde la UI sin pasar por un
  /// comando: las que no necesitan una corrida en curso para tener sentido.
  /// Las de peso (`1`-`4`) y la mezcla sólo se alcanzan con los comandos de la
  /// app.
  static const List<St456webScreen> forzables = <St456webScreen>[
    principal,
    elegirReceta,
    elegirAutonomo,
    elegirGuia,
    trabajos,
    usarParcial,
    detalle,
    cambioOperario,
    sincronizando,
    sincronizacionFallida,
    sincronizacionExitosa,
    descargaPendiente,
    cargaODescarga,
    sinOperario,
    cargaRealizada,
    sinTrabajos,
    operarioNoEncontrado,
    claveIncorrecta,
    indicadorOcupado,
  ];
}
