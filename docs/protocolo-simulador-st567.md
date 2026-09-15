# Protocolo Remoto BLE – Indicador **ST567** (guía para el simulador)

**Origen de la información:** análisis del código de la app `remoto_567_flutter` versión **5.0.0-beta+44**, rama `RemotoBLE`
(`lib/provider/conexion/remoto_common_ble.dart`, `lib/provider/protocolos/st456_coma_parser.dart`,
`lib/provider/stream_provider_remoto.dart`, `lib/models/**`, `lib/pages/**`, `lib/pages/remoto.dart`).
**Fecha:** 14/09/2026.

> Todo lo que dice este documento sobre **formato de tramas, campos y comandos** sale directamente del código de la app y es exacto.
> La **secuencia entre pantallas** (qué pantalla responde el indicador a cada comando) la decide el firmware del ST567, que no está en este
> repositorio. Los flujos de la sección 8 son los que la app asume por el diseño de sus botones y por el historial del proyecto; el
> simulador puede respetarlos o ajustarlos al comportamiento real del indicador.

---

## Índice

1. [Alcance](#1-alcance)
2. [Capa BLE (GATT)](#2-capa-ble-gatt)
3. [Trama indicador → app](#3-trama-indicador--app)
4. [Comandos app → indicador](#4-comandos-app--indicador)
5. [Comportamiento general de la app](#5-comportamiento-general-de-la-app)
6. [Tabla resumen de pantallas](#6-tabla-resumen-de-pantallas)
7. [Detalle de cada pantalla](#7-detalle-de-cada-pantalla)
8. [Flujos completos sugeridos](#8-flujos-completos-sugeridos)
9. [Checklist y errores comunes](#9-checklist-y-errores-comunes)
10. [Apéndice](#10-apéndice)

---

## 1. Alcance

Pantallas que la app usa con el **ST567**:

| Grupo | IDs |
|---|---|
| Peso / operación | `0`, `2`, `4`, `6`, `38`, `39` |
| Listas / selección | `30`, `60`, `32`, `34`, `42` |
| Detalles | `31`, `37` |
| Diálogos con botones | `33`, `35`, `36`, `40`, `41` |
| Popups sin botones | `16`, `17`, `20`, `43`, `44`, `45` |
| Sincronización | `19`, `35`, `36` |

Pantallas que **no** son del ST567 pero la app también procesa (pertenecen al ST456web, ver `protocolo-simulador-st456web.md`):
`1`, `3`, `8`, `9`, `10`, `11`, `12`, `14`, `15`, `18`. Si el ST567 las envía la app las muestra igual, pero el flujo ST567 usa `38`/`39`/`34`/`30`/`60` en su lugar.

Pantallas reservadas que el simulador **no debe usar**: `13` (ignorada, muestra pantalla principal) y `100`–`108` (indicador ST407).

---

## 2. Capa BLE (GATT)

| Elemento | UUID | Propiedades | Sentido |
|---|---|---|---|
| Servicio | `0000ABF3-0000-1000-8000-00805F9B34FB` | – | – |
| Característica **Pantallas** | `0000ABF5-0000-1000-8000-00805F9B34FB` | NOTIFY (+ descriptor CCCD `00002902-…`) | indicador → app |
| Característica **Comandos** | `0000ABF4-0000-1000-8000-00805F9B34FB` | WRITE WITHOUT RESPONSE | app → indicador |

Comportamiento de la app al conectar:

1. Escanea **todos** los dispositivos BLE con nombre no vacío y los lista; el usuario elige uno. No filtra por nombre ni por servicio en el escaneo.
2. Intenta `connectToAdvertisingDevice(withServices: [ABF3])` con un pre-scan de 4 s. Si falla, hace `connectToDevice` directo (fallback). Conviene que el simulador **anuncie el servicio ABF3 en el advertising**.
3. Pide **MTU 512**. Si el simulador no lo soporta, simplemente debe fragmentar las tramas en más partes (sección 3.2).
4. Se suscribe a notificaciones de `ABF5` y marca "conectado". **No envía ningún comando inicial**: el simulador debe empezar a notificar la pantalla `0` por su cuenta.
5. Guarda el dispositivo para autoconexión (si el switch *AutoConect* está activo, reintenta cada 20 s tras una desconexión no manual).

---

## 3. Trama indicador → app

### 3.1 Estructura de cada notificación

```
byte 0      idPaquete    : 0-255. Identificador de la trama lógica. Incrementar por cada trama (con wrap).
byte 1      totalPartes  : cantidad de notificaciones que componen la trama (1 = trama completa en una notificación).
byte 2      numParte     : número de esta parte, base 1 (1..totalPartes).
byte 3-4    longitud     : uint16 big-endian = cantidad de bytes de payload de la notificación (ver validación).
byte 5..n   payload      : texto ASCII/Latin-1 separado por comas.
```

Payload lógico completo:

```
<idPantalla>,<campo1>,<campo2>,...,<campoN>\r\n
```

Reglas de parseo (tal como las aplica la app):

* Se quitan los **2 últimos caracteres** (`\r\n`), se hace `trim()` a la cadena completa y `split(',')`.
* `totalPartes == 1`: la notificación se **descarta** si `longitud != bytes de payload` (contando el `\r\n`).
* `totalPartes > 1`: las partes se guardan por `idPaquete` + `numParte`; cuando están las `totalPartes` se concatenan en orden `1..N` y se parsea el conjunto. En multiparte la app **no valida** el campo `longitud` (se recomienda poner la longitud de la parte). Sólo la **última parte** termina en `\r\n`. La cabecera de 5 bytes se repite en **cada** parte con el mismo `idPaquete`.
* Si se pierde una parte, la trama queda incompleta hasta que llegue otra trama con el mismo `idPaquete` completa.
* Codificación: cada byte se convierte a un carácter (**Latin-1**). Usar ASCII o ISO-8859-1. UTF-8 multibyte (p. ej. `ñ` = `C3 B1`) se muestra mal.

### 3.2 Ejemplo de trama en una parte (pantalla principal)

Payload: `0,1250,1,kg,,14/09/2026 10:32,0\r\n` → 33 bytes (0x0021).

```
01 01 01 00 21 | 30 2C 31 32 35 30 2C 31 2C 6B 67 2C 2C 31 34 2F 30 39 2F 32 30 32 36 20 31 30 3A 33 32 2C 30 0D 0A
^  ^  ^  ^^^^^   "0,1250,1,kg,,14/09/2026 10:32,0\r\n"
|  |  |  longitud = 33
|  |  numParte = 1
|  totalPartes = 1
idPaquete = 1
```

### 3.3 Ejemplo de trama multiparte

Una trama de pantalla `38` (carga por receta con lista de ingredientes) de, por ejemplo, 250 bytes, enviada en partes de 100 bytes con MTU chico:

```
Parte 1:  07 03 01 00 64 | <100 bytes de payload>
Parte 2:  07 03 02 00 64 | <100 bytes de payload>
Parte 3:  07 03 03 00 32 | <50 bytes de payload, terminando en 0D 0A>
```

La app concatena las tres partes, quita `\r\n`, y parsea `38,....`.

### 3.4 Reglas para los campos

| Regla | Motivo en el código |
|---|---|
| Ningún campo puede contener `,` | `split(',')` sin escape ni comillas. |
| No poner espacios después de las comas (`1, 200` ✗) | Los campos no se recortan individualmente: un flag `" 1"` no es igual a `"1"` (lock, level, sirena, estado, estabilidad, completo…), los nombres no coinciden con `ingredienteActual`/`loteActual` y los textos se muestran con el espacio. |
| Los campos marcados **int** deben ser enteros (`250`, no `250.0` ni `250,5`) | Se usa `int.tryParse(...)!`; un valor no entero rompe el parseo de toda la trama y la pantalla no se actualiza. |
| Los campos "0/1" son texto: se compara con `"1"` o con `"0"` | Cualquier otro valor cae en la rama "distinto de …" indicada en cada tabla. |
| Los valores se muestran tal cual llegan | No hay formateo; `1250`, `1250.5` o `01250` se muestran así. |
| Campos que faltan al final | La mayoría de los modelos los toma como vacío (`''`); los obligatorios están marcados en cada pantalla. |

---

## 4. Comandos app → indicador

Formato: `CTR,<comando>[,<arg>...]\r\n`, en ASCII, escrito con *write without response* en `ABF4`. Un comando por escritura.

| Comando (bytes exactos) | Desde qué pantalla / acción | Respuesta que espera la app |
|---|---|---|
| `CTR,sync\r\n` | `0`, botón *sincronizar* | `19` (progreso, opcional) y luego `36` (ok) o `35` (falla) |
| `CTR,levelLock\r\n` | `0`, botón *LevelLock* | `0` con campo `levelLock` = `1` (líneas rojas) / `0` |
| `CTR,cero\r\n` | `0`, pulsación **larga** del botón cero | `0` con peso en cero |
| `CTR,cargaManual\r\n` | `0` → menú → *Carga Manual* | `32` (elegir ingrediente) o directamente `2` |
| `CTR,elegirReceta\r\n` | `0` → menú → *Carga Por Receta* | `60` (firmware ≥ 1.36.3) o `30` |
| `CTR,descargaManual,<lote>,<kg>\r\n` | `0` → menú → *Descarga Manual* (diálogo lote+cantidad); también desde `33` | `4` |
| `CTR,elegirTrabajo\r\n` | `0` → menú → *Iniciar Trabajo* | `34` (lista) o `20` (no hay trabajos) |
| `CTR,cambiarOperario\r\n` | `0` → menú → *Seleccionar Operario*; botón *Operario* en `2`, `38` | `42` |
| `CTR,esc\r\n` | Botón *ESC* de casi todas las pantallas; botón OK de `35`/`36`; al validar PIN en `42` | Volver a la pantalla anterior (normalmente `0`) |
| `CTR,nextPage\r\n` / `CTR,prevPage\r\n` | Botones *next*/*prev* en `30`, `60`, `32`, `34` | La misma pantalla con la página siguiente/anterior |
| `CTR,detail,<indice>\r\n` | Botón *Detalles* en `30`, `60` (→ detalle de receta) y `34` (→ detalle de trabajo) | `37` desde recetas, `31` desde trabajos |
| `CTR,select,<indice>\r\n` | `34`, botón *start* con trabajo seleccionado | `41` (¿reanudar?) o directamente la pantalla de trabajo (`38`/`39`) |
| `CTR,select,<indice>,<kg>\r\n` | `30`/`60` (receta + cantidad) y `32` (ingrediente + cantidad) | `38` (desde receta) / `2` (desde ingrediente) |
| `CTR,selectIngrediente\r\n` | `2`, botón *ingrediente* | `32` |
| `CTR,acum,<operario>\r\n` | Botón *ACUM* en `2`, `38`, `39` (tras confirmar diálogo). `<operario>` = nombre del operario elegido en la tablet; puede ir **vacío** (`CTR,acum,\r\n`) | Misma pantalla con el siguiente ingrediente/lote, o `6`/`0`/`40` |
| `CTR,acum\r\n` | Botón *ACUM* en `4` (descarga manual, sin operario) | `33` (pedir lote y cantidad para seguir) o `0` |
| `CTR,lock\r\n` / `CTR,level\r\n` | Botones *lock*/*level* en `2`, `4`, `38`, `39` | Misma pantalla con `lock`/`level` en `1`/`0` |
| `CTR,rotate\r\n` | Botón *rotate* en `38`, `39` | Sin cambio de pantalla (acción del mixer) |
| `CTR,boton1\r\n` / `CTR,boton2\r\n` | Diálogos `40` (CONTINUAR / NUEVA) y `41` (CONTINUAR / REINICIAR) | La pantalla que corresponda (`38`, `39`, `0`…) |

Comandos definidos en la app pero **no usados** por ninguna pantalla (no hace falta implementarlos): `CTR,loginOperario,<usuario>,<pass>`, `CTR,elegirAutonomo`, `CTR,elegirGuia`, `CTR,acum,<kg>` (carga manual ST407), `CTR,cargaManual,<kg>` (ST407), `CTR,acum,<lote>,<kg>`.

---

## 5. Comportamiento general de la app

* **Cada trama recibida** hace dos cosas: `pantalla = campo[0]` (si cambia, la app navega a esa pantalla) y `conexión = 1`.
* **No hay timeout de datos.** La app sólo marca "desconectado" cuando se cae el enlace BLE (el timer de 5 s está deshabilitado en el código). Aun así, para que el peso se vea "vivo" el simulador debe **repetir la pantalla actual periódicamente** (200–500 ms es razonable en pantallas de peso; en listas alcanza con enviarlas una vez y al cambiar).
* ID de pantalla desconocido → se muestra la pantalla principal **sin datos** (rayas). Evitarlo.
* Los **popups sin botones** (`16`, `17`, `20`, `43`, `44`, `45`) no tienen ESC: el simulador debe sacar a la app enviando otra pantalla (normalmente `0`) cuando corresponda.
* Al recibir cualquier pantalla ≠ `0` mientras está abierto el **menú principal**, la app lo cierra sola (útil con `45` "indicador ocupado").
* Repetir una trama idéntica es inofensivo: las listas comparan el JSON del modelo y no se redibujan si no cambió.
* El **operario** que muestra la app es local de la tablet (se elige en `42` y se guarda en la tablet). El campo *operario* de la pantalla `0` se parsea pero **no se muestra**. El nombre se envía en `CTR,acum,<operario>`.
* El botón **Desconectar** de la barra superior corta el BLE desde la app (no envía comando).

---

## 6. Tabla resumen de pantallas

| ID | Nombre en la app | Payload (después del ID) | Botones → comandos |
|---|---|---|---|
| `0` | Pantalla principal | `peso,estabilidad,unidad,operario,fecha,levelLock` | levelLock, sync, menú, bluetooth, cero(long) |
| `2` | Carga manual | `total,parcial*,kgACargar*,nroIngrediente,ingrediente,lock,level,sirena` | esc, level, acum(op), lock, selectIngrediente |
| `4` | Descarga manual | `total,parcial,kgADescargar,lote,lock,level,sirena` | esc, level, acum, lock |
| `6` | Mezclando | `minutos,segundos` | esc |
| `16` | Popup "Primero debe seleccionar un operario en el indicador" | – | (ninguno) |
| `17` | Popup "Ya realizó la carga, proceda a la descarga" | – | (ninguno) |
| `19` | Sincronizando (porcentaje) | `porcentaje` | esc |
| `20` | Popup "No hay trabajos cargados en el indicador" | – | (ninguno) |
| `30` | Elegir receta (sin preset) | `n,(indice,nombre)*n` | esc, prevPage, start→select, nextPage, detail |
| `31` | Detalle de trabajo | `nombreTrabajo,nombreReceta,bachada,porcentaje,mezclaSeg,nIng,nLotes,viajes,(ing,kg)*nIng,(lote,kg)*nLotes` | esc |
| `32` | Elegir ingrediente | `n,(indice,nombre)*n` | esc, prevPage, start→select, nextPage |
| `33` | Diálogo lote + cantidad (descarga manual) | – | Aceptar→descargaManual, esc |
| `34` | Trabajos | `n,(indice,nombre,completo)*n` (n ≤ 15) | esc, prevPage, start→select, nextPage, detail |
| `35` | Diálogo "La sincronización ha fallado" | – | OK→esc, esc |
| `36` | Diálogo "La sincronización ha sido exitosa" | – | OK→esc, esc |
| `37` | Detalle de receta | `nombre,mezclaSeg,tipo,n,(nombre,cantidad,tipoAviso,aviso,mezclaSeg)*n` | esc |
| `38` | Carga por receta (con lista) | `total,parcial*,kgACargar*,ingredienteActual,lock,level,sirena,n,(nombre,cantidad,tipoAviso,aviso,mezclaSeg,estado)*n` | esc, level, acum(op), lock, rotate, operario |
| `39` | Descarga por guía (con lotes) | `total,parcial*,kgADescargar*,loteActual,lock,level,sirena,n,(nombre,parcial,total)*n` | esc, level, acum(op), lock, rotate |
| `40` | Diálogo "ADVERTENCIA – Debe preparar más carga" | – | CONTINUAR→boton1, NUEVA→boton2, esc |
| `41` | Diálogo "TRABAJOS – ¿Reanudar trabajo?" | – | CONTINUAR→boton1, REINICIAR→boton2, esc |
| `42` | Cambio de operario (login) | `n,(nombre,password)*n` | esc, start→PIN local→esc |
| `43` | Popup "Operario No encontrado !!!" | – | (ninguno) |
| `44` | Popup "Clave incorrecta !!!" | – | (ninguno) |
| `45` | Popup "Indicador ocupado, salga de la pantalla actual del indicador" | – | Desconectar (BLE) |
| `60` | Elegir receta con preset (firmware ≥ 1.36.3) | `n,(indice,nombre,cantidadPreset)*n` (n ≤ 30) | esc, prevPage, start→select, nextPage, detail |

`*` = entero obligatorio.

---

## 7. Detalle de cada pantalla

Convenciones de las tablas: **Índice** es la posición en el `split(',')` (el índice 0 es siempre el ID de pantalla). **Tipo**: `texto`, `int` (entero obligatorio), `0/1` (texto comparado con `"0"`/`"1"`).

### 7.1 Pantalla `0` – Principal

Modelo: `PantallaPrincipalModel.fromParceo` · Vista: `principal_remoto_page.dart`, `recuadro_peso.dart`.

| Índice | Campo | Tipo | Cómo lo usa la app |
|---|---|---|---|
| 1 | peso | texto | Número grande central. Si la app está desconectada muestra `- - - -`. |
| 2 | estabilidad | 0/1 | `"1"` → punto **verde** (estable); cualquier otro valor → punto **rojo**. |
| 3 | unidad | texto | Se parsea pero **no se muestra** (la app escribe "Kg" fijo). Enviar `kg`. |
| 4 | operario | texto | Se parsea pero **no se muestra** (la app muestra el operario local de la tablet). Puede ir vacío. |
| 5 | fecha | texto | Se muestra como `Fecha: <valor>`. Formato libre. |
| 6 | levelLock | 0/1 | `"0"` → líneas azules; cualquier otro valor → líneas **rojas** (LevelLock activo). Si falta se asume `0`. |

Mínimo: sólo el ID; los campos faltantes quedan vacíos.

```
0,1250,1,kg,,14/09/2026 10:32,0\r\n      peso estable, LevelLock apagado
0,1248,0,kg,,14/09/2026 10:32,0\r\n      peso inestable
0,1250,1,kg,,14/09/2026 10:32,1\r\n      LevelLock activo (líneas rojas)
0,0,1,kg,,14/09/2026 10:33,0\r\n         después de CTR,cero
```

Comandos que puede recibir el simulador estando en `0`: `CTR,levelLock`, `CTR,sync`, `CTR,cero`, y desde el menú: `CTR,cargaManual`, `CTR,elegirReceta`, `CTR,descargaManual,<lote>,<kg>`, `CTR,elegirTrabajo`, `CTR,cambiarOperario`.

### 7.2 Pantalla `2` – Carga manual

Modelo: `PantallaCargaManualModel.fromParceo` · Vista: `carga_manual_page.dart`.

| Índice | Campo | Tipo | Cómo lo usa la app |
|---|---|---|---|
| 1 | totalCargado | texto | Fila `Total : <valor>`. |
| 2 | parcialCargado | **int** | Fila `Parcial : <valor>` y barra de progreso. |
| 3 | kgACargar | **int** | Fila `Kg a Cargar: <valor>` y barra de progreso. |
| 4 | nroIngrediente | texto | Fila `Nº Ingrediente: <valor>`. |
| 5 | ingrediente | texto | Fila `Nombre: <valor>`. |
| 6 | lock | 0/1 | `"1"` → fondo rojo translúcido detrás del peso grande. |
| 7 | level | 0/1 | `"1"` → fondo azul translúcido en la franja del peso. |
| 8 | sirena | 0/1 | `"1"` → suena la sirena en loop; `"0"` → se apaga. Si falta se asume `0`. |

Derivados: **peso grande** = `kgACargar − parcialCargado`; **progreso** = `parcialCargado / kgACargar` (se muestra `%` y `parcial / kgACargar kg`).
Obligatorio: al menos 4 campos con `[2]` y `[3]` enteros.

```
2,800,120,500,3,Soja,0,0,0\r\n        peso grande 380, progreso 24 %
2,800,480,500,3,Soja,0,0,1\r\n        faltan 20 kg, sirena de aviso anticipado
2,1300,0,0,,,0,0,0\r\n                sin ingrediente elegido (peso grande 0)
```

Botones → comandos: ESC (diálogo "¿Está seguro que desea salir?") → `CTR,esc`; level → `CTR,level`; ACUM (diálogo "¿pasar el ingrediente?") → `CTR,acum,<operario>`; lock → `CTR,lock`; ingrediente → `CTR,selectIngrediente` (esperar `32`); botón *Operario* de la barra → `CTR,cambiarOperario` (esperar `42`).

### 7.3 Pantalla `4` – Descarga manual

Modelo: `PantallaDescargaManualModel.fromParceo` · Vista: `descarga_manual_page.dart`, `recuadro_peso_carga_descarga.dart`.

| Índice | Campo | Tipo | Cómo lo usa la app |
|---|---|---|---|
| 1 | totalCargado | texto | Fila `Total : <valor>`. |
| 2 | parcialCargado | int (tolerante: si falta o no es entero se toma 0) | Fila `Parcial : <valor>` y barra. |
| 3 | kgADescargar | int (tolerante) | Fila `Kg a Descargar: <valor>` y barra. |
| 4 | lote | texto | Fila `Descargando Lote: <valor>`. Si falta muestra ` -`. |
| 5 | lock | 0/1 | `"1"` → fondo rojo detrás del peso. |
| 6 | level | 0/1 | `"1"` → fondo azul. |
| 7 | sirena | 0/1 | `"1"` sirena en loop, `"0"` apaga. |

Derivados: **peso grande** = `kgADescargar − parcialCargado`; si `kgADescargar = 0` se muestra `|parcialCargado|` (descarga sin objetivo, "descarga con kg en 0").

```
4,2600,300,1000,L01,0,0,0\r\n       faltan 700 kg del lote L01
4,2600,300,0,L01,0,0,0\r\n          sin objetivo: muestra 300 (lo descargado)
```

Botones → comandos: ESC → `CTR,esc`; level → `CTR,level`; ACUM (diálogo) → `CTR,acum` (**sin operario**; la app espera que el indicador pida lote y cantidad con `33`); lock → `CTR,lock`. El quinto botón está vacío.

### 7.4 Pantalla `6` – Mezclando

Modelo: campos sueltos en `StreamProviderRemoto` · Vista: `mezcla_page.dart`.

| Índice | Campo | Tipo | Cómo lo usa la app |
|---|---|---|---|
| 1 | minutos | texto | Se muestra `<minutos>:` en grande. |
| 2 | segundos | texto | Se rellena a 2 dígitos a la izquierda (`5` → `05`). |

Obligatorio: al menos 3 campos (si no, la trama se ignora). Repetir cada segundo para la cuenta regresiva.

```
6,2,5\r\n      →  2:05
6,0,59\r\n     →  0:59
```

Botón: ESC → `CTR,esc`.

### 7.5 Pantalla `19` – Sincronizando (porcentaje)

Modelo: `ActualizandoIndicador.fromParseo` · Vista: `dialogo_actualizacion_porcentaje.dart`.

| Índice | Campo | Tipo | Cómo lo usa la app |
|---|---|---|---|
| 1 | porcentaje | texto | Se muestra `SINCRONIZANDO : <valor>` (la app no agrega `%`). |

```
19,0\r\n
19,45\r\n
19,100\r\n
```

Botón: ESC → `CTR,esc`. Al terminar, el indicador debe enviar `36` (ok) o `35` (falla).

### 7.6 Pantallas `30` y `60` – Elegir receta

Modelos: `ElegirReceta567Model` (`30`) y `ElegirReceta567CargaModel` (`60`) · Vistas: `elegir_receta567.dart`, `elegir_receta567_carga.dart`.

**`30`** (sin preset):

| Índice | Campo | Tipo | Cómo lo usa la app |
|---|---|---|---|
| 1 | totalRecetas | int | Cantidad de pares que siguen. |
| 2 + 2k | indice | texto | Se muestra `Receta : <indice> - <nombre>` y es el valor que se envía en `select`/`detail`. |
| 3 + 2k | nombre | texto | |

**`60`** (con preset, ST567 ≥ 1.36.3):

| Índice | Campo | Tipo | Cómo lo usa la app |
|---|---|---|---|
| 1 | totalRecetas | int | Cantidad de ternas (la app procesa como máximo **30**). |
| 2 + 3k | indice | texto | Idem `30`. |
| 3 + 3k | nombre | texto | |
| 4 + 3k | cantidadPreset | texto | Se muestra `Preset: <valor>` y precarga el campo *Cantidad* del diálogo de inicio. |

Si `totalRecetas` es mayor que los pares/ternas realmente enviados, la app muestra sólo los que llegaron completos.

```
30,3,1,Vacas Lecheras,2,Terneros,3,Engorde\r\n
60,3,1,Vacas Lecheras,1500,2,Terneros,800,3,Engorde,2000\r\n
```

Botones → comandos: ESC → `CTR,esc`; prev → `CTR,prevPage`; next → `CTR,nextPage`; *Detalles* de una tarjeta → `CTR,detail,<indice>` (esperar `37`); START → abre diálogo "INICIAR CARGA" con *Cantidad* → `CTR,select,<indice>,<cantidad>` (esperar `38`).
Diferencias: en `30` START funciona aunque no haya selección (usa `indice = "1"`); en `60` START requiere haber tocado una receta.

### 7.7 Pantalla `31` – Detalle de trabajo

Modelo: `DetalleTrabajo567Model.fromParseo` · Vista: `detalles_trabajos_567_page.dart`.

| Índice | Campo | Tipo | Cómo lo usa la app |
|---|---|---|---|
| 1 | nombreTrabajo | texto | Título del panel derecho. |
| 2 | nombreReceta | texto | Panel izquierdo `Nombre : <valor>`. |
| 3 | bachada | texto | Panel derecho `Bachada : <valor>`. |
| 4 | porcentaje | texto | Panel derecho `Porc. : <valor> %`. |
| 5 | minutosMezcla | texto | Panel izquierdo `Mezcla: <valor> seg`. |
| 6 | cantIngredientes | int | Cantidad de pares (nombre, kg) que siguen. |
| 7 | cantLotes | int | Cantidad de pares (lote, kg) que siguen después de los ingredientes. |
| 8 | viajes | texto | Panel derecho `Viajes : <valor>`. |
| 9 … | ingredientes | (texto, texto) × cantIngredientes | Tarjetas `Ingrediente : <nombre>` — `<kg> kg`. |
| … | lotes | (texto, texto) × cantLotes | Tarjetas `Lote : <nombre>` — `<kg> kg`. |

Obligatorio: al menos 9 campos.

```
31,Trabajo Manana,Vacas Lecheras,2,50,120,3,2,4,Maiz,600,Soja,300,Heno,900,Corral 1,1000,Corral 2,800\r\n
```

Botón: ESC → `CTR,esc` (volver a `34`).

### 7.8 Pantalla `32` – Elegir ingrediente (carga manual)

Modelo: `ElegirIngrediente567Model.fromParseo` · Vista: `elegir_ingrediente_567.dart`.

| Índice | Campo | Tipo | Cómo lo usa la app |
|---|---|---|---|
| 1 | totalIngredientes | int | Cantidad de pares que siguen. |
| 2 + 2k | indice | texto | Se muestra `Ingrediente : <indice> - <nombre>`; es lo que se envía en `select`. |
| 3 + 2k | nombre | texto | |

```
32,4,1,Maiz,2,Soja,3,Heno,4,Nucleo\r\n
```

Botones → comandos: ESC → `CTR,esc`; prev → `CTR,prevPage`; next → `CTR,nextPage`; START (requiere selección) → diálogo *Cantidad* → `CTR,select,<indice>,<cantidad>` (esperar `2`).

### 7.9 Pantalla `33` – Diálogo lote + cantidad (descarga manual)

Sin campos: `33\r\n`. Vista: `dialogo_descarga_manual_567.dart`.
Muestra "INICIAR DESCARGA MANUAL" con dos entradas: **Lote** (máx. 3 caracteres alfanuméricos) y **Cantidad** (máx. 5 dígitos).

Botones → comandos: Aceptar (ambos campos no vacíos) → `CTR,descargaManual,<lote>,<kg>` (esperar `4`); ESC → `CTR,esc`.

### 7.10 Pantalla `34` – Trabajos

Modelo: `PantallaTrabajos567Model.fromParceo` · Vista: `trabajos_page567.dart`.

| Índice | Campo | Tipo | Cómo lo usa la app |
|---|---|---|---|
| 1 | tTrabajos | int | Cantidad de trabajos de esta página. Se usa como cantidad de filas: **máximo 15**; más de 15 rompe la lista. |
| 2 + 3k | indice | texto | `Trabajo : <indice> - <nombre>`; es lo que se envía en `select`/`detail`. |
| 3 + 3k | nombre | texto | |
| 4 + 3k | completo | 0/1 | `"1"` → tilde verde (trabajo realizado). |

La app siempre reserva 15 posiciones internas; las que no lleguen quedan vacías. Paginar con `nextPage`/`prevPage` si hay más de 15.

```
34,3,1,Trabajo Manana,1,2,Trabajo Tarde,0,3,Trabajo Noche,0\r\n
```

Botones → comandos: ESC → `CTR,esc`; prev → `CTR,prevPage`; next → `CTR,nextPage`; *Detalles* → `CTR,detail,<indice>` (esperar `31`); START → `CTR,select,<indice>` (si no eligió nada envía `1`).

### 7.11 Pantallas `35` y `36` – Resultado de sincronización

Sin campos: `35\r\n` (falló) / `36\r\n` (exitosa). Vista: `dialogo_sincronizacion.dart`.
Botones: OK → `CTR,esc`; ESC → `CTR,esc`. Después del `esc` el indicador debe enviar `0`.

### 7.12 Pantalla `37` – Detalle de receta

Modelo: `DetalleReceta567Model.fromParseo` · Vista: `receta_567_widget.dart`.

| Índice | Campo | Tipo | Cómo lo usa la app |
|---|---|---|---|
| 1 | nombreReceta | texto | `Nombre: <valor>`. |
| 2 | mezcla | texto | `Mezcla: <valor> seg`. |
| 3 | tipo | 0/1 | `"0"` → `Tipo : KG`; cualquier otro → `Tipo : Cabezas`. |
| 4 | totalIngredientes | int | Cantidad de quintetos que siguen. |
| 5 + 5k | nombre | texto | Título de la tarjeta. |
| 6 + 5k | cantidad | texto | `Cant.: <valor> kg`. |
| 7 + 5k | tipoAviso | 0/1 | `"0"` → el aviso se muestra en `kg`; otro → en `%`. |
| 8 + 5k | aviso | texto | `Aviso : <valor> kg|%`. |
| 9 + 5k | mezcla | texto | `Mezcla : <valor> seg`. |

**Cada ingrediente debe traer los 5 campos**; un ingrediente truncado rompe el parseo.

```
37,Vacas Lecheras,120,0,3,Maiz,600,1,10,30,Soja,300,0,20,30,Heno,900,1,15,60\r\n
```

Botón: ESC → `CTR,esc` (volver a `30`/`60`).

### 7.13 Pantalla `38` – Carga por receta (con lista de ingredientes)

Modelo: `PantallaCargaReceta567Model.fromParseo` · Vista: `carga_por_receta_567_page.dart`.

| Índice | Campo | Tipo | Cómo lo usa la app |
|---|---|---|---|
| 1 | total | texto | Fila `Total : <valor>`. |
| 2 | parcial | **int** | Fila `Parcial : <valor>`, barra de progreso. |
| 3 | kgACargar | **int** | Fila `Kg a Cargar: <valor>`, barra. |
| 4 | ingredienteActual | texto | Fila `Cargando : <valor>`. La tarjeta cuyo `nombre` es **exactamente igual** se resalta (borde azul). |
| 5 | lock | 0/1 | `"1"` → fondo rojo detrás del peso. |
| 6 | level | 0/1 | `"1"` → fondo azul. |
| 7 | sirena | 0/1 | `"1"` sirena en loop, `"0"` apaga. |
| 8 | totalIngredientes | int | Cantidad de sextetos que siguen. |
| 9 + 6k | nombre | texto | Nombre en la tarjeta. |
| 10 + 6k | cantidad | texto | `<valor>kg`. |
| 11 + 6k | tipoAviso | texto | Se parsea pero **no se muestra** en esta pantalla. |
| 12 + 6k | aviso | texto | `Ant.: <valor>%` (la app siempre escribe `%`). |
| 13 + 6k | mezcla | texto | `Mezcla: <valor>seg`. |
| 14 + 6k | estado | 0/1 | `"0"` → círculo numerado claro (pendiente); cualquier otro → círculo azul relleno (ya cargado / en curso). |

Derivados: **peso grande** = `kgACargar − parcial`; progreso = `parcial / kgACargar`.
Obligatorio: al menos 9 campos, `[2]` y `[3]` enteros, y **6 campos por ingrediente**.

```
Inicio de receta (cargando Maiz, 250 de 600):
38,250,250,600,Maiz,0,0,0,3,Maiz,600,1,10,30,0,Soja,300,1,10,30,0,Heno,600,1,10,60,0\r\n

Aviso anticipado (faltan 60 kg, sirena):
38,540,540,600,Maiz,0,0,1,3,Maiz,600,1,10,30,0,Soja,300,1,10,30,0,Heno,600,1,10,60,0\r\n

Después de CTR,acum (Maiz cargado, empieza Soja):
38,600,0,300,Soja,0,0,0,3,Maiz,600,1,10,30,1,Soja,300,1,10,30,0,Heno,600,1,10,60,0\r\n
```

Botones → comandos: ESC (diálogo) → `CTR,esc`; level → `CTR,level`; ACUM (diálogo "¿pasar el ingrediente?") → `CTR,acum,<operario>`; lock → `CTR,lock`; rotate → `CTR,rotate`; botón *Operario* de la barra → `CTR,cambiarOperario`.

### 7.14 Pantalla `39` – Descarga por guía (con lista de lotes)

Modelo: `PantallaDescargaGuia567Model.fromParseo` · Vista: `descarga_por_guia_567.dart` y widgets en `descarga_guia_567/widgets/`.

| Índice | Campo | Tipo | Cómo lo usa la app |
|---|---|---|---|
| 1 | total | texto | Fila `Total : <valor>`. |
| 2 | parcial | **int** | Fila `Parcial : <valor>`, barra principal. |
| 3 | kgADescargar | **int** | Fila `Kg a Cargar: <valor>` (etiqueta reutilizada), barra principal. |
| 4 | loteActual | texto | Fila `Descargando : <valor>`. La tarjeta cuyo `nombre` es **exactamente igual** se resalta (borde naranja, ícono de check). |
| 5 | lock | 0/1 | `"1"` → fondo rojo. |
| 6 | level | 0/1 | `"1"` → fondo azul. |
| 7 | sirena | 0/1 | `"1"` sirena en loop, `"0"` apaga. |
| 8 | totalLotes | int | Cantidad de ternas que siguen. |
| 9 + 3k | nombre | texto | Nombre del lote. |
| 10 + 3k | parcial | número (texto) | `Desc. : <valor> kg`. Se usa `double.tryParse` para la barra (acepta decimales). |
| 11 + 3k | total | número (texto) | `Total: <valor> kg`. Barra = parcial/total; debajo `xx.x %` y `Faltan: <total−parcial> kg` (o `Sobran: … kg` en rojo si parcial > total). Lote con parcial ≥ total y no actual → ícono de caja (completo). |

Derivados: **peso grande** = `kgADescargar − parcial`.
Obligatorio: al menos 9 campos, `[2]` y `[3]` enteros, y **3 campos por lote**.

```
39,7800,3250,8000,Lote 3,0,0,0,5,Lote 1,1000,1500,Lote 2,1500,2000,Lote 3,750,2500,Lote 4,0,1800,Lote 5,0,1200\r\n
```
(Ejemplo tomado del *mock* que dejó el propio desarrollador en la página.)

Botones → comandos: ESC (diálogo) → `CTR,esc`; level → `CTR,level`; ACUM (diálogo "¿pasar el lote?") → `CTR,acum,<operario>`; lock → `CTR,lock`; rotate → `CTR,rotate`.

### 7.15 Pantallas `40` y `41` – Diálogos de dos botones

Sin campos. Vista: `dialogo_reanudar_trabajo.dart`.

| ID | Título / texto | Botón 1 | Botón 2 |
|---|---|---|---|
| `40` | ADVERTENCIA – "Debe preparar más carga" | CONTINUAR → `CTR,boton1` | NUEVA → `CTR,boton2` |
| `41` | TRABAJOS – "¿Reanudar trabajo?" | CONTINUAR → `CTR,boton1` | REINICIAR → `CTR,boton2` |

Además ESC → `CTR,esc`.

### 7.16 Pantalla `42` – Cambio de operario (login)

Modelo: `LoginUsuariosModel.fromArray` · Vista: `dialog_cambiar_operario.dart`.

| Índice | Campo | Tipo | Cómo lo usa la app |
|---|---|---|---|
| 1 | cantidad | int | Cantidad de pares que siguen. |
| 2 + 2k | nombre | texto | Se lista como `<k+1> : <nombre>`. |
| 3 + 2k | password | texto | PIN esperado (4 dígitos). Si falta se toma `''`. |

Funcionamiento: el usuario toca un nombre, pulsa START, ingresa el PIN (4 dígitos) y la app lo **compara localmente** con el `password` recibido. Si coincide guarda el operario en la tablet y envía `CTR,esc`; si no, muestra "Contraseña incorrecta" y sigue en `42`. Los PIN viajan en claro.

```
42,3,Dario,1234,Estevan,0000,Claudio,4321\r\n
```

Botones → comandos: ESC → `CTR,esc`; START → diálogo PIN → (si es correcto) `CTR,esc`. Después del `esc` enviar `0`.
Los popups `43` (operario no encontrado) y `44` (clave incorrecta) existían para validación en el indicador; la app hoy valida localmente pero los sigue mostrando si llegan.

### 7.17 Popups sin botones: `16`, `17`, `20`, `43`, `44`, `45`

Sin campos (`<id>\r\n`). Vista: `popups.dart`. Se muestran con título "INFO" y el texto fijo:

| ID | Texto |
|---|---|
| `16` | Primero debe seleccionar un operario en el indicador |
| `17` | Ya realizo la carga, proceda a la descarga |
| `20` | No hay trabajos cargado en el indicador |
| `43` | Operario No encontrado !!! |
| `44` | Clave incorrecta !!! |
| `45` | Indicador ocupado, salga de la pantalla actual del indicador (muestra además el botón *Desconectar*) |

No tienen ESC: el simulador debe enviar otra pantalla (p. ej. `0`) para salir. `45` la envía el ST567 (≥ v1.31.0) mientras el operador está dentro de un menú local del indicador; al salir del menú vuelve a enviar `0`.

---

## 8. Flujos completos sugeridos

Notación: `app →` comando que envía la app; `sim →` pantalla que debe notificar el simulador.

### 8.1 Reposo

```
(conexión BLE)        sim → 0 cada 300 ms   (peso, estabilidad, fecha, levelLock)
app → CTR,cero        sim → 0 con peso 0
app → CTR,levelLock   sim → 0 con levelLock alternado (0/1)
```

### 8.2 Carga por receta

```
app → CTR,elegirReceta                sim → 60 (o 30 en firmware viejo)
app → CTR,nextPage / prevPage         sim → 60 con otra página
app → CTR,detail,2                    sim → 37 (detalle de la receta 2)
app → CTR,esc                         sim → 60
app → CTR,select,2,1500               sim → 38 (cargando 1er ingrediente), repetir cada 300 ms con el peso
   … el peso sube; cuando falta el "aviso" → sirena=1 …
app → CTR,acum,<operario>             sim → 38 (siguiente ingrediente, estado del anterior = 1)
   … último ingrediente …
app → CTR,acum,<operario>             sim → 6 (mezclando, cuenta regresiva) → luego 0   (o 39 si el trabajo sigue con descarga)
app → CTR,esc (en cualquier momento)  sim → 0
```

### 8.3 Carga manual

```
app → CTR,cargaManual                 sim → 32 (lista de ingredientes)      [o directamente 2]
app → CTR,select,3,500                sim → 2 (cargando ingrediente 3, kgACargar 500), repetir con el peso
app → CTR,acum,<operario>             sim → 32 (para elegir otro) o 0
app → CTR,selectIngrediente           sim → 32
app → CTR,esc                         sim → 0
```

### 8.4 Descarga manual

```
app → CTR,descargaManual,L01,1000     sim → 4 (lote L01, kgADescargar 1000), repetir con el peso
app → CTR,acum                        sim → 33 (pedir lote y cantidad)
app → CTR,descargaManual,L02,800      sim → 4 (lote L02)
app → CTR,esc                         sim → 0
```

### 8.5 Trabajos

```
app → CTR,elegirTrabajo               sim → 34 (o 20 si no hay trabajos)
app → CTR,detail,1                    sim → 31
app → CTR,esc                         sim → 34
app → CTR,select,1                    sim → 41 "¿Reanudar trabajo?"  (opcional, si había uno pendiente)
app → CTR,boton1 | CTR,boton2         sim → 38 (etapa de carga)
   … carga como en 8.2 …
app → CTR,acum,<operario> (último)    sim → 6 → 39 (etapa de descarga por lotes)
app → CTR,acum,<operario>             sim → 39 (siguiente lote)   [o 40 "Debe preparar más carga"]
app → CTR,boton1 / boton2 (desde 40)  sim → 39 o 0
   … último lote …                    sim → 0
```

### 8.6 Sincronización

```
app → CTR,sync                        sim → 19,0 … 19,50 … 19,100  (opcional)
                                      sim → 36 (o 35)
app → CTR,esc                         sim → 0
```

### 8.7 Cambio de operario

```
app → CTR,cambiarOperario             sim → 42 con la lista de usuarios y PIN
   (validación local del PIN)
app → CTR,esc                         sim → 0
```

### 8.8 Indicador ocupado

```
(operador entra a un menú del indicador)   sim → 45
(operador sale del menú)                   sim → 0
```

---

## 9. Checklist y errores comunes

* [ ] Cabecera de 5 bytes en **cada** notificación; en una sola parte, `longitud` = bytes del payload incluidos `\r\n` (si no coincide, la trama se descarta en silencio).
* [ ] `numParte` empieza en **1**; `idPaquete` distinto para cada trama lógica.
* [ ] Payload termina en `\r\n` **una sola vez**, al final de la última parte.
* [ ] Sin espacios después de las comas; sin comas dentro de los nombres.
* [ ] Campos **int** (`parcial`, `kgACargar`, `kgADescargar` en `2`, `38`, `39`) siempre enteros; si no, la pantalla no se actualiza.
* [ ] Listas: enviar exactamente los campos por ítem indicados (2 en `30`/`32`/`34`… salvo `34` que lleva 3; 3 en `60` y `39`; 5 en `37`; 6 en `38`). Un ítem truncado rompe el parseo.
* [ ] `34`: máximo 15 trabajos por página; `60`: máximo 30 recetas.
* [ ] `38`/`39`: el `ingredienteActual`/`loteActual` debe coincidir **exactamente** (mayúsculas, espacios) con el `nombre` de la lista para que se resalte.
* [ ] Refrescar la pantalla de peso periódicamente; no hay polling desde la app.
* [ ] Después de un popup sin botones (`16`, `17`, `20`, `43`, `44`, `45`) enviar otra pantalla para salir.
* [ ] Codificación Latin-1/ASCII, no UTF-8 multibyte.

---

## 10. Apéndice

### 10.1 Etiquetas que muestra la app (idioma español)

`Total : `, `Parcial : `, `Kg a Cargar: `, `Kg a Descargar:  `, `Nº Ingrediente: `, `Nombre:`, `Cargando : `, `Descargando Lote: `, `Progreso de Carga`, `Progreso de Descarga`, `Fecha`, `OPERARIO`, `LISTA INGREDIENTES`, `LISTA LOTES`, `Mezclando`, `Sincronizando Indicador`, `Seleccionar Trabajo`, `Seleccionar Receta`, `Seleccionar Ingrediente`, `CAMBIO DE OPERARIO`.

### 10.2 Pantallas del ST407 (no usar con ST567)

`100` principal, `101` carga por receta, `102` carga manual, `103` descarga por guía, `104` descarga manual, `105` mezclando, `106` elegir receta, `107` elegir autónomo, `108` elegir guía. Tienen otros modelos de datos.

### 10.3 Versiones de firmware mencionadas en el repositorio

| Función | ST567 |
|---|---|
| Popup `45` "indicador ocupado" | ≥ v1.31.0 |
| Pantalla `60` (recetas con preset) | ≥ v1.36.3 |
