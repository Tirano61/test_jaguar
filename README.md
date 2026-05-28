# test_jaguar

Aplicacion Flutter para simular una balanza BLE y probar la comunicacion con una central.

## Formas de conexion

### 1. Jaguar BLE
La app se comporta como un periferico BLE, publica los servicios GATT y envia las mediciones por notificaciones.
En este modo, los valores se generan automaticamente por la simulacion y se mandan en formato JSON.

### 2. Manual
La conexion BLE se mantiene igual, pero los datos enviados se controlan desde la interfaz.
En este modo, puedes definir manualmente valores como peso, tara, humedad y estado para probar casos especificos.

## Funcionamiento

1. Se inicia la simulacion para activar el advertising BLE.
2. Una central BLE se conecta al periferico.
3. Se elige el modo Jaguar BLE o Manual.
4. La app envia el JSON correspondiente segun el modo seleccionado.
