# Plan de Implementación - Descarga Automática BLE Hidráulica

## 1. Objetivo

Incorporar un nuevo modo de descarga para BLE en el que la balanza controla hidráulicos del tractor, sin romper ni alterar el flujo actual de la aplicación para usuarios que siguen operando con el modo clásico.

## 2. Principios de implementación

- Respetar la arquitectura existente por capas: presentation, application, domain, infrastructure.
- Mantener compatibilidad con el flujo clásico actual.
- Evitar cambios invasivos en módulos no relacionados al nuevo modo.
- Reutilizar componentes existentes cuando sea posible.
- Mantener el protocolo BLE/WiFi vigente y agregar el nuevo comportamiento de forma opt-in por configuración.
- Implementar parseo JSON BLE tolerante a evolución de firmware: aceptar payloads con keys extra o faltantes opcionales, consumiendo solo las keys necesarias.

## 3. Alcance funcional del nuevo modo

- Disponible solo cuando el tipo de conexión es BLE.
- Permite iniciar descarga por comando AT+INICIO desde diálogo de operación.
- Permite mover manualmente tubo y guillotina por AT+MOVIMIENTO desde pantalla.
- Recibe eventos de guardado por AT+GUARDAR desde notify BLE.
- Recibe AT+GUARDARDOS como cierre de la primera descarga del modo dos
  descargas: guarda igual que con AT+GUARDAR pero se queda en descarga y pide
  el segundo tramo.
- Muestra en pantalla estados de toma de fuerza y mensaje de error ECU.
- Ignora sensorInduc para transición de pantallas y guardado cuando el modo está activo.

## 4. Protocolo nuevo a soportar

### 4.1 Campos JSON adicionales

- tomaFuerza: int (0 apagada, 1 encendida, 2 encienda toma de fuerza, 3 apague toma de fuerza)
- rpm: int (rpm de la toma de fuerza; solo con tomaFuerza = 1, en el resto de los estados va 0)
- errorEcu: string

Rango simulable de rpm: 200 a 1200.

### 4.2 Comando de inicio de descarga

AT+INICIO=<kgDescarga>,<kgTubo>,<kgPrecierre>,<modo>,<velocidad>\r\n

Mapeos:

- modo: 1 una descarga, 2 dos descargas, 3 total, 4 noria
- velocidad: 1 lenta, 2 normal, 3 rapida, 4 variable

Validaciones:

- kgDescarga > kgTubo
- kgDescarga < peso actual en tolva

Sobre el modo:

- modo = 2 (dos descargas) cambia unicamente el evento con el que cierra esa
  corrida: en lugar de AT+GUARDAR se envia AT+GUARDARDOS (ver 4.8). El resto de
  la descarga (validaciones, AT+DETENER / AT+REANUDAR / AT+FINALIZAR, posiciones
  de tubo y guillotina, velocidad) es identico a cualquier otra descarga.
- El segundo AT+INICIO de esa secuencia va con modo = 1 y su kgDescarga se
  valida contra el peso remanente, o sea el que quedo despues de la primera
  descarga.
- Los modos 1, 3, 4 y cualquier valor desconocido cierran con AT+GUARDAR.

### 4.3 Comando de pausa de descarga

AT+DETENER\r\n

- Pausa la descarga en curso: el peso queda congelado donde estaba.
- No cancela la descarga: se conservan kg objetivo y velocidad del AT+INICIO.
- No dispara AT+GUARDAR (la descarga todavía no alcanzó el objetivo).
- Tubo y guillotina quedan en su posición y siguen ignorando AT+MOVIMIENTO,
  porque la descarga sigue en curso (pausada).
- Si no hay descarga en curso, o ya estaba pausada, se ignora.

### 4.4 Comando de reanudación de descarga

AT+REANUDAR\r\n

- Continúa la descarga pausada por AT+DETENER desde el peso en el que quedó.
- Mantiene el mismo objetivo y la misma velocidad del AT+INICIO original.
- Al alcanzar el objetivo dispara AT+GUARDAR como cualquier descarga completa.
- Si no hay descarga pausada, se ignora.

### 4.5 Comando de finalización de descarga

AT+FINALIZAR\r\n

- Termina la descarga automática en curso sin haber llegado al objetivo.
- El peso queda donde estaba en ese momento.
- Descarta la corrida: no queda nada para reanudar con AT+REANUDAR.
- Vale con la descarga corriendo y también con la descarga pausada por AT+DETENER.
- No dispara AT+GUARDAR: el guardado lo decide la app que finalizó.
- Tubo y guillotina quedan en su posición y vuelven a aceptar AT+MOVIMIENTO.
- Si no hay descarga en curso, se ignora.

### 4.6 Evento de guardado

- Entrada por notify BLE: AT+GUARDAR
- Se emite al completar una descarga iniciada con modo distinto de 2, y tambien
  desde el boton manual del simulador.
