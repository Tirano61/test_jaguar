# Protocolo Remoto BLE – Indicador **ST456web** (guía para el simulador)

**Origen de la información:** análisis del código de la app `remoto_567_flutter` versión **5.0.0-beta+44**, rama `RemotoBLE`
(`lib/provider/conexion/remoto_common_ble.dart`, `lib/provider/protocolos/st456_coma_parser.dart`,
`lib/provider/stream_provider_remoto.dart`, `lib/models/**`, `lib/pages/**`, `lib/pages/remoto.dart`) y del historial
git del proyecto (el proyecto nació como `remoto_st456` con las pantallas `0`–`12`; las de la serie `30`–`60` se agregaron después para el ST567).
**Fecha:** 14/09/2026.

> Todo lo que dice este documento sobre **formato de tramas, campos y comandos** sale directamente del código de la app y es exacto.
> La **secuencia entre pantallas** (qué pantalla responde el indicador a cada comando) la decide el firmware del ST456web, que no está en
> este repositorio. Los flujos de la sección 8 son los que la app asume por el diseño de sus botones y por el historial del proyecto; el
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

Pantallas que la app usa con el **ST456web**:

| Grupo | IDs |
|---|---|
| Peso / operación | `0`, `1`, `2`, `3`, `4`, `6` |
| Selección con next/prev | `8`, `9`, `10` |
| Listas | `11`, `42` |
| Entrada de datos | `12` |
| Detalles | `18` |
| Diálogos con botones | `14`, `15`, `19`, `35`, `36` |
| Popups sin botones | `16`, `17`, `20`, `43`, `44`, `45` |

Notas de alcance:

* Según el manual de usuario, **Carga Manual**, **Descarga Manual** y **LevelLock** son funciones del ST567. La app igual envía esos comandos (`CTR,cargaManual`, `CTR,descargaManual,…`, `CTR,levelLock`) porque el menú es el mismo; el simulador ST456web puede ignorarlos o responder. Las pantallas `2` y `4` existen desde la versión original ST456 y la app las muestra si llegan.
* Pantallas que **no** son del ST456web pero la app también procesa (pertenecen al ST567, ver `protocolo-simulador-st567.md`): `30`, `31`, `32`, `33`, `34`, `37`, `38`, `39`, `40`, `41`, `60`.
* Pantallas reservadas que el simulador **no debe usar**: `13` (ignorada) y `100`–`108` (indicador ST407).

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
3. Pide **MTU 512**. Si el simulador no lo soporta, debe fragmentar las tramas en más partes (sección 3.2).
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

Una trama de pantalla `11` (6 trabajos) o `18` (detalle con muchos ingredientes) puede superar el MTU. Ejemplo de 250 bytes en partes de 100:

```
Parte 1:  07 03 01 00 64 | <100 bytes de payload>
Parte 2:  07 03 02 00 64 | <100 bytes de payload>
Parte 3:  07 03 03 00 32 | <50 bytes de payload, terminando en 0D 0A>
```

### 3.4 Reglas para los campos

| Regla | Motivo en el código |
|---|---|
| Ningún campo puede contener `,` | `split(',')` sin escape ni comillas. |
| No poner espacios después de las comas (`1, 200` ✗) | Los campos no se recortan individualmente: un flag `" 1"` no es igual a `"1"` (lock, level, sirena, estabilidad, completado…), `tipo` `" RECE"` no se reconoce y los textos se muestran con el espacio. |
| Los campos marcados **int** deben ser enteros (`250`, no `250.0` ni `250,5`) | Se usa `int.tryParse(...)!`; un valor no entero rompe el parseo de toda la trama y la pantalla no se actualiza. |
| Los campos "0/1" son texto: se compara con `"1"` o con `"0"` | Cualquier otro valor cae en la rama "distinto de …" indicada en cada tabla. |
| Los valores se muestran tal cual llegan | No hay formateo; `1250`, `1250.5` o `01250` se muestran así. |
| Campos que faltan al final | La mayoría de los modelos los toma como vacío (`''`); los obligatorios están marcados en cada pantalla. |

---

## 4. Comandos app → indicador

Formato: `CTR,<comando>[,<arg>...]\r\n`, en ASCII, escrito con *write without response* en `ABF4`. Un comando por escritura.

