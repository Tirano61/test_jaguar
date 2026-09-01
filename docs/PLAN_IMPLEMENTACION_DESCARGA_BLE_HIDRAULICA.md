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
- Muestra en pantalla estados de toma de fuerza y mensaje de error ECU.
- Ignora sensorInduc para transición de pantallas y guardado cuando el modo está activo.

## 4. Protocolo nuevo a soportar

### 4.1 Campos JSON adicionales

- tomaFuerza: int (0 apagada, 1 encendida, 2 encienda toma de fuerza, 3 apague toma de fuerza)
- errorEcu: string

### 4.2 Comando de inicio de descarga

AT+INICIO(<kgDescarga>,<kgTubo>,<kgPrecierre>,<modo>,<velocidad>)\r\n

Mapeos:

- modo: 1 una descarga, 2 dos descargas, 3 total, 4 noria
- velocidad: 1 lenta, 2 normal, 3 rapida, 4 variable

Validaciones:

- kgDescarga > kgTubo
- kgDescarga < peso actual en tolva

### 4.3 Evento de guardado

- Entrada por notify BLE: AT+GUARDAR
- Compatibilidad recomendada de parser: AT+GUARDAR, AT+GUARDAR() y variantes con espacios.

### 4.4 Movimiento manual

AT+MOVIMIENTO(<tipo>)\r\n

- 1 abrir tubo
- 2 cerrar tubo
- 3 abrir guillotina
- 4 cerrar guillotina

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
- Los 4 comandos AT+MOVIMIENTO funcionan desde carga y descarga hidráulica.
- Toma de fuerza y errorEcu se muestran de forma persistente y clara.
- Documentación técnica del nuevo protocolo queda incluida.
- El parser BLE procesa correctamente payloads JSON con keys extra o faltantes opcionales, sin romper el flujo.
