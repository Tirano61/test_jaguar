/// Un comando `CTR,<nombre>[,<arg>…]` que la app manda al ST567 por la
/// característica de escritura (`docs/protocolo-simulador-st567.md`, sección 4).
///
/// Es otra gramática que la de los `AT+`: distingue mayúsculas en los
/// argumentos (nombres de operario, lotes) y los espacios son parte del valor,
/// así que no puede pasar por la normalización que usa el orquestador para
/// esos comandos.
class St567Command {
  const St567Command(this.nombre, [this.args = const <String>[]]);

  /// El comando tal como lo escribe la app (`levelLock`, `cargaManual`…).
  final String nombre;
  final List<String> args;

  /// Argumento [index], o vacío si la app no lo mandó. `CTR,acum,` trae un
  /// operario vacío y es válido.
  String arg(int index) => index < args.length ? args[index] : '';

  /// El comando sin el `\r\n`, para los logs.
  String get texto => <String>['CTR', nombre, ...args].join(',');

  /// Interpreta lo que llegó por BLE. Devuelve `null` si no es un `CTR,`.
  ///
  /// [received] viene con los caracteres de control escapados por el
  /// datasource (`\r`, `\n`, `\s` por el espacio, `\\`, `\xNN`), así que
  /// primero se deshace ese escapado.
  static St567Command? tryParse(String received) {
    final String texto = _unescape(received).trim();
    final List<String> partes = texto.split(',');
    if (partes.length < 2 || partes.first.toUpperCase() != 'CTR') {
      return null;
    }
    final String nombre = partes[1].trim();
    if (nombre.isEmpty) {
      return null;
    }
    return St567Command(nombre, partes.sublist(2));
  }

  static String _unescape(String input) {
    final StringBuffer out = StringBuffer();
    int i = 0;
    while (i < input.length) {
      final String c = input[i];
      if (c != r'\' || i + 1 >= input.length) {
        out.write(c);
        i += 1;
        continue;
      }
      final String next = input[i + 1];
      switch (next) {
        case r'\':
          out.write(r'\');
        case 'r':
          out.write('\r');
        case 'n':
          out.write('\n');
        case 't':
          out.write('\t');
        case 's':
          out.write(' ');
        case 'x':
          final int? code = i + 3 < input.length
              ? int.tryParse(input.substring(i + 2, i + 4), radix: 16)
              : null;
          if (code != null) {
            out.writeCharCode(code);
            i += 4;
            continue;
          }
          out.write(r'\x');
        default:
          out.write('\\$next');
      }
      i += 2;
    }
    return out.toString();
  }
}