- Compatibilidad recomendada de parser: AT+GUARDAR, AT+GUARDAR() y variantes con espacios.
- Atencion: AT+GUARDAR es prefijo de AT+GUARDARDOS (4.8). El parser tiene que
  comparar la linea completa por igualdad exacta, o evaluar AT+GUARDARDOS antes
  que AT+GUARDAR y cortar ahi. Con contains / startsWith sobre AT+GUARDAR, una
  descarga en modo 2 se procesa como guardado simple, la app vuelve a la
  pantalla de carga y la segunda descarga nunca se pide.
- Por el mismo motivo, evaluar recien al cerrar la linea en \r\n y nunca sobre
  el buffer parcial: el notify va troceado por MTU y AT+GUARDARDOS podria
  verse como AT+GUARDAR antes de recibir el resto.

### 4.7 Movimiento manual

AT+MOVIMIENTO=<tipo>\r\n

- 1 abrir tubo
- 2 cerrar tubo
- 3 abrir guillotina
- 4 cerrar guillotina

### 4.8 Evento de guardado con segunda descarga

AT+GUARDARDOS\r\n

- Se emite en lugar de AT+GUARDAR cuando la descarga que se acaba de completar
  fue iniciada con AT+INICIO en modo = 2 (dos descargas).
- Se emite unicamente al alcanzar el peso objetivo. AT+DETENER no lo emite (solo
  pausa) y AT+FINALIZAR tampoco (descarta la corrida sin mandar ningun guardado).
- Una descarga en modo 2 pausada con AT+DETENER y retomada con AT+REANUDAR sigue
  cerrando con AT+GUARDARDOS.
- Despues de emitirlo la balanza no queda en ningun estado especial: la corrida
  termino, tubo y guillotina conservan su posicion y vuelven a aceptar
  AT+MOVIMIENTO. Queda esperando un AT+INICIO nuevo como en cualquier otro momento.

Comportamiento esperado de la app al recibirlo:

- Ejecuta el mismo guardado que con AT+GUARDAR: persiste la pesada, imprime y
  envia, con la misma logica de parcial.
- No navega a la pantalla de carga: se queda en la pantalla de descarga.
- Abre el dialogo de inicio de descarga con el modo fijo en 1 (una sola
  descarga), no editable. Los demas parametros (kg a descargar, velocidad, etc.)
  quedan editables, igual que en la pantalla de carga.
- Al confirmar envia AT+INICIO=<kgDescarga>,<kgTubo>,<kgPrecierre>,1,<velocidad>.
  Esa segunda corrida cierra con AT+GUARDAR (4.6) y recien ahi la app vuelve a
  la pantalla de carga.

Secuencia completa:

```
app -> AT+INICIO=1500,300,100,2,2
bal <- {json...}            (peso bajando)
bal <- AT+GUARDARDOS        la app guarda/imprime/envia y se queda en descarga
app -> AT+INICIO=800,300,100,1,2   modo fijo en 1
bal <- {json...}            (peso bajando)
bal <- AT+GUARDAR           la app guarda y vuelve a carga
```

- Si la app manda el segundo AT+INICIO otra vez con modo = 2, la balanza vuelve
  a responder AT+GUARDARDOS: no hay tope ni corte del lado de la balanza, el
  modo lo fija la app. Por eso el dialogo del segundo tramo tiene el modo
  bloqueado en 1.
- Si llega AT+FINALIZAR entre las dos descargas (despues de AT+GUARDARDOS y
  antes del segundo AT+INICIO) se ignora: no hay descarga en curso.

## 5. Estrategia de UI

Para minimizar riesgo de regresión:

- Mantener pantallas actuales para modo clásico sin cambios funcionales.
- Crear variantes de pantallas para modo hidráulico:
  - carga_hidraulica_page
  - descarga_hidraulica_page
- Enrutar desde work shell según modo y configuración activa.
- Reutilizar widgets compartidos (header, cards, layout base) para evitar duplicación innecesaria.

## 6. Plan por fases

### Fase 1 - Configuración y modelo de dominio

Objetivo:

Agregar flags y parámetros del modo hidráulico en configuración persistente.

Tareas:

- Extender entidad de configuración con:
  - activarDescargaAutomaticaBle
  - kgTubo
  - kgPrecierre
  - kgDescargaUltimo
  - modoDescargaUltimo
  - velocidadDescargaUltima
- Extender notifier de configuración con setters correspondientes.
- Persistir claves en SharedPreferences con defaults compatibles.

Entregable:

- Configuración del modo hidráulico persistida y recuperable.

### Fase 2 - Telemetría BLE y parseo

Objetivo:

Soportar nuevos campos del JSON BLE y robustecer parser.

Tareas:

- Extender WeightReading con tomaFuerza y errorEcu.
- Parsear tomaFuerza y errorEcu en ambos repositorios BLE.
- Alinear compatibilidad de aliases documentados para humedad/hum y sensorInduc/sensor.
- Asegurar parseo tolerante para JSON base, JSON base+keys nuevas y JSON con keys adicionales no usadas, sin error por diferencias de cantidad de campos.

Entregable:

- Lecturas BLE enriquecidas con nuevos datos de protocolo.

