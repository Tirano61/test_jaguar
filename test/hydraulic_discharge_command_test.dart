import 'package:flutter_test/flutter_test.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_discharge_command.dart';

HydraulicDischargeCommand _inicio({required int modo}) {
  final HydraulicDischargeCommand? command =
      HydraulicDischargeCommand.tryParse('AT+INICIO=1500,300,100,$modo,2');
  expect(command, isNotNull, reason: 'no parseó el AT+INICIO con modo $modo');
  return command!;
}

void main() {
  test('modo 2 marca la descarga como "dos descargas"', () {
    final HydraulicDischargeCommand command =
        _inicio(modo: HydraulicDischargeMode.dosDescargas);

    expect(command.modo, 2);
    expect(command.isDosDescargas, isTrue);
  });

  test('el resto de los modos no son "dos descargas"', () {
    for (final int modo in <int>[
      HydraulicDischargeMode.unaDescarga,
      HydraulicDischargeMode.total,
      HydraulicDischargeMode.noria,
      0,
      9,
    ]) {
      expect(
        _inicio(modo: modo).isDosDescargas,
        isFalse,
        reason: 'modo $modo',
      );
    }
  });

  test('las etiquetas de modo se mantienen', () {
    expect(_inicio(modo: 1).modoLabel, 'Una descarga');
    expect(_inicio(modo: 2).modoLabel, 'Dos descargas');
    expect(_inicio(modo: 3).modoLabel, 'Total');
    expect(_inicio(modo: 4).modoLabel, 'Noria');
    expect(_inicio(modo: 9).modoLabel, 'Desconocido (9)');
  });
}