| Comando (bytes exactos) | Desde qué pantalla / acción | Respuesta que espera la app |
|---|---|---|
| `CTR,sync\r\n` | `0`, botón *sincronizar* | `19` (progreso) y al terminar `0` (o `36`/`35` si el firmware lo implementa) |
| `CTR,levelLock\r\n` | `0`, botón *LevelLock* (función ST567; el ST456web puede ignorarlo) | `0` |
| `CTR,cero\r\n` | `0`, pulsación **larga** del botón cero | `0` con peso en cero |
| `CTR,elegirReceta\r\n` | `0` → menú → *Carga Por Receta* | `8` |
| `CTR,elegirTrabajo\r\n` | `0` → menú → *Iniciar Trabajo* | `11` (lista) o `20` (no hay trabajos) |
| `CTR,cargaManual\r\n` | `0` → menú → *Carga Manual* (función ST567) | `2` o ignorar |
| `CTR,descargaManual,<lote>,<kg>\r\n` | `0` → menú → *Descarga Manual* (función ST567) | `4` o ignorar |
| `CTR,cambiarOperario\r\n` | `0` → menú → *Seleccionar Operario*; botón *Operario* en `1`, `2` | `42` |
| `CTR,esc\r\n` | Botón *ESC* de casi todas las pantallas; OK de `35`/`36`; al validar PIN en `42` | Volver a la pantalla anterior (normalmente `0`) |
| `CTR,next\r\n` / `CTR,prev\r\n` | `8` (next y prev), `9` y `10` (sólo next) | La misma pantalla con la siguiente/anterior receta, autónomo o guía |
| `CTR,start,<kg>\r\n` | `8` (start con la cantidad editada) y `12` (parcial ingresado) | `1` (cargando por receta) |
| `CTR,start\r\n` | `9` (autónomo) y `10` (guía), botón *start* | `1` (carga) o `3` (descarga por guía) |
| `CTR,nextPage\r\n` / `CTR,prevPage\r\n` | `11`, botones *next*/*prev* | `11` con la página siguiente/anterior |
| `CTR,detail,<indice>\r\n` | `11`, botón *Detalles* de un trabajo | `18` |
| `CTR,select,<posicion>\r\n` | `11`, botón *start*. **Atención:** `<posicion>` es la fila tocada dentro de la página actual (1..6), no el campo `indice` | `14`, `15`, `12`, `9`, `10`, `16`, `17`… según el trabajo |
| `CTR,boton1\r\n` / `CTR,boton2\r\n` | `14` (CONTINUAR / NUEVA) y `15` (CARGA / DESCARGA) | `12`, `1`, `3`, `9`, `10`… |
| `CTR,acum,<operario>\r\n` | Botón *ACUM* en `1`, `2`, `3` (tras confirmar diálogo). `<operario>` = nombre elegido en la tablet; puede ir **vacío** (`CTR,acum,\r\n`) | Misma pantalla con el siguiente ingrediente/lote, o `6`/`0` |
| `CTR,acum\r\n` | Botón *ACUM* en `4` (descarga manual, sin operario) | `4` o `0` |
| `CTR,lock\r\n` / `CTR,level\r\n` | Botones *lock*/*level* en `1`, `2`, `3`, `4` | Misma pantalla con `lock`/`level` en `1`/`0` |
| `CTR,rotate\r\n` | Botón *rotate* en `1`, `3` | Sin cambio de pantalla (acción del mixer) |
| `CTR,selectIngrediente\r\n` | `2`, botón *ingrediente* (función ST567) | ignorar o `32` |

Comandos definidos en la app pero **no usados** por ninguna pantalla (no hace falta implementarlos): `CTR,loginOperario,<usuario>,<pass>`, `CTR,elegirAutonomo`, `CTR,elegirGuia`, `CTR,acum,<kg>`, `CTR,cargaManual,<kg>`, `CTR,acum,<lote>,<kg>`.

---

## 5. Comportamiento general de la app

* **Cada trama recibida** hace dos cosas: `pantalla = campo[0]` (si cambia, la app navega a esa pantalla) y `conexión = 1`.
* **No hay timeout de datos.** La app sólo marca "desconectado" cuando se cae el enlace BLE. Aun así, para que el peso se vea "vivo" el simulador debe **repetir la pantalla actual periódicamente** (200–500 ms en pantallas de peso; en listas alcanza con enviarlas al entrar y al cambiar).
* ID de pantalla desconocido → se muestra la pantalla principal **sin datos** (rayas). Evitarlo.
* Los **popups sin botones** (`16`, `17`, `20`, `43`, `44`, `45`) no tienen ESC: el simulador debe sacar a la app enviando otra pantalla (normalmente `0`).
* Al recibir cualquier pantalla ≠ `0` mientras está abierto el **menú principal**, la app lo cierra sola (útil con `45`).
* Repetir una trama idéntica es inofensivo: las listas comparan el JSON del modelo y no se redibujan si no cambió.
* Las pantallas `8`, `9`, `10` mantienen el **último valor recibido** en memoria (modelos persistentes): si llega una trama con menos campos de los obligatorios se ignora y queda lo anterior.
* El **operario** que muestra la app es local de la tablet (se elige en `42` y se guarda en la tablet). El campo *operario* de la pantalla `0` se parsea pero **no se muestra**. El nombre se envía en `CTR,acum,<operario>`.
* El botón **Desconectar** de la barra superior corta el BLE desde la app (no envía comando).

