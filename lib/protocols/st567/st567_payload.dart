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
