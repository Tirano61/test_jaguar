/// Cómo se enmarcan los bytes de un payload antes de salir por notify.
///
/// Es una propiedad del protocolo, no del perfil GATT. Hoy coinciden (sólo los
/// protocolos sobre ABF3 usan cabecera), pero declararla en el protocolo evita
/// que el transporte tenga que deducirla comparando UUIDs.
enum PayloadFraming {
  /// Bytes UTF-8 crudos, partidos por MTU y sin cabecera. Los usan Jaguar BLE,
  /// Manual e Hidráulico BLE, que mandan JSON.
  plain,

  /// Cabecera binaria de 5 bytes delante de cada parte: `idPaquete`,
  /// `totalPartes`, `numParte` y `longitud` (uint16 big-endian) del mensaje
  /// completo. La usan los protocolos remotos, que mandan cadenas separadas por
  /// coma: el ST407 hoy, y el ST456web y el ST567 cuando se implementen.
  fiveByteHeader,
}
