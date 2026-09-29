import 'package:test_jaguar/protocols/st456web/st456web_catalog.dart';
import 'package:test_jaguar/protocols/st456web/st456web_screen.dart';

/// Arma el texto de cada pantalla del ST456web: `<id>,<campo1>,…,<campoN>\r\n`.
///
/// Son funciones puras sobre valores ya resueltos; qué pantalla toca y con qué
/// datos lo decide `St456webProtocol`. Las reglas de formato salen de
/// `docs/protocolo-simulador-st456web.md` (sección 3.4): sin espacios después
/// de las comas, sin comas dentro de los campos y enteros donde la app hace
/// `int.tryParse(...)!`. La cabecera de 5 bytes la pone el transporte.
class St456webPayload {
  St456webPayload._();

  /// Tope de la app para la pantalla `11`: más de 6 trabajos rompen la lista.
  static const int maxTrabajos = 6;

  /// Pantalla `0`: `peso,estabilidad,unidad,operario,fecha,levelLock`. El
  /// levelLock es del ST567: el ST456web lo manda siempre en `0`.
  static String principal({
    required int peso,
    required bool estable,
    required String operario,
    required DateTime fecha,
  }) {
    return frame(St456webScreen.principal, <Object>[
      peso,
      _flag(estable),
      'kg',
      operario,
      _formatFecha(fecha),
      0,
    ]);
  }

  /// Pantalla `1`: `total,parcial,kgACargar,ingrediente,lock,level,sirena`.
  static String cargaReceta(
    St456webPesaje pesaje, {
    required String ingrediente,
  }) {
    return frame(St456webScreen.cargaReceta, <Object>[
      pesaje.total,
      pesaje.parcial,
      pesaje.objetivo,
      ingrediente,
      ...pesaje.flags,
    ]);
  }

  /// Pantalla `2`: `total,parcial,kgACargar,nroIngrediente,ingrediente,lock,
  /// level,sirena`.
  static String cargaManual(
    St456webPesaje pesaje, {
    required String nroIngrediente,
    required String ingrediente,
  }) {
    return frame(St456webScreen.cargaManual, <Object>[
      pesaje.total,
      pesaje.parcial,
      pesaje.objetivo,
      nroIngrediente,
      ingrediente,
      ...pesaje.flags,
    ]);
  }

  /// Pantalla `3`: `total,parcial,kgADescargar,lote,lock,level,sirena`.
  static String descargaGuia(St456webPesaje pesaje, {required String lote}) {
    return frame(St456webScreen.descargaGuia, <Object>[
      pesaje.total,
      pesaje.parcial,
      pesaje.objetivo,
      lote,
      ...pesaje.flags,
    ]);
  }

