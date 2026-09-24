import 'package:flutter/material.dart';
import 'package:test_jaguar/presentation/controllers/simulator_controller.dart';
import 'package:test_jaguar/presentation/state/simulator_view_state.dart';
import 'package:test_jaguar/presentation/widgets/hero_weight_card.dart';
import 'package:test_jaguar/presentation/widgets/section_card.dart';
import 'package:test_jaguar/presentation/widgets/simulator_scaffold.dart';
import 'package:test_jaguar/protocols/st567/st567_screen.dart';
import 'package:test_jaguar/protocols/st567/st567_state.dart';

/// Pantalla del modo Remoto ST567: muestra en qué pantalla está el indicador
/// simulado y qué está haciendo, deja saltar a las pantallas que no necesitan
/// una corrida en curso y fija cómo responde a algunos comandos.
///
/// La navegación real la hace la app con sus `CTR,<comando>`; esto es para
/// forzar casos (un popup, un diálogo) sin tener que llegar a ellos.
class St567View extends StatelessWidget {
  const St567View({required this.controller, super.key});

  final SimulatorController controller;

  @override
  Widget build(BuildContext context) {
    final SimulatorViewState state = controller.state;
    final St567State st567 = state.st567;
    final St567Screen actual = st567.screen;
    final St567Options options = st567.options;

    return SimulatorScaffold(
      controller: controller,
      title: 'Jaguar BLE Scale',
      subtitle: 'Peripheral/GATT Server para pruebas',
      sections: <Widget>[
        const SizedBox(height: 8),
        SectionCard(
          title: 'Pantalla ST567',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Notificando: ${actual.label}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (st567.detalle.isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                Text(st567.detalle),
              ],
              const SizedBox(height: 4),
              Text(
                'Mixer: ${st567.totalCargado} kg · '
                'Operario: ${st567.operario.isEmpty ? '-' : st567.operario} · '
                'LevelLock: ${st567.levelLock ? 'ON' : 'OFF'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<St567Screen>(
                // initialValue sólo se lee al crear el campo; la key lo
                // recrea cuando la pantalla cambia sola (un popup que se
                // cierra, un comando de la app).
                key: ValueKey<St567Screen>(actual),
                // La pantalla actual puede no estar en la lista (las de peso
                // sólo se alcanzan con comandos), y el dropdown no acepta un
                // valor que no figure entre sus ítems.
                initialValue:
                    St567Screen.forzables.contains(actual) ? actual : null,
                isExpanded: true,
                hint: const Text('Ir a pantalla…'),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
                items: St567Screen.forzables
                    .map(
                      (St567Screen s) => DropdownMenuItem<St567Screen>(
                        value: s,
                        child: Text(s.label),
                      ),
                    )
                    .toList(),
                onChanged: (St567Screen? next) {
                  if (next != null) {
                    controller.selectSt567Screen(next);
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        SectionCard(
          title: 'Respuestas del indicador',
          child: Column(
            children: <Widget>[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Recetas con preset (firmware ≥ 1.36.3)'),
                subtitle: const Text('elegirReceta responde 60 en vez de 30'),
                value: options.recetasConPreset,
                onChanged: (bool v) => controller.setSt567Options(
                  options.copyWith(recetasConPreset: v),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('La sincronización falla'),
                subtitle: const Text('sync termina en 35 en vez de 36'),
                value: options.sincronizacionFalla,
                onChanged: (bool v) => controller.setSt567Options(
                  options.copyWith(sincronizacionFalla: v),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Sin trabajos cargados'),
                subtitle: const Text('elegirTrabajo responde el popup 20'),
                value: options.sinTrabajos,
                onChanged: (bool v) => controller.setSt567Options(
                  options.copyWith(sinTrabajos: v),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Indicador sin operario'),
                subtitle: const Text(
                  'elegir una receta o un trabajo responde el popup 16',
                ),
                value: options.sinOperario,
                onChanged: (bool v) => controller.setSt567Options(
                  options.copyWith(sinOperario: v),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        HeroWeightCard(
          weight: state.weight,
          footer: Text(
            'Protocolo ST567 (remoto): cabecera binaria de 5 bytes y cadena '
            'separada por coma, sobre el mismo perfil ABF3 que el ST407. En '
            'las pantallas de peso se muestra lo que falta cargar o '
            'descargar, como en la app.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.90),
                ),
          ),
        ),
      ],
    );
  }
}