---

## 6. Tabla resumen de pantallas

| ID | Nombre en la app | Payload (después del ID) | Botones → comandos |
|---|---|---|---|
| `0` | Pantalla principal | `peso,estabilidad,unidad,operario,fecha,levelLock` | levelLock, sync, menú, bluetooth, cero(long) |
| `1` | Carga por receta | `total,parcial*,kgACargar*,ingrediente,lock,level,sirena` | esc, level, acum(op), lock, rotate, operario |
| `2` | Carga manual | `total,parcial*,kgACargar*,nroIngrediente,ingrediente,lock,level,sirena` | esc, level, acum(op), lock, selectIngrediente, operario |
| `3` | Descarga por guía | `total,parcial*,kgADescargar*,lote,lock,level,sirena` | esc, level, acum(op), lock, rotate |
| `4` | Descarga manual | `total,parcial,kgADescargar,lote,lock,level,sirena` | esc, level, acum, lock |
| `6` | Mezclando | `minutos,segundos` | esc |
| `8` | Elegir receta | `nombre,cantidad` | esc, prev, start(kg), next |
| `9` | Elegir autónomo | `numero,nombre,fechaInicial,fechaFinal,receta,guia` | esc, start, next |
| `10` | Elegir guía | `numero,nombre` | esc, start, next |
| `11` | Trabajos | `n,(indice,orden,tipo,nombre,completado)*n` (n ≤ 6) | esc, prevPage, start→select(pos), nextPage, detail |
| `12` | Usar parcial | `parcial` | esc, start(kg) |
| `14` | Diálogo "DESCARGA PENDIENTE" | – | CONTINUAR→boton1, NUEVA→boton2, esc |
| `15` | Diálogo "INICIAR TRABAJO – Elija el siguiente paso" | – | CARGA→boton1, DESCARGA→boton2, esc |
| `16` | Popup "Primero debe seleccionar un operario en el indicador" | – | (ninguno) |
| `17` | Popup "Ya realizó la carga, proceda a la descarga" | – | (ninguno) |
| `18` | Detalles receta / guía | `tipo,nombreReceta,nombreGuia,minMezcla,nIng,nLotes,(ing,kg)*nIng,(lote,kg)*nLotes` | esc |
| `19` | Sincronizando (porcentaje) | `porcentaje` | esc |
| `20` | Popup "No hay trabajos cargados en el indicador" | – | (ninguno) |
| `35` / `36` | Diálogo sincronización fallida / exitosa | – | OK→esc, esc |
| `42` | Cambio de operario (login) | `n,(nombre,password)*n` | esc, start→PIN local→esc |
| `43` / `44` | Popup operario no encontrado / clave incorrecta | – | (ninguno) |
| `45` | Popup "Indicador ocupado…" | – | Desconectar (BLE) |

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
| 4 | operario | texto | Se parsea pero **no se muestra**. Puede ir vacío. |
| 5 | fecha | texto | Se muestra como `Fecha: <valor>`. Formato libre. |
| 6 | levelLock | 0/1 | `"0"` → líneas azules; cualquier otro valor → líneas **rojas**. Si falta se asume `0`. Para ST456web enviar siempre `0`. |

Mínimo: sólo el ID; los campos faltantes quedan vacíos.

```
0,1250,1,kg,,14/09/2026 10:32,0\r\n      peso estable
0,1248,0,kg,,14/09/2026 10:32,0\r\n      peso inestable
0,0,1,kg,,14/09/2026 10:33,0\r\n         después de CTR,cero
```

Comandos que puede recibir el simulador estando en `0`: `CTR,levelLock`, `CTR,sync`, `CTR,cero`, y desde el menú: `CTR,cargaManual`, `CTR,elegirReceta`, `CTR,descargaManual,<lote>,<kg>`, `CTR,elegirTrabajo`, `CTR,cambiarOperario`.

### 7.2 Pantalla `1` – Carga por receta

Modelo: `PantallaCargaRecetaModel.fromParseo` · Vista: `carga_por_receta_page.dart`.

