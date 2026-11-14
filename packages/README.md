# Paquetes parcheados

## bluetooth_low_energy_android 6.2.1

Copia de `bluetooth_low_energy_android` 6.2.1 (MIT, pub.dev), usada desde
`pubspec.yaml` con `dependency_overrides`. Cambios respecto del original:

- `PeripheralManagerImpl.setName` responde al instante si el adaptador ya tiene
  el nombre pedido.
- `pubspec.yaml`: `resolution: workspace` reemplazado por `publish_to: none`,
  porque fuera del monorepo original pub rechaza el paquete.

### Por qué

Antes de anunciar, el plugin llama a `BluetoothAdapter.setName` y espera el
broadcast `ACTION_LOCAL_NAME_CHANGED` para seguir, sin timeout. En la tablet
T10A (Android 16, Unisoc) ese broadcast sólo sale si el nombre cambia de
verdad. Como el simulador siempre pide `JaguarScaleSim`, sólo funcionaba el
primer arranque después de que el adaptador tuviera otro nombre: al reabrir la
app, al detener y volver a iniciar o al cambiar de perfil GATT,
`startAdvertising` quedaba esperando para siempre y no se anunciaba nada.

### Cuándo sacarlo

Cuando una versión publicada del plugin resuelva el caso, borrar esta carpeta y
el `dependency_overrides` de `pubspec.yaml`.
