import 'package:flutter/material.dart';
import 'package:test_jaguar/presentation/controllers/simulator_controller.dart';
import 'package:test_jaguar/presentation/state/simulator_view_state.dart';
import 'package:test_jaguar/presentation/widgets/hero_weight_card.dart';
import 'package:test_jaguar/presentation/widgets/section_card.dart';
import 'package:test_jaguar/presentation/widgets/simulator_scaffold.dart';
import 'package:test_jaguar/protocols/st567/st567_screen.dart';

/// Pantalla del modo Remoto ST567: muestra en qué pantalla está el indicador
/// simulado y deja saltar a las que no necesitan una corrida en curso.
class St567View extends StatelessWidget {
  const St567View({required this.controller, super.key});

  final SimulatorController controller;

  @override
  Widget build(BuildContext context) {
    final SimulatorViewState state = controller.state;
    final St567Screen actual = state.st567.screen;

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
        HeroWeightCard(
          weight: state.weight,
          footer: Text(
            'Protocolo ST567 (remoto): cabecera binaria de 5 bytes y cadena '
            'separada por coma, sobre el mismo perfil ABF3 que el ST407.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.90),
                ),
          ),
        ),
      ],
    );
  }
}