| Índice | Campo | Tipo | Cómo lo usa la app |
|---|---|---|---|
| 1 | total | texto | Fila `Total : <valor>` (total cargado de la receta). |
| 2 | parcial | **int** | Fila `Parcial : <valor>` (cargado del ingrediente actual) y barra de progreso. |
| 3 | kgACargar | **int** | Fila `Kg a Cargar: <valor>` (objetivo del ingrediente actual) y barra. |
| 4 | ingrediente | texto | Fila `Cargando : <valor>`. |
| 5 | lock | 0/1 | `"1"` → fondo rojo translúcido detrás del peso grande. |
| 6 | level | 0/1 | `"1"` → fondo azul translúcido en la franja del peso. |
| 7 | sirena | 0/1 | `"1"` → sirena en loop (aviso anticipado); `"0"` → se apaga. |

Derivados: **peso grande** = `kgACargar − parcial`; progreso = `parcial / kgACargar` (se muestra `%` y `parcial / kgACargar kg`).
Obligatorio: al menos 4 campos con `[2]` y `[3]` enteros.

```
1,3200,450,1200,Maiz,0,0,0\r\n      peso grande 750, progreso 37 %
1,3200,1100,1200,Maiz,0,0,1\r\n     faltan 100 kg, sirena
1,4400,0,800,Soja,0,0,0\r\n         después de CTR,acum: siguiente ingrediente
```

Botones → comandos: ESC (diálogo "¿Está seguro que desea salir?") → `CTR,esc`; level → `CTR,level`; ACUM (diálogo "¿pasar el ingrediente?") → `CTR,acum,<operario>`; lock → `CTR,lock`; rotate → `CTR,rotate`; botón *Operario* de la barra → `CTR,cambiarOperario` (esperar `42`).

### 7.3 Pantalla `2` – Carga manual

Modelo: `PantallaCargaManualModel.fromParceo` · Vista: `carga_manual_page.dart`. (En el ST456web la carga manual no pide kg desde la app; el indicador envía esta pantalla si entra en carga manual localmente.)

| Índice | Campo | Tipo | Cómo lo usa la app |
|---|---|---|---|
| 1 | totalCargado | texto | Fila `Total : <valor>`. |
| 2 | parcialCargado | **int** | Fila `Parcial : <valor>` y barra. |
| 3 | kgACargar | **int** | Fila `Kg a Cargar: <valor>` y barra. |
| 4 | nroIngrediente | texto | Fila `Nº Ingrediente: <valor>`. |
| 5 | ingrediente | texto | Fila `Nombre: <valor>`. |
| 6 | lock | 0/1 | `"1"` → fondo rojo. |
| 7 | level | 0/1 | `"1"` → fondo azul. |
| 8 | sirena | 0/1 | `"1"` sirena en loop, `"0"` apaga. Si falta se asume `0`. |

Derivados: **peso grande** = `kgACargar − parcialCargado`.

```
2,800,120,500,3,Soja,0,0,0\r\n
```

Botones → comandos: ESC → `CTR,esc`; level → `CTR,level`; ACUM → `CTR,acum,<operario>`; lock → `CTR,lock`; ingrediente → `CTR,selectIngrediente` (función ST567, ignorar); *Operario* → `CTR,cambiarOperario`.

### 7.4 Pantalla `3` – Descarga por guía

Modelo: `PantallaDescargaGuiaModel.fromParceo` · Vista: `descarga_por_guia.dart`.

| Índice | Campo | Tipo | Cómo lo usa la app |
|---|---|---|---|
| 1 | total | texto | Fila `Total : <valor>` (total descargado de la guía). |
| 2 | parcial | **int** | Fila `Parcial : <valor>` (descargado del lote actual) y barra. |
| 3 | kgADescargar | **int** | Objetivo del lote actual (barra). |
| 4 | lote | texto | Fila `Descargando Lote: <valor>`. |
| 5 | lock | 0/1 | `"1"` → fondo rojo. |
| 6 | level | 0/1 | `"1"` → fondo azul. |
| 7 | sirena | 0/1 | `"1"` sirena en loop, `"0"` apaga. |

Derivados: **peso grande** = `kgADescargar − parcial`. La fila `Kg a Descargar:` muestra ese **restante**, no el objetivo.
Obligatorio: al menos 4 campos con `[2]` y `[3]` enteros.

```
3,5000,1500,2000,Corral 4,0,0,0\r\n     restante 500
3,7000,0,1800,Corral 5,0,0,0\r\n        siguiente lote tras CTR,acum
```

Botones → comandos: ESC (diálogo) → `CTR,esc`; level → `CTR,level`; ACUM (diálogo) → `CTR,acum,<operario>`; lock → `CTR,lock`; rotate → `CTR,rotate`.

### 7.5 Pantalla `4` – Descarga manual

Modelo: `PantallaDescargaManualModel.fromParceo` · Vista: `descarga_manual_page.dart`.

