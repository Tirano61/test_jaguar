# test_jaguar

Simulador BLE de balanzas e indicadores. La app se comporta como **periférico**
(servidor GATT): publica los servicios, notifica las mediciones y recibe
comandos. La app real se conecta como central, igual que lo haría contra el
equipo de verdad.

Sirve para probar la app sin tener la balanza físicamente, y para reproducir a
mano casos que en el campo son difíciles de provocar.

## Protocolos

Se elige desde el selector de arriba de la pantalla. Cambiar de protocolo
rearma el advertising con el perfil GATT que corresponda.

| Protocolo | Qué simula | Trama | Perfil GATT |
|---|---|---|---|
| **Jaguar BLE** | Balanza clásica. El peso lo genera el motor de simulación siguiendo un ciclo de carga y descarga | JSON de 7 claves | ABF0 / ABF6 |
| **Remoto ST407** | Indicador remoto. Se elige qué pantalla mostrar (códigos 100-110) y el simulador notifica su cadena | Cadena separada por coma, con cabecera binaria de 5 bytes | ABF3 |
| **Manual** | Balanza con los valores fijados a mano desde la UI. Los automatismos están apagados | JSON de 7 claves | ABF0 / ABF6 |
| **Hidráulico BLE** | Caja de manejo de tubo y guillotina, con descarga automática | JSON de 7 claves + `tomaFuerza`, `rpm`, `errorEcu`, `tubo` y `gillo` | ABF0 / ABF6 |
| **Remoto ST567** | Indicador remoto que responde a la app: listas de recetas, ingredientes y trabajos, carga y descarga animadas, mezcla y sincronización (pantallas 0-60) | Cadena separada por coma, con cabecera binaria de 5 bytes | ABF3 |

## Cómo se usa

1. Se aprieta **Iniciar** para activar el advertising BLE.
2. La app se conecta como central y se suscribe a las notificaciones.
3. Se elige el protocolo y se ajustan sus controles.
4. El simulador notifica una trama por segundo, y responde los comandos que le
   llegan por escritura.

## Comandos que acepta

Llegan por *characteristic write* desde la app conectada.

| Comando | Protocolo | Qué hace |
|---|---|---|
| `AT+RSTHOLD` | todos | Suelta el hold del modo Manual |
| `AT+TARA` | Manual | Alterna la tara |
| `AT+CERO` | todos | Pone el peso en cero |
| `AT+INICIO=<kg>,<kgTubo>,<kgPrecierre>,<modo>,<velocidad>` | Hidráulico | Arranca una descarga simulada |
| `AT+DETENER` / `AT+REANUDAR` | Hidráulico | Pausa y retoma la descarga |
| `AT+FINALIZAR` | Hidráulico | Corta la descarga sin guardar |
| `AT+MOVIMIENTO=<tipo>` | Hidráulico | Abre y cierra tubo o guillotina |
| `CTR,<comando>[,<arg>…]` | Remoto ST567 | Los comandos de la app remota (`sync`, `elegirReceta`, `select`, `acum`, `esc`…); ver [docs/protocolo-simulador-st567.md](docs/protocolo-simulador-st567.md) |

Y notifica `AT+GUARDAR` (o `AT+GUARDARDOS` en el modo dos descargas) cuando una
descarga hidráulica llega a su objetivo.

### Ciclo de descarga hidráulica

`AT+INICIO` no arranca la descarga en el acto: primero hay que abrir el tubo,
igual que en el equipo real.

1. Llega `AT+INICIO` → `tubo: 2` (abriendo) durante **6 s**, y la guillotina
   empieza a abrir hacia **25%**.
2. Tubo abierto → `tubo: 1`, y recién ahí el peso empieza a bajar.
3. Mientras dura la descarga, `gillo` salta cada **5 s** a un valor al azar
   entre **25 y 80** (la válvula regulando caudal).
4. Se alcanza el objetivo → se notifica `AT+GUARDAR` y el tubo pasa a
   `tubo: 3` (cerrando) durante **6 s**, con la guillotina cerrando a 0.
5. `tubo: 0` (cerrado) y la corrida termina.

`AT+MOVIMIENTO` mueve tubo y guillotina a mano, con un recorrido completo de
**15 s**; invertir la marcha a mitad de camino arranca desde donde quedó, no
desde el tope. Durante una corrida esos comandos se ignoran.

`AT+FINALIZAR` corta la corrida sin guardar: cierra la guillotina y **deja el
tubo donde está**.

El tubo y la guillotina se mueven con su propio reloj, que corre aunque la
simulación esté detenida: en el equipo real el hidráulico no depende de que la
balanza esté pesando. El peso, en cambio, sólo baja con **Iniciar** apretado.

Un comando que llega al protocolo equivocado se ignora y queda registrado en el
log, diciendo qué protocolo hay que seleccionar para que funcione.

## Cómo está organizado

```
lib/
  protocols/              un módulo por protocolo: su lógica, su estado,
    jaguar_ble/           su trama y su pantalla, todo junto
    st407_remote/
    manual/
    hidraulico_ble/
    st567/
    shared/               lo que comparten dos o más protocolos
    simulator_protocol.dart   el contrato
    protocol_registry.dart
  domain/                 motor de simulación, mediciones, estado BLE
  application/            orquestador y use cases
  infrastructure/         el servidor GATT real
  presentation/           el router de pantallas y los widgets compartidos
```

Para sumar un protocolo nuevo: [docs/como-agregar-un-protocolo.md](docs/como-agregar-un-protocolo.md).

Los documentos de protocolo de los indicadores están en `docs/`.

## Desarrollo

```
flutter analyze    # tiene que quedar en cero
flutter test
```
