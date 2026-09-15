import 'package:test_jaguar/domain/entities/scale_measurement.dart';
import 'package:test_jaguar/protocols/st407_remote/st407_screen.dart';

class St407PayloadDto {
  const St407PayloadDto({
    required this.screen,
    required this.measurement,
    required this.now,
  });

  final St407Screen screen;
  final ScaleMeasurement measurement;
  final DateTime now;

  String toProtocolString() {
    final String screenCode = screen.code.toString();
    switch (screen) {
      case St407Screen.main:
        final String dateTime = _formatDateTime(now);
        return '$screenCode,${measurement.peso},0,0,1,,,$dateTime\r\n';
      case St407Screen.loadingRecipe:
        return '$screenCode,${measurement.peso},20,117,Maiz\r\n';
      case St407Screen.loadingManual:
        return '$screenCode,${measurement.peso},20,1200,1\r\n';
      case St407Screen.unloadingGuide:
        return '$screenCode,${measurement.peso},0,150,M1\r\n';
      case St407Screen.unloadingManual:
        return '$screenCode,${measurement.peso},20,250,7\r\n';
      case St407Screen.mixing:
        return '$screenCode,1,23\r\n';
      case St407Screen.chooseRecipe:
        return '$screenCode,1,0,1200\r\n';
      case St407Screen.chooseAutonomous:
        return '$screenCode,1,ADGF,15/05/2017,17/05/2017,Receta1,Guia1\r\n';
      case St407Screen.chooseGuide:
        return '$screenCode,1,DescNov\r\n';
    }
  }

  String _formatDateTime(DateTime value) {
    final String day = value.day.toString().padLeft(2, '0');
    final String month = value.month.toString().padLeft(2, '0');
    final String year = (value.year % 100).toString().padLeft(2, '0');
    final String hour = value.hour.toString().padLeft(2, '0');
    final String minute = value.minute.toString().padLeft(2, '0');
    return '$day-$month-$year $hour:$minute';
  }
}