| Índice | Campo | Tipo | Cómo lo usa la app |
|---|---|---|---|
| 1 | totalCargado | texto | Fila `Total : <valor>`. |
| 2 | parcialCargado | int (tolerante: si falta o no es entero se toma 0) | Fila `Parcial : <valor>` y barra. |
| 3 | kgADescargar | int (tolerante) | Fila `Kg a Descargar: <valor>` y barra. |
| 4 | lote | texto | Fila `Descargando Lote: <valor>`. Si falta muestra ` -`. |
| 5 | lock | 0/1 | `"1"` → fondo rojo. |
| 6 | level | 0/1 | `"1"` → fondo azul. |
| 7 | sirena | 0/1 | `"1"` sirena en loop, `"0"` apaga. |

Derivados: **peso grande** = `kgADescargar − parcialCargado`; si `kgADescargar = 0` se muestra `|parcialCargado|`.

```
4,2600,300,1000,L01,0,0,0\r\n
4,2600,300,0,L01,0,0,0\r\n          sin objetivo: muestra 300
```

Botones → comandos: ESC → `CTR,esc`; level → `CTR,level`; ACUM (diálogo) → `CTR,acum` (sin operario); lock → `CTR,lock`.

### 7.6 Pantalla `6` – Mezclando

| Índice | Campo | Tipo | Cómo lo usa la app |
|---|---|---|---|
| 1 | minutos | texto | Se muestra `<minutos>:` en grande. |
| 2 | segundos | texto | Se rellena a 2 dígitos a la izquierda (`5` → `05`). |

Obligatorio: al menos 3 campos (si no, la trama se ignora). Repetir cada segundo.

```
6,2,5\r\n      →  2:05
6,0,59\r\n     →  0:59
```

Botón: ESC → `CTR,esc`.

### 7.7 Pantalla `8` – Elegir receta

Modelo: `PantallaElegirRecetaModel.fromParceo` · Vista: `elegir_receta_page.dart`.

| Índice | Campo | Tipo | Cómo lo usa la app |
|---|---|---|---|
| 1 | nombre | texto | `Receta : <nombre>`. |
| 2 | cantidad | texto (numérico) | Precarga el campo editable `Cantidad`. Sólo se vuelve a precargar cuando el valor recibido **cambia** (así no pisa lo que escribe el usuario). |

```
8,Vacas Lecheras,1500\r\n
8,Terneros,800\r\n          tras CTR,next
```

Botones → comandos: ESC → `CTR,esc`; prev → `CTR,prev`; next → `CTR,next`; START → `CTR,start,<cantidad editada>` (esperar `1`). El peso no se muestra en esta pantalla (recuadro con rayas).

### 7.8 Pantalla `9` – Elegir autónomo

Modelo: campos en `PantallaElegirAutonomoModel` · Vista: `elegir_autonomo_page.dart`.

| Índice | Campo | Tipo | Cómo lo usa la app |
|---|---|---|---|
| 1 | numeroDeAutonomo | texto | `Nº de Autonomo : <valor>`. |
| 2 | nombreDeAutonomo | texto | `Nombre Autónomo : <valor>`. |
| 3 | fechaInicial | texto | `Fecha inicio : <valor>`. |
| 4 | fechaFinal | texto | `Fecha final : <valor>`. |
| 5 | receta | texto | `Receta : <valor>`. |
| 6 | guia | texto | `Guía<valor>` (la etiqueta no lleva separador). |

Obligatorio: **7 campos** (si llegan menos, la trama se ignora).

```
9,3,Lote Norte,01/09/2026,30/09/2026,Vacas Lecheras,Corrales A\r\n
```

Botones → comandos: ESC → `CTR,esc`; START → `CTR,start` (sin argumentos; esperar `1`); next → `CTR,next`. No hay botón *prev*.

### 7.9 Pantalla `10` – Elegir guía

Modelo: campos en `PantallaElegirGuiaModel` · Vista: `elegir_guia_page.dart`.

| Índice | Campo | Tipo | Cómo lo usa la app |
|---|---|---|---|
| 1 | numeroDeGuia | texto | `Nº de Guía : <valor>`. |
| 2 | nombreDeGuia | texto | `Nombre:<valor>`. |

Obligatorio: **3 campos**.

```
10,2,Corrales A\r\n
```

Botones → comandos: ESC → `CTR,esc`; START → `CTR,start` (esperar `3`); next → `CTR,next`. No hay *prev*.

### 7.10 Pantalla `11` – Trabajos

Modelo: `PantallaTrabajosModel.fromParceo` · Vista: `trabajos_page.dart` y widgets `trabajos_leading.dart` / `trabajos_trailing.dart`.

