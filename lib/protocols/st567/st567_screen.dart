/// Pantallas del indicador ST567, con el código que viaja como primer campo de
/// la trama (`docs/protocolo-simulador-st567.md`, sección 6).
///
/// De las del ST456web (`1`, `3`, `8`…) sólo incluye la `18`, que el documento
/// propone para ver una guía sola porque el ST567 no tiene pantalla propia
/// (sección 7.18). No incluye las reservadas: `13` y el rango `100`-`110`, que
/// es del ST407.
enum St567Screen {
  principal(0, 'Principal'),
  cargaManual(2, 'Carga manual'),
  descargaManual(4, 'Descarga manual'),
  mezclando(6, 'Mezclando'),
  sinOperario(16, 'Popup: seleccionar operario'),
  cargaRealizada(17, 'Popup: ya realizó la carga'),
  sincronizando(19, 'Sincronizando'),
  detalleGuia(18, 'Detalle de guía'),
  sinTrabajos(20, 'Popup: no hay trabajos'),
  elegirReceta(30, 'Elegir receta'),
  detalleTrabajo(31, 'Detalle de trabajo'),
  elegirIngrediente(32, 'Elegir ingrediente'),
  loteYCantidad(33, 'Diálogo lote + cantidad'),
  trabajos(34, 'Trabajos'),
  sincronizacionFallida(35, 'Sincronización fallida'),
  sincronizacionExitosa(36, 'Sincronización exitosa'),
  detalleReceta(37, 'Detalle de receta'),
  cargaReceta(38, 'Carga por receta'),
  descargaGuia(39, 'Descarga por guía'),
  masCarga(40, 'Diálogo: preparar más carga'),
  reanudarTrabajo(41, 'Diálogo: ¿reanudar trabajo?'),
  cambioOperario(42, 'Cambio de operario'),
  operarioNoEncontrado(43, 'Popup: operario no encontrado'),
  claveIncorrecta(44, 'Popup: clave incorrecta'),
  indicadorOcupado(45, 'Popup: indicador ocupado'),
  elegirRecetaPreset(60, 'Elegir receta con preset');

  const St567Screen(this.code, this.name);

  final int code;
  final String name;

  String get label => '$code - $name';

  /// Popups sin botones: la app no tiene cómo salir de ellos, así que el
  /// indicador los tiene que reemplazar por otra pantalla.
  bool get isPopup => const <St567Screen>{
        sinOperario,
        cargaRealizada,
        sinTrabajos,
        operarioNoEncontrado,
        claveIncorrecta,
        indicadorOcupado,
      }.contains(this);

  /// Pantallas a las que el tester puede saltar desde la UI sin pasar por un
  /// comando: las que no necesitan una corrida en curso para tener sentido.
  /// Las de peso (`2`, `4`, `38`, `39`), la mezcla y los detalles sólo se
  /// alcanzan con los comandos de la app.
  static const List<St567Screen> forzables = <St567Screen>[
    principal,
    elegirReceta,
    elegirRecetaPreset,
    elegirIngrediente,
    trabajos,
    detalleGuia,
    cambioOperario,
    loteYCantidad,
    sincronizacionFallida,
    sincronizacionExitosa,
    masCarga,
    reanudarTrabajo,
    sinOperario,
    cargaRealizada,
    sinTrabajos,
    operarioNoEncontrado,
    claveIncorrecta,
    indicadorOcupado,
  ];
}
