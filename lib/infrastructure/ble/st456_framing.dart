/// Implementación del framing ST456 para notificaciones BLE de pantallas
/// Basado en el protocolo del firmware real

import 'dart:math';
import 'dart:typed_data';

class ST456Framer {
  static const int MTU = 20; // Valor típico para BLE GATT
  int _packetId = 0;

  /// Función de ayuda para inspección en hex
  static String hexDump(List<int> data, [int? length]) {
    final len = length ?? data.length;
    return data.take(len).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
  }

  /// Implementa el mismo framing ST456 que usa el firmware real
  List<List<int>> frameMessage(String dataStr) {
    // Convertir string a bytes ASCII
    final dataBytes = Uint8List.fromList(dataStr.codeUnits);
    
    // Asegurar terminación CRLF al final si no está
    bool hasCRLF = false;
    if (dataBytes.length >= 2) {
      hasCRLF = dataBytes[dataBytes.length - 2] == 0x0D && 
                dataBytes[dataBytes.length - 1] == 0x0A;
    }
    
    Uint8List messageBytes;
    if (!hasCRLF) {
      // Agregar CRLF al final
      messageBytes = Uint8List.fromList([
        ...dataBytes,
        0x0D, // \r
        0x0A  // \n
      ]);
    } else {
      messageBytes = dataBytes;
    }

    final length = messageBytes.length;
    final chunkPayloadSize = MTU - 3 - 5; // mtu - 3 (checksum) - 5 (header)
    
    // Validar que chunk_payload_size sea positivo
    if (chunkPayloadSize <= 0) {
      throw Exception('MTU $MTU demasiado pequeño para el framing');
    }

    final totalTramas = (length / chunkPayloadSize).ceil();
    
    print('DEBUG: dataStr="$dataStr"');
    print('DEBUG: length=$length, chunkPayloadSize=$chunkPayloadSize, totalTramas=$totalTramas');

    final tramas = <List<int>>[];

    for (int trama = 0; trama < totalTramas; trama++) {
      final offset = trama * chunkPayloadSize;
      final toSend = min(chunkPayloadSize, length - offset);
      
      // Crear buffer de to_send + 5 bytes de header
      final buffer = Uint8List(toSend + 5);
      
      // Construir cabecera
      buffer[0] = _packetId; // packet_id (uint8 rotativo)
      buffer[1] = totalTramas; // total_tramas
      buffer[2] = trama + 1; // numero_trama (arranca en 1)
      buffer[3] = (length >> 8) & 0xFF; // length high
      buffer[4] = length & 0xFF; // length low
      
      // Copiar payload parcial
      for (int i = 0; i < toSend; i++) {
        buffer[5 + i] = messageBytes[offset + i];
      }
      
      tramas.add(buffer.toList());
      
      print('DEBUG: packet_id=$_packetId, total_tramas=$totalTramas, '
            'numero_trama=${trama + 1}, length_total=$length, to_send=$toSend, '
            'primeros_bytes=${hexDump(buffer, min(10, buffer.length))}');
    }
    
    // Incrementar packet_id para la próxima transmisión
    _packetId = (_packetId + 1) & 0xFF;
    
    return tramas;
  }

  /// Reconstruye el mensaje original a partir de las tramas
  String reconstructMessage(List<List<int>> tramas) {
    if (tramas.isEmpty) return '';
    
    // Obtener el packet_id y total_tramas del primer mensaje
    final packetId = tramas[0][0];
    final totalTramas = tramas[0][1];
    final length = (tramas[0][3] << 8) | tramas[0][4];
    
    // Verificar consistencia
    for (int i = 0; i < tramas.length; i++) {
      if (tramas[i][0] != packetId) {
        throw Exception('packet_id inconsistente en trama $i');
      }
      if (tramas[i][1] != totalTramas) {
        throw Exception('total_tramas inconsistente en trama $i');
      }
      if (tramas[i][2] != i + 1) {
        throw Exception('numero_trama inconsistente en trama $i');
      }
    }
    
    // Reconstruir el mensaje
    final reconstructed = Uint8List(length);
    
    for (final trama in tramas) {
      final offset = (trama[2] - 1) * (MTU - 3 - 5);
      final payloadStart = 5;
      final payloadEnd = payloadStart + trama.length - 5;
      
      for (int i = payloadStart; i < payloadEnd; i++) {
        reconstructed[offset + (i - payloadStart)] = trama[i];
      }
    }
    
    // Convertir a string y eliminar el CRLF final si existe
    final result = String.fromCharCodes(reconstructed);
    if (result.endsWith('\r\n')) {
      return result.substring(0, result.length - 2);
    }
    
    return result;
  }

  /// Modo test local para verificar el funcionamiento
  void testFraming() {
    print('=== TEST DE FRAMING ST456 ===');
    
    // Mensaje largo de prueba
    String testMessage = '60,123,abc,def,ghi,jkl,mno,pqr,stu,vwx,yz';
    // Hacerlo más largo para asegurar total_tramas > 1
    testMessage = List.filled(50, testMessage).join(',');
    
    print('Mensaje de prueba: "$testMessage"');
    print('Longitud: ${testMessage.length} caracteres');
    
    // Enviar mensaje
    final tramas = frameMessage(testMessage);
    
    print('\nTotal de tramas enviadas: ${tramas.length}');
    
    // Verificar condiciones del test
    assert(tramas.length > 1, 'Debe haber más de una trama');
    
    // Verificar que todas las tramas tienen el mismo length_total en header
    final firstLength = (tramas[0][3] << 8) | tramas[0][4];
    for (int i = 0; i < tramas.length; i++) {
      final length = (tramas[i][3] << 8) | tramas[i][4];
      assert(length == firstLength, 'Longitud inconsistente en trama $i');
    }
    
    // Verificar que numero_trama es secuencial
    for (int i = 0; i < tramas.length; i++) {
      assert(tramas[i][2] == i + 1, 'numero_trama no secuencial en trama $i');
    }
    
    print('✓ Todas las condiciones del test se cumplen');
    
    // Reconstruir mensaje
    final reconstructed = reconstructMessage(tramas);
    print('\nMensaje original: "$testMessage"');
    print('Reconstruido:     "$reconstructed"');
    print('Igual? ${testMessage == reconstructed}');
    
    assert(testMessage == reconstructed, 'El mensaje reconstruido no es igual al original');
    print('✓ Reconstrucción exacta del string original');
  }
}