  /// Pantalla `4`: `total,parcial,kgADescargar,lote,lock,level,sirena`.
  static String descargaManual(St456webPesaje pesaje, {required String lote}) {
    return frame(St456webScreen.descargaManual, <Object>[
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
    return frame(St456webScreen.mezclando, <Object>[
      segundosRestantes ~/ 60,
      segundosRestantes % 60,
    ]);
  }

  /// Pantalla `8`: `nombre,cantidad`.
  static String receta(St456webReceta receta) {
    return frame(
      St456webScreen.elegirReceta,
      <Object>[receta.nombre, receta.cantidad],
    );
  }

  /// Pantalla `9`: `numero,nombre,fechaInicial,fechaFinal,receta,guia`. La app
  /// ignora la trama si falta alguno.
  static String autonomo(St456webAutonomo autonomo) {
    return frame(St456webScreen.elegirAutonomo, <Object>[
      autonomo.numero,
      autonomo.nombre,
      autonomo.fechaInicial,
      autonomo.fechaFinal,
      autonomo.receta,
      autonomo.guia,
    ]);
  }

  /// Pantalla `10`: `numero,nombre`.
  static String guia(St456webGuia guia) {
    return frame(St456webScreen.elegirGuia, <Object>[guia.numero, guia.nombre]);
  }

  /// Pantalla `11`: `n,(indice,orden,tipo,nombre,completado)*n`, con
  /// `n` ≤ [maxTrabajos]. [completo] dice si cada trabajo ya está realizado,
  /// que cambia durante la sesión.
  static String trabajos(
    List<St456webTrabajo> pagina, {
    required bool Function(St456webTrabajo) completo,
  }) {
    assert(pagina.length <= maxTrabajos, 'la app muestra hasta 6 trabajos');
    return frame(St456webScreen.trabajos, <Object>[
      pagina.length,
      for (final St456webTrabajo t in pagina)
        ...<Object>[t.indice, t.orden, t.tipo.code, t.nombre, _flag(completo(t))],
    ]);
  }

  /// Pantalla `12`: `parcial`.
  static String parcial(int kg) {
    return frame(St456webScreen.usarParcial, <Object>[kg]);
  }

  /// Pantalla `18` con `tipo` 1 (sólo receta): `tipo,nombreReceta,nombreGuia,
  /// minutosMezcla,nIng,nLotes,(ing,kg)*nIng`.
  static String detalleReceta(
    St456webReceta receta,
    List<St456webIngrediente> ingredientes,
  ) {
    return frame(St456webScreen.detalle, <Object>[
      1,
      receta.nombre,
      '',
      receta.minutosMezcla,
      ingredientes.length,
      0,
      for (final St456webIngrediente i in ingredientes) ...<Object>[i.nombre, i.kg],
    ]);
  }

  /// Pantalla `18` con `tipo` 2 (sólo guía). La app muestra el campo de la
  /// receta en el panel de la guía, así que el nombre va en los dos.
  static String detalleGuia(St456webGuia guia) {
    return frame(St456webScreen.detalle, <Object>[
      2,
      guia.nombre,
      guia.nombre,
      0,
      0,
      guia.lotes.length,
      for (final St456webLote l in guia.lotes) ...<Object>[l.nombre, l.kg],
    ]);
  }

  /// Pantalla `18` con `tipo` 3 (receta y guía lado a lado).
  static String detalleRecetaYGuia(
    St456webReceta receta,
    List<St456webIngrediente> ingredientes,
    St456webGuia guia,
  ) {
    return frame(St456webScreen.detalle, <Object>[
      3,
      receta.nombre,
      guia.nombre,
      receta.minutosMezcla,
      ingredientes.length,
      guia.lotes.length,
      for (final St456webIngrediente i in ingredientes) ...<Object>[i.nombre, i.kg],
      for (final St456webLote l in guia.lotes) ...<Object>[l.nombre, l.kg],
    ]);
  }

  /// Pantalla `19`: `porcentaje`, sin el signo (la app no lo agrega).
  static String sincronizando(int porcentaje) {
    return frame(St456webScreen.sincronizando, <Object>[porcentaje]);
  }

  /// Pantalla `42`: `n,(nombre,password)*n`.
  static String operarios(List<St456webOperario> operarios) {
    return frame(St456webScreen.cambioOperario, <Object>[
      operarios.length,
      for (final St456webOperario o in operarios) ...<Object>[o.nombre, o.pin],
    ]);
  }

  /// Una pantalla con [campos] después del ID; sin campos sirve para los
  /// popups y los diálogos (`14`, `15`, `35`, `36`…).
  static String frame(
    St456webScreen screen, [
    List<Object> campos = const <Object>[],
  ]) {
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

/// Los campos que comparten las pantallas de peso (`1`-`4`): el total, lo
/// cargado o descargado en el paso actual, el objetivo del paso y los tres
/// indicadores. La app calcula el peso grande como `objetivo - parcial`.
class St456webPesaje {
  const St456webPesaje({
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
        St456webPayload._flag(lock),
        St456webPayload._flag(level),
        St456webPayload._flag(sirena),
      ];
}