| Índice | Campo | Tipo | Cómo lo usa la app |
|---|---|---|---|
| 1 | tTrabajos | int | Cantidad de trabajos de esta página. Se usa como cantidad de filas: **máximo 6**; más de 6 rompe la lista. |
| 2 + 5k | indice | texto | `ID: <indice>`. Es lo que se envía en `detail`. |
| 3 + 5k | orden | texto | `ORDEN: <orden>` rellenado a 3 dígitos (`7` → `007`). |
| 4 + 5k | tipo | texto | `TIPO: <tipo>` + ícono: `RECE` → ícono de receta; `GUIA` → ícono de mixer; cualquier otro (p. ej. `AUTO`) → ambos íconos. |
| 5 + 5k | nombre | texto | Nombre del trabajo. |
| 6 + 5k | completado | 0/1 | `"1"` → tilde verde (trabajo realizado). |

La app siempre reserva 6 posiciones internas (campos 2–31); las que no lleguen quedan vacías. Paginar con `nextPage`/`prevPage`.

```
11,3,1,1,RECE,Carga Manana,1,2,2,GUIA,Descarga Corral 4,0,3,3,AUTO,Autonomo Norte,0\r\n
11,6,7,7,RECE,Trabajo 7,0,8,8,RECE,Trabajo 8,0,9,9,GUIA,Trabajo 9,0,10,10,GUIA,Trabajo 10,0,11,11,AUTO,Trabajo 11,0,12,12,RECE,Trabajo 12,0\r\n
```

Botones → comandos: ESC → `CTR,esc`; prev → `CTR,prevPage`; next → `CTR,nextPage`; *Detalles* → `CTR,detail,<indice>` (esperar `18`); START (requiere haber tocado una fila) → `CTR,select,<posicion>` donde **`<posicion>` es el número de fila en la página actual (1..6)**, no el `indice`. El simulador debe traducir posición → trabajo de la página que está mostrando.

### 7.11 Pantalla `12` – Usar parcial

Vista: `parcial_page.dart`.

| Índice | Campo | Tipo | Cómo lo usa la app |
|---|---|---|---|
| 1 | parcial | texto (numérico) | Precarga el campo editable `PARCIAL :` (máx. 5 caracteres). Se recorta con `trim()`. |

Obligatorio: 2 campos (si falta `[1]` la trama falla).

```
12,1500\r\n
```

Botones → comandos: ESC → `CTR,esc`; START → `CTR,start,<valor del campo>` (esperar `1`).

### 7.12 Pantallas `14` y `15` – Diálogos de dos botones

Sin campos. Vistas: `dialogo_reanudar_trabajo.dart` (`14`), `dialogo_carga_o_descarga.dart` (`15`).

| ID | Título / texto | Botón 1 | Botón 2 |
|---|---|---|---|
| `14` | DESCARGA PENDIENTE – "Continuar con la carga anterior o iniciar una nueva?" | CONTINUAR → `CTR,boton1` | NUEVA → `CTR,boton2` |
| `15` | INICIAR TRABAJO – "Elija el siguiente paso." | CARGA → `CTR,boton1` | DESCARGA → `CTR,boton2` |

Además ESC → `CTR,esc`.

### 7.13 Pantalla `18` – Detalles de receta / guía

Modelo: `DetalleRecetaGuiaModel.fromParseo` · Vista: `detalles_recetas_guias_page.dart` + `receta_widget.dart`, `guia_widget.dart`, `guia_y_receta.dart`.

| Índice | Campo | Tipo | Cómo lo usa la app |
|---|---|---|---|
| 1 | tipo | texto | `"1"` → sólo receta; `"2"` → sólo guía; `"3"` → receta y guía lado a lado; otro → "Tipo no soportado". |
| 2 | nombreReceta | texto | Nombre en el panel de receta (etiqueta `Nombre Autónomo :` en tipo `1`, `Nombre :` en tipo `3`). **En tipo `2` el panel de guía muestra este campo** (peculiaridad de la vista): poner ahí el nombre de la guía. |
| 3 | nombreGuia | texto | Nombre en el panel de guía (sólo se usa en tipo `3`). |
| 4 | minutosMezcla | texto | `Mezcla : <valor> min` en el panel de receta. |
| 5 | cantIngredientes | int | Cantidad de pares (nombre, kg) que siguen. |
| 6 | cantLotes | int | Cantidad de pares (lote, kg) que siguen después de los ingredientes. |
| 7 … | ingredientes | (texto, texto) × cantIngredientes | Tarjetas `Ingrediente : <nombre>` — `<kg> kg`. |
| … | lotes | (texto, texto) × cantLotes | Tarjetas `Lote : <nombre>` — `<kg> kg`. |

