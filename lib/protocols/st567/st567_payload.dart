import 'package:test_jaguar/protocols/st567/st567_catalog.dart';
import 'package:test_jaguar/protocols/st567/st567_screen.dart';

/// Arma el texto de cada pantalla del ST567: `<id>,<campo1>,…,<campoN>\r\n`.
///
/// Son funciones puras sobre valores ya resueltos; qué pantalla toca y con qué
/// datos lo decide `St567Protocol`. Las reglas de formato salen de
/// `docs/protocolo-simulador-st567.md` (sección 3.4): sin espacios después de
/// las comas, sin comas dentro de los campos y enteros donde la app hace
/// `int.tryParse(...)!`. La cabecera de 5 bytes la pone el transporte.
class St567Payload {
  St567Payload._();

  /// Pantalla `0`: `peso,estabilidad,unidad,operario,fecha,levelLock`.
  static String principal({
    required int peso,
    required bool estable,
    required String operario,
    required DateTime fecha,
    required bool levelLock,
  }) {
    return frame(St567Screen.principal, <Object>[
      peso,
      _flag(estable),
      'kg',
      operario,
      _formatFecha(fecha),
      _flag(levelLock),
    ]);
  }

  /// Pantalla `30`: `n,(indice,nombre)*n`.
  static String recetas(List<St567Receta> pagina) {
    return frame(St567Screen.elegirReceta, <Object>[
      pagina.length,
      for (final St567Receta r in pagina) ...<Object>[r.indice, r.nombre],
    ]);
  }

  /// Pantalla `60`: `n,(indice,nombre,cantidadPreset)*n`.
  static String recetasConPreset(List<St567Receta> pagina) {
    return frame(St567Screen.elegirRecetaPreset, <Object>[
      pagina.length,
      for (final St567Receta r in pagina)
        ...<Object>[r.indice, r.nombre, r.preset],
    ]);
  }

  /// Pantalla `32`: `n,(indice,nombre)*n`.
  static String ingredientes(List<St567Ingrediente> pagina) {
    return frame(St567Screen.elegirIngrediente, <Object>[
      pagina.length,
      for (final St567Ingrediente i in pagina) ...<Object>[i.indice, i.nombre],
    ]);
  }

  /// Pantalla `34`: `n,(indice,nombre,completo)*n`. [completo] dice si cada
  /// trabajo ya está realizado, que cambia durante la sesión.
  static String trabajos(
    List<St567Trabajo> pagina, {
    required bool Function(St567Trabajo) completo,
  }) {
    return frame(St567Screen.trabajos, <Object>[
      pagina.length,
      for (final St567Trabajo t in pagina)
        ...<Object>[t.indice, t.nombre, _flag(completo(t))],
    ]);
  }

  /// Pantalla `42`: `n,(nombre,password)*n`.
  static String operarios(List<St567Operario> operarios) {
    return frame(St567Screen.cambioOperario, <Object>[
      operarios.length,
      for (final St567Operario o in operarios) ...<Object>[o.nombre, o.pin],
    ]);
  }

  /// Pantalla `2`: `total,parcial,kgACargar,nroIngrediente,ingrediente,lock,
  /// level,sirena`.
  static String cargaManual(
    St567Pesaje pesaje, {
    required String nroIngrediente,
    required String ingrediente,
  }) {
    return frame(St567Screen.cargaManual, <Object>[
      pesaje.total,
      pesaje.parcial,
      pesaje.objetivo,
      nroIngrediente,
      ingrediente,
      ...pesaje.flags,
    ]);
  }

  /// Pantalla `4`: `total,parcial,kgADescargar,lote,lock,level,sirena`.
  static String descargaManual(St567Pesaje pesaje, {required String lote}) {
    return frame(St567Screen.descargaManual, <Object>[
      pesaje.total,
      pesaje.parcial,
      pesaje.objetivo,
      lote,
      ...pesaje.flags,
    ]);
  }

  /// Pantalla `6`: `minutos,segundos`. Los segundos van sin rellenar: la app
  /// los completa a dos dígitos.
  static String mezclando(int segundosRestantes) {
    return frame(St567Screen.mezclando, <Object>[
      segundosRestantes ~/ 60,
      segundosRestantes % 60,
    ]);
  }

  /// Pantalla `19`: `porcentaje`, sin el signo (la app no lo agrega).
  static String sincronizando(int porcentaje) {
    return frame(St567Screen.sincronizando, <Object>[porcentaje]);
  }

  /// Pantalla `31`: `nombreTrabajo,nombreReceta,bachada,porcentaje,mezclaSeg,
  /// nIng,nLotes,viajes,(ing,kg)*nIng,(lote,kg)*nLotes`.
  static String detalleTrabajo(
    St567Trabajo trabajo, {
    required St567Receta receta,
    required List<St567IngredienteReceta> ingredientes,
  }) {
    return frame(St567Screen.detalleTrabajo, <Object>[
      trabajo.nombre,
      receta.nombre,
      trabajo.bachada,
      trabajo.porcentaje,
      receta.mezclaSeg,
      ingredientes.length,
      trabajo.lotes.length,
      trabajo.viajes,
      for (final St567IngredienteReceta i in ingredientes)
        ...<Object>[i.nombre, i.cantidad],
      for (final St567Lote l in trabajo.lotes) ...<Object>[l.nombre, l.kg],
    ]);
  }

