import 'package:flutter_test/flutter_test.dart';
import 'package:test_jaguar/protocols/st567/st567_command.dart';

void main() {
  test('separa nombre y argumentos y descarta el \\r\\n', () {
    final St567Command? cmd = St567Command.tryParse('CTR,select,2,1500\r\n');
    expect(cmd, isNotNull);
    expect(cmd!.nombre, 'select');
    expect(cmd.args, <String>['2', '1500']);
    expect(cmd.texto, 'CTR,select,2,1500');
  });

  test('deshace el escapado del datasource', () {
    // Así llega del datasource real: el espacio como \s y el CRLF escapado.
    final St567Command? cmd =
        St567Command.tryParse(r'CTR,acum,Juan\sPerez\r\n');
    expect(cmd!.nombre, 'acum');
    expect(cmd.arg(0), 'Juan Perez');
  });

  test('un argumento vacío es válido y uno que falta se lee vacío', () {
    final St567Command? cmd = St567Command.tryParse(r'CTR,acum,\r\n');
    expect(cmd!.args, <String>['']);
    expect(cmd.arg(0), '');
    expect(cmd.arg(5), '');
  });

  test('sin argumentos', () {
    final St567Command? cmd = St567Command.tryParse('CTR,levelLock');
    expect(cmd!.nombre, 'levelLock');
    expect(cmd.args, isEmpty);
  });

  test('\\xNN y la barra escapada', () {
    final St567Command? cmd =
        St567Command.tryParse(r'CTR,descargaManual,A\x2DB\\,10');
    expect(cmd!.args, <String>[r'A-B\', '10']);
  });

  test('no toma lo que no es un CTR', () {
    expect(St567Command.tryParse('AT+CERO'), isNull);
    expect(St567Command.tryParse(r'AT+INICIO=1,2\r\n'), isNull);
    expect(St567Command.tryParse('CTR'), isNull);
    expect(St567Command.tryParse('CTR,'), isNull);
    expect(St567Command.tryParse(''), isNull);
  });
}