Obligatorio: al menos 7 campos. Para tipo `1` enviar `cantLotes = 0`; para tipo `2`, `cantIngredientes = 0`.

```
18,3,Vacas Lecheras,Corrales A,5,3,2,Maiz,600,Soja,300,Heno,900,Corral 1,1000,Corral 2,800\r\n   receta + guía
18,1,Vacas Lecheras,,5,3,0,Maiz,600,Soja,300,Heno,900\r\n                                        sólo receta
18,2,Corrales A,Corrales A,0,0,2,Corral 1,1000,Corral 2,800\r\n                                   sólo guía
```

Botón: ESC → `CTR,esc` (volver a `11`).

### 7.14 Pantalla `19` – Sincronizando (porcentaje)

| Índice | Campo | Tipo | Cómo lo usa la app |
|---|---|---|---|
| 1 | porcentaje | texto | `SINCRONIZANDO : <valor>` (la app no agrega `%`). |

```
19,0\r\n
19,45\r\n
19,100\r\n
```

Botón: ESC → `CTR,esc`. Al terminar, enviar `0` (o `36`/`35`, que la app también muestra: diálogo "La sincronización ha sido exitosa / ha fallado" con OK → `CTR,esc`).

### 7.15 Pantalla `42` – Cambio de operario (login)

Modelo: `LoginUsuariosModel.fromArray` · Vista: `dialog_cambiar_operario.dart`. Disponible en ST456web desde la versión de app 2.3.0.

| Índice | Campo | Tipo | Cómo lo usa la app |
|---|---|---|---|
| 1 | cantidad | int | Cantidad de pares que siguen. |
| 2 + 2k | nombre | texto | Se lista como `<k+1> : <nombre>`. |
| 3 + 2k | password | texto | PIN esperado (4 dígitos). Si falta se toma `''`. |

Funcionamiento: el usuario toca un nombre, pulsa START, ingresa el PIN y la app lo **compara localmente** con el `password` recibido. Si coincide guarda el operario en la tablet y envía `CTR,esc`; si no, muestra "Contraseña incorrecta" y sigue en `42`.

```
42,3,Dario,1234,Estevan,0000,Claudio,4321\r\n
```

Botones → comandos: ESC → `CTR,esc`; START → diálogo PIN → (si es correcto) `CTR,esc`. Después del `esc` enviar `0`.

### 7.16 Popups sin botones: `16`, `17`, `20`, `43`, `44`, `45`

Sin campos (`<id>\r\n`). Vista: `popups.dart`. Título fijo "INFO" y texto:

| ID | Texto | Cuándo lo envía el indicador |
|---|---|---|
| `16` | Primero debe seleccionar un operario en el indicador | Al intentar iniciar un trabajo sin operario cargado en el indicador. |
| `17` | Ya realizo la carga, proceda a la descarga | Al seleccionar un trabajo cuya carga ya se hizo. |
| `20` | No hay trabajos cargado en el indicador | Respuesta a `CTR,elegirTrabajo` sin trabajos. |
| `43` | Operario No encontrado !!! | Legado de validación en el indicador. |
| `44` | Clave incorrecta !!! | Legado de validación en el indicador. |
| `45` | Indicador ocupado, salga de la pantalla actual del indicador (con botón *Desconectar*) | ST456web ≥ v1.38.5, mientras el operador está en un menú local. |

No tienen ESC: el simulador debe enviar otra pantalla (p. ej. `0` o `11`) para salir.

---

## 8. Flujos completos sugeridos

Notación: `app →` comando que envía la app; `sim →` pantalla que debe notificar el simulador.

### 8.1 Reposo

```
(conexión BLE)        sim → 0 cada 300 ms   (peso, estabilidad, fecha, levelLock=0)
app → CTR,cero        sim → 0 con peso 0
```

### 8.2 Carga por receta (menú)

```
app → CTR,elegirReceta                sim → 8 (primera receta y su cantidad)
app → CTR,next / CTR,prev             sim → 8 con otra receta
app → CTR,start,1500                  sim → 1 (1er ingrediente), repetir cada 300 ms con el peso
   … el peso sube; cerca del objetivo → sirena=1 …
app → CTR,acum,<operario>             sim → 1 (siguiente ingrediente, parcial=0, total acumulado)
   … último ingrediente …
app → CTR,acum,<operario>             sim → 6 (mezclando, cuenta regresiva) → luego 0 (o 3 si sigue descarga)
app → CTR,esc (en cualquier momento)  sim → 0
```

### 8.3 Trabajos