  /// Pantalla `18` con `tipo` 2 (sólo guía): `tipo,nombreReceta,nombreGuia,
  /// minutosMezcla,nIng,nLotes,(lote,kg)*nLotes`.
  ///
  /// Es la pantalla de detalle del ST456web. En tipo 2 la app muestra el campo
  /// de la receta en el panel de la guía, así que el nombre va en los dos.
  static String detalleGuia(String guia, List<St567Lote> lotes) {
    return frame(St567Screen.detalleGuia, <Object>[
      2,
      guia,
      guia,
      0,
      0,
      lotes.length,
      for (final St567Lote l in lotes) ...<Object>[l.nombre, l.kg],
    ]);
  }

  /// Pantalla `37`: `nombre,mezclaSeg,tipo,n,(nombre,cantidad,tipoAviso,aviso,
  /// mezclaSeg)*n`. Cada ingrediente lleva los cinco campos siempre: uno
  /// truncado rompe el parseo en la app.
  static String detalleReceta(St567Receta receta) {
    return frame(St567Screen.detalleReceta, <Object>[
      receta.nombre,
      receta.mezclaSeg,
      receta.tipo,
      receta.ingredientes.length,
      for (final St567IngredienteReceta i in receta.ingredientes)
        ...<Object>[i.nombre, i.cantidad, i.tipoAviso, i.aviso, i.mezclaSeg],
    ]);
  }

  /// Pantalla `38`: `total,parcial,kgACargar,ingredienteActual,lock,level,
  /// sirena,n,(nombre,cantidad,tipoAviso,aviso,mezclaSeg,estado)*n`.
  ///
  /// `ingredienteActual` tiene que ser idéntico al `nombre` de la lista para
  /// que la app resalte la tarjeta.
  static String cargaReceta(
    St567Pesaje pesaje, {
    required String ingredienteActual,
    required List<({St567IngredienteReceta ingrediente, bool cargado})> items,
  }) {
    return frame(St567Screen.cargaReceta, <Object>[
      pesaje.total,
      pesaje.parcial,
      pesaje.objetivo,
      ingredienteActual,
      ...pesaje.flags,
      items.length,
      for (final item in items)
        ...<Object>[
          item.ingrediente.nombre,
          item.ingrediente.cantidad,
          item.ingrediente.tipoAviso,
          item.ingrediente.aviso,
          item.ingrediente.mezclaSeg,
          _flag(item.cargado),
        ],
    ]);
  }

  /// Pantalla `39`: `total,parcial,kgADescargar,loteActual,lock,level,sirena,
  /// n,(nombre,parcial,total)*n`.
  static String descargaGuia(
    St567Pesaje pesaje, {
    required String loteActual,
    required List<({String nombre, int descargado, int total})> lotes,
  }) {
    return frame(St567Screen.descargaGuia, <Object>[
      pesaje.total,
      pesaje.parcial,
      pesaje.objetivo,
      loteActual,
      ...pesaje.flags,
      lotes.length,
      for (final lote in lotes)
        ...<Object>[lote.nombre, lote.descargado, lote.total],
    ]);
  }

  /// Una pantalla con [campos] después del ID; sin campos sirve para los
  /// popups y los diálogos (`33`, `35`, `36`, `40`, `41`…).
  static String frame(St567Screen screen, [List<Object> campos = const <Object>[]]) {
    return '${<Object>[screen.code, ...campos].join(',')}\r\n';
  }

  static String _flag(bool value) => value ? '1' : '0';

  /// `dd/MM/yyyy HH:mm`. La app lo muestra tal cual llega.
  static String _formatFecha(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)}/${value.year} '
        '${two(value.hour)}:${two(value.minute)}';
  }
}

/// Los campos que comparten las pantallas de peso (`2`, `4`, `38`, `39`):
/// total del mixer, lo cargado o descargado en el paso actual, el objetivo del
/// paso y los tres indicadores. La app calcula el peso grande como
/// `objetivo - parcial`.
class St567Pesaje {
  const St567Pesaje({
    required this.total,
    required this.parcial,
    required this.objetivo,
    required this.lock,
    required this.level,
    required this.sirena,
  });

  final int total;

  /// Entero obligatorio: la app hace `int.tryParse(...)!`.
  final int parcial;

  /// Entero obligatorio, igual que [parcial].
  final int objetivo;
  final bool lock;
  final bool level;
  final bool sirena;

  List<String> get flags => <String>[
        St567Payload._flag(lock),
        St567Payload._flag(level),
        St567Payload._flag(sirena),
      ];
}
