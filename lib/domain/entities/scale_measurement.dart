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
  final int humedad;
  final int sensorInduc;

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
    humedad: 60,
    sensorInduc: 0,
  );
}