```
app → CTR,elegirTrabajo               sim → 11 (página 1, ≤ 6 trabajos)   [o 20 si no hay]
app → CTR,nextPage / prevPage         sim → 11 con otra página
app → CTR,detail,2                    sim → 18 (tipo 1, 2 o 3 según el trabajo)
app → CTR,esc                         sim → 11
app → CTR,select,2                    (fila 2 de la página actual)
      trabajo tipo RECE  →            sim → 15 "Elija el siguiente paso" → app → CTR,boton1 → sim → 12 (parcial) → app → CTR,start,1500 → sim → 1 …
      trabajo tipo GUIA  →            sim → 15 → app → CTR,boton2 → sim → 10 (guía) → app → CTR,start → sim → 3 …
      trabajo tipo AUTO  →            sim → 9 (autónomo) → app → CTR,start → sim → 1 … → 6 → 3 …
      carga anterior sin descargar →  sim → 14 "DESCARGA PENDIENTE" → app → CTR,boton1 (continuar) | CTR,boton2 (nueva)
      sin operario en el indicador →  sim → 16 → (luego) sim → 11
      carga ya hecha →                sim → 17 → (luego) sim → 11 o 3
```

### 8.4 Descarga por guía

```
sim → 10 (guía N)
app → CTR,next                        sim → 10 (guía N+1)
app → CTR,start                       sim → 3 (1er lote), repetir con el peso
app → CTR,acum,<operario>             sim → 3 (siguiente lote)
   … último lote …                    sim → 0
app → CTR,esc                         sim → 0
```

### 8.5 Carga / descarga manual iniciadas en el indicador

```
(operador inicia carga manual en el indicador)     sim → 2, repetir con el peso
app → CTR,acum,<operario>                          sim → 2 (siguiente) o 0
(operador inicia descarga manual en el indicador)  sim → 4, repetir con el peso
app → CTR,acum                                     sim → 4 o 0
```

### 8.6 Sincronización

```
app → CTR,sync                        sim → 19,0 … 19,50 … 19,100
                                      sim → 0   (o 36 / 35 y luego, tras CTR,esc, 0)
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
* [ ] Campos **int** (`parcial`, `kgACargar`, `kgADescargar` en `1`, `2`, `3`) siempre enteros; si no, la pantalla no se actualiza.
* [ ] `9` necesita 7 campos, `10` necesita 3, `6` necesita 3, `12` necesita 2; con menos, la trama se ignora o falla.
* [ ] `11`: máximo 6 trabajos por página y **5 campos por trabajo**; `select` recibe la **posición** (1..6), `detail` recibe el **indice**.
* [ ] `18`: los contadores `[5]` y `[6]` deben coincidir con los pares enviados; en tipo `2` poner el nombre de la guía también en `[2]`.
* [ ] Refrescar la pantalla de peso periódicamente; no hay polling desde la app.
* [ ] Después de un popup sin botones (`16`, `17`, `20`, `43`, `44`, `45`) enviar otra pantalla para salir.
* [ ] Codificación Latin-1/ASCII, no UTF-8 multibyte.

---

## 10. Apéndice

### 10.1 Etiquetas que muestra la app (idioma español)

`Total : `, `Parcial : `, `Kg a Cargar: `, `Kg a Descargar:  `, `Nº Ingrediente: `, `Nombre:`, `Cargando : `, `Descargando Lote: `, `Progreso de Carga`, `Progreso de Descarga`, `Fecha`, `OPERARIO`, `Receta`, `Cantidad`, `Nº de Autonomo : `, `Nombre Autónomo`, `Fecha inicio : `, `Fecha final : `, `Guía`, `Nº de Guía : `, `ID: `, `ORDEN: `, `TIPO: `, `PARCIAL : `, `Mezclando`, `Sincronizando Indicador`, `Seleccionar Trabajo`, `Elegir Receta`, `Elegir Autónomo`, `Elegir Guía`, `Detalles Recetas - Guías`, `CAMBIO DE OPERARIO`.

### 10.2 Pantallas del ST567 (no usar con ST456web)

`30`/`60` elegir receta (lista), `31` detalle de trabajo, `32` elegir ingrediente, `33` diálogo lote+cantidad, `34` trabajos (3 campos por trabajo, hasta 15), `37` detalle de receta, `38` carga por receta con lista, `39` descarga por guía con lotes, `40`/`41` diálogos. Están documentadas en `protocolo-simulador-st567.md`.

### 10.3 Pantallas del ST407 (no usar)

`100`–`108`. Tienen otros modelos de datos.

### 10.4 Versiones de firmware mencionadas en el repositorio

| Función | ST456web |
|---|---|
| Popup `45` "indicador ocupado" | ≥ v1.38.5 |
| Detalles de recetas (`18`) correctos | ≥ v1.40.0 (hasta 1.38.7 el indicador tenía un problema al mostrarlos) |
