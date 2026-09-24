# Cómo agregar un protocolo al simulador

Guía para sumar un indicador nuevo. Asume que ya tenés el documento de
protocolo (formato de trama y comandos) del indicador que querés simular.

## La idea

Cada protocolo vive en su propia carpeta bajo `lib/protocols/<nombre>/` y trae
todo lo suyo junto: la lógica, su estado, cómo arma la trama y su pantalla. Lo
que es de todos —el motor de simulación, la capa BLE, el log— vive fuera y no
hay que tocarlo.

El orquestador (`lib/application/services/simulator_orchestrator.dart`) es el
que coordina: escucha el tick del motor y los comandos que llegan por BLE, le
pregunta al protocolo activo qué mandar, y notifica. **No sabe nada de ningún
protocolo en particular** salvo por la tabla de despacho de comandos, que se
explica más abajo.

## Los tres pasos

### 1. Sumar el valor al enum

`lib/domain/value_objects/send_protocol.dart`:

```dart
enum SendProtocol {
  jaguarBle,
  st407Remote,
  manual,
  hidraulicoBle,
  st456web,       // <- nuevo
  ;

  String get label {
    switch (this) {
      // ...
      case SendProtocol.st456web:
        return 'Remoto ST456web';
    }
  }
}
```

El `switch` del label es exhaustivo, así que el compilador te avisa. El selector
de la UI se arma solo desde `SendProtocol.values`.

### 2. Crear la carpeta del protocolo

`lib/protocols/st456web/st456web_protocol.dart` implementando `SimulatorProtocol`:

```dart
class St456webProtocol implements SimulatorProtocol {
  @override
  SendProtocol get id => SendProtocol.st456web;

  @override
  BleUuids get bleUuids => BleConstants.remotoAbf3;

  @override
  PayloadFraming get framing => PayloadFraming.fiveByteHeader;

  @override
  String encodePayload(ScaleMeasurement measurement) => /* tu trama */;
}
```

El contrato tiene **cuatro miembros a propósito**. Los protocolos son
polimórficos en el formato de la trama y en el perfil BLE, y nada más: lo que
cada uno acepta como comando y lo que expone a la UI es tan distinto entre sí
que generalizarlo sería inventar una abstracción que nadie usa.

Todo lo demás que necesite tu protocolo es API propia del módulo, que llaman los
use cases directamente. Mirá `HydraulicProtocol` como ejemplo completo: tiene
`setTomaFuerza`, `applyInicio`, `advance`, `resetRunState`, etc. Dos
convenciones que conviene seguir:

* **Los métodos devuelven la línea de log en vez de escribirla.** Así el módulo
  no depende del orquestador y se prueba solo.
* **Devolver `null` cuando no cambió nada.** Es lo que le dice al orquestador
  que no reenvíe el payload.

Si tenés estado que la UI muestra, agregá un `st456web_state.dart` con una clase
inmutable, como `HydraulicState`. Esa misma clase la usan el DTO y el
`SimulatorViewState`, así que no hay que aplanarla dos veces.

**Regla de imports:** `*_protocol.dart`, `*_state.dart` y `*_payload.dart` no
importan Flutter. Sólo `*_view.dart` lo hace.

### 3. Registrarlo y darle pantalla

`lib/protocols/protocol_registry.dart`:

```dart
return ProtocolRegistry(<SimulatorProtocol>[
  // ...
  St456webProtocol(),
]);
```

`lib/presentation/pages/simulator_page.dart`:

```dart
case SendProtocol.st456web:
  return St456webView(controller: controller);
```

Ese `switch` es exhaustivo, así que **no compila** hasta que la vista exista. Y
`test/protocol_registry_test.dart` falla si el valor del enum no tiene
implementación registrada.

Para la vista, si tu protocolo muestra una balanza usá `SimulatorScaffold` y
pasale sólo lo tuyo en `sections` (mirá `St407RemoteView`). Si lo que hay que
ver es otra cosa, hacé una pantalla propia como `HydraulicView`.

## Si tu protocolo recibe comandos

Los comandos `AT+` se despachan en `_applyIncomingCommandIfNeeded`, dentro del
orquestador. **Eso es a propósito**, no una deuda pendiente: de los ocho
comandos actuales, tres (`AT+RSTHOLD`, `AT+TARA`, `AT+CERO`) tocan estado
compartido y tienen efectos cruzados entre protocolos. Moverlos a los módulos
los rompía en silencio.

Agregá tu familia de comandos ahí, delegando en tu módulo:

```dart
if (_isMiComando(normalizedCommand)) {
  if (_sendProtocol == SendProtocol.st456web) {
    await _applySt456webCommand(_st456web.applyMiComando());
  }
  return;
}
```

## Si tu protocolo usa comandos `CTR,<comando>`

Es la gramática de los indicadores remotos nuevos (ST567, ST456web). No pasa
por la cadena de `AT+`: esa normalización pasa todo a mayúsculas y borra los
espacios, y en los `CTR,` los argumentos (nombre de operario, lote) valen tal
cual llegan. El orquestador los intercepta **antes** de normalizar.

El ST567 ya lo resuelve y sirve de modelo:

* `St567Command.tryParse` (`lib/protocols/st567/st567_command.dart`) separa
  nombre y argumentos y deshace el escapado que aplica el datasource (`\s`
  por el espacio, `\r`, `\n`, `\`, `\xNN`). Si el ST456web necesita lo mismo,
  conviene moverlo a `protocols/shared/` en vez de copiarlo.
* `St567Protocol.apply` es la máquina de estados: recibe el comando, decide la
  pantalla que sigue según la pantalla vigente y devuelve la línea de log. Un
  comando que no corresponde a la pantalla se loguea y no cambia nada.
* `St567Protocol.advance` es el reloj: anima carga y descarga, corre la cuenta
  regresiva de la mezcla y cierra los popups. `encodePayload` es puro.

Sobre el ritmo de envío: los documentos piden repetir la pantalla cada
**200–500 ms**, pero el motor tiene un tick de **1 segundo**
(`SimulationTiming.oneMinutePerPhase`) y el ST567 lo usa tal cual. La app no
tiene timeout de datos, así que alcanza; si hiciera falta más fluidez, hay que
hacer el tick configurable por protocolo.

Ojo con los códigos de pantalla: los documentos reservan `100`-`110` para el
ST407 y `13` no se debe usar. El resto del rango `0`-`60` es de los remotos
nuevos.

## Cómo verificar

```
flutter analyze      # tiene que quedar en cero
flutter test
```

Para el protocolo nuevo escribí al menos:

* Un test unitario del módulo: se prueba solo, sin orquestador ni BLE. Mirá
  `test/hydraulic_protocol_test.dart` o `test/st407_protocol_test.dart`.
* Un test de integración con `Harness` (`test/support/orchestrator_harness.dart`)
  que fije la trama exacta que sale por notify. Mirá
  `test/st407_remote_protocol_test.dart`.

Si tu protocolo mete algo que dependa de la hora, inyectá el reloj como hace
`St407RemoteProtocol`: así el test puede clavar la cadena exacta en vez de
conformarse con un regex.

Y después probalo contra la app real conectada como central, que es para lo que
existe el simulador.
