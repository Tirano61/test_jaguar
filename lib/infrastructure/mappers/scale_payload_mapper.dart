import 'package:test_jaguar/application/dto/scale_payload_dto.dart';
import 'package:test_jaguar/domain/entities/scale_measurement.dart';

class ScalePayloadMapper {
  const ScalePayloadMapper();

  String toJson(ScaleMeasurement measurement) {
    return ScalePayloadDto(measurement: measurement).toJsonUtf8String();
  }
}
