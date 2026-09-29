import 'package:flutter_test/flutter_test.dart';
import 'package:test_jaguar/protocols/shared/ctr_command.dart';

void main() {
  test('separa nombre y argumentos y descarta el \\r\\n', () {
    final CtrCommand? cmd = CtrCommand.tryParse('CTR,select,2,1500\r\n');
    expect(cmd, isNotNull);
    expect(cmd!.nombre, 'select');
    expect(cmd.args, <String>['2', '1500']);
    expect(cmd.texto, 'CTR,select,2,1500');
  });

  test('deshace el escapado del datasource', () {
    // Así llega del datasource real: el espacio como \s y el CRLF escapado.
    final CtrCommand? cmd =
        CtrCommand.tryParse(r'CTR,acum,Juan\sPerez\r\n');
    expect(cmd!.nombre, 'acum');
    expect(cmd.arg(0), 'Juan Perez');
  });

  test('un argumento vacío es válido y uno que falta se lee vacío', () {
    final CtrCommand? cmd = CtrCommand.tryParse(r'CTR,acum,\r\n');
    expect(cmd!.args, <String>['']);
    expect(cmd.arg(0), '');
    expect(cmd.arg(5), '');
  });

  test('sin argumentos', () {
    final CtrCommand? cmd = CtrCommand.tryParse('CTR,levelLock');
    expect(cmd!.nombre, 'levelLock');
    expect(cmd.args, isEmpty);
  });

  test('\\xNN y la barra escapada', () {
    final CtrCommand? cmd =
        CtrCommand.tryParse(r'CTR,descargaManual,A\x2DB\\,10');
    expect(cmd!.args, <String>[r'A-B\', '10']);
  });

  test('no toma lo que no es un CTR', () {
    expect(CtrCommand.tryParse('AT+CERO'), isNull);
    expect(CtrCommand.tryParse(r'AT+INICIO=1,2\r\n'), isNull);
    expect(CtrCommand.tryParse('CTR'), isNull);
    expect(CtrCommand.tryParse('CTR,'), isNull);
    expect(CtrCommand.tryParse(''), isNull);
  });
}
