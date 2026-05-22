class ScaleMeasurement {
  const ScaleMeasurement({
    required this.tara,
    required this.hold,
    required this.vbat,
    required this.peso,
    required this.estBalanza,
    required this.humedad,
    required this.sensorInduc,
  });

  final int tara;
  final int hold;
  final double vbat;
  final int peso;
  final int estBalanza;
  final double humedad;
  final int sensorInduc;

  ScaleMeasurement copyWith({
    int? tara,
    int? hold,
    double? vbat,
    int? peso,
    int? estBalanza,
    double? humedad,
    int? sensorInduc,
  }) {
    return ScaleMeasurement(
      tara: tara ?? this.tara,
      hold: hold ?? this.hold,
      vbat: vbat ?? this.vbat,
      peso: peso ?? this.peso,
      estBalanza: estBalanza ?? this.estBalanza,
      humedad: humedad ?? this.humedad,
      sensorInduc: sensorInduc ?? this.sensorInduc,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'tara': tara,
      'hold': hold,
      'vbat': vbat,
      'peso': peso,
      'estBalanza': estBalanza,
      'humedad': humedad,
      'sensorInduc': sensorInduc,
    };
  }

  static const ScaleMeasurement baseline = ScaleMeasurement(
    tara: 12,
    hold: 1,
    vbat: 3.9,
    peso: 0,
    estBalanza: 3,
    humedad: 10.0,
    sensorInduc: 0,
  );

  static ScaleMeasurement fromDynamicWeight({
    required int peso,
    required int sensorInduc,
  }) {
    return baseline.copyWith(
      peso: peso,
      sensorInduc: sensorInduc,
    );
  }
}
