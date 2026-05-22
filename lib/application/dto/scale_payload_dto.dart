import 'dart:convert';

import 'package:test_jaguar/domain/entities/scale_measurement.dart';

class ScalePayloadDto {
  const ScalePayloadDto({required this.measurement});

  final ScaleMeasurement measurement;

  String toJsonUtf8String() => jsonEncode(measurement.toMap());
}