### Fase 3 - Lógica de sesión dual

Objetivo:

Soportar coexistencia segura entre modo clásico y modo hidráulico.

Tareas:

- En SessionNotifier, ramificar por configuración:
  - Modo clásico: conservar lógica actual por sensor y debouncers.
  - Modo hidráulico: ignorar sensorInduc para transiciones y guardado.
- Integrar escucha de respuestas AT en SessionNotifier para detectar AT+GUARDAR.
- Al recibir AT+GUARDAR, calcular parcial con snapshot - peso actual y persistir con flujo actual.

Entregable:

- Motor de sesión con dos estrategias compatibles sin regresión.

### Fase 4 - Pantallas del modo hidráulico

Objetivo:

Implementar experiencia operativa específica para el nuevo modo.

Tareas:

- Crear variantes de carga/descarga del modo hidráulico.
- En esas pantallas, incorporar:
  - Botones manuales de movimiento (4 acciones).
  - Indicador persistente de toma de fuerza.
  - Indicador persistente de errorEcu.
- Mantener estilos consistentes con la app.

Entregable:

- Pantallas hidráulicas funcionales y aisladas del modo clásico.

### Fase 5 - Diálogo de inicio de descarga

Objetivo:

Implementar diálogo de parámetros de descarga para AT+INICIO.

Tareas:

- Crear diálogo con:
  - Velocidad (lenta, normal, rapida, variable)
  - Kg a descargar
  - Modo de descarga (una, dos, total, noria)
- Precargar valores persistidos.
- Validar reglas de kg.
- Enviar AT+INICIO con orden exacto de parámetros.

Entregable:

- Inicio de descarga comandado por AT+INICIO con validación de negocio.

### Fase 6 - Router y configuración de activación

Objetivo:

Activar el modo hidráulico de forma explícita desde configuración.

Tareas:

- Agregar sección de configuración en menú (solo BLE).
- Conmutar navegación en work shell entre vistas clásicas y vistas hidráulicas.

Entregable:

- Selección operativa del modo sin impacto en usuarios clásicos.

### Fase 7 - Localización y documentación

Objetivo:

Dejar el cambio completo en UX y documentación técnica.

Tareas:

- Agregar textos nuevos en app_es.arb y app_en.arb.
- Regenerar localizaciones.
- Documentar protocolo nuevo en PROTOCOLOS.md (sección propia al final).
- Actualizar manual técnico de conexión.

Entregable:

- Documentación y textos finalizados.

### Fase 8 - Validación y no regresión

Objetivo:

Verificar que el modo nuevo funciona y que el clásico no se rompe.

Tareas:

- Ejecutar análisis estático.
- Ejecutar tests existentes.
- Agregar pruebas de parser BLE y rama de sesión hidráulica.
- Pruebas manuales:
  - Clásico BLE/WiFi sin modo hidráulico.
  - Hidráulico BLE con modo activo.
  - Comandos de movimiento.
  - Guardado por AT+GUARDAR.
  - Variantes de JSON BLE con más o menos keys (incluyendo base histórico y base+keys nuevas).

Entregable:

- Evidencia de funcionamiento y regresión controlada.

## 7. Archivos principales a intervenir

- lib/domain/entities/app_config.dart
- lib/application/notifiers/app_config_notifier.dart
- lib/infrastructure/local/shared_prefs_app_config_repository.dart
- lib/domain/entities/weight_reading.dart
- lib/application/notifiers/session_notifier.dart
- lib/domain/entities/session_state.dart
- lib/infrastructure/ble/ble_weight_repository_blue_plus.dart
- lib/infrastructure/ble/ble_weight_repository.dart
- lib/presentation/screens/work/work_shell_page.dart
- lib/presentation/screens/carga/carga_page.dart (solo si se extraen componentes compartidos)
- lib/presentation/screens/descarga/descarga_page.dart (solo si se extraen componentes compartidos)
- lib/presentation/screens/menu/menu_page.dart
- lib/l10n/app_es.arb
- lib/l10n/app_en.arb
- PROTOCOLOS.md
- Manual_Tecnico_Conexion.md

## 8. Criterios de aceptación

- El modo clásico conserva exactamente su comportamiento actual.
- El modo hidráulico puede activarse/desactivarse por configuración BLE.
- AT+INICIO se envía con formato y orden acordado.
- AT+GUARDAR dispara guardado correcto con lógica de parcial actual.
- Una descarga iniciada en modo 2 cierra con AT+GUARDARDOS y la segunda, en
  modo 1, con AT+GUARDAR.
- El parser distingue AT+GUARDARDOS de AT+GUARDAR sin ambigüedad de prefijo.
- Los 4 comandos AT+MOVIMIENTO funcionan desde carga y descarga hidráulica.
- Toma de fuerza y errorEcu se muestran de forma persistente y clara.
- Documentación técnica del nuevo protocolo queda incluida.
- El parser BLE procesa correctamente payloads JSON con keys extra o faltantes opcionales, sin romper el flujo.
