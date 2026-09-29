import 'package:flutter/material.dart';
import 'package:test_jaguar/presentation/controllers/simulator_controller.dart';
import 'package:test_jaguar/presentation/state/simulator_view_state.dart';
import 'package:test_jaguar/presentation/widgets/hero_weight_card.dart';
import 'package:test_jaguar/presentation/widgets/section_card.dart';
import 'package:test_jaguar/presentation/widgets/simulator_scaffold.dart';
import 'package:test_jaguar/protocols/st456web/st456web_screen.dart';
import 'package:test_jaguar/protocols/st456web/st456web_state.dart';

/// Pantalla del modo Remoto ST456web: muestra en qué pantalla está el
/// indicador simulado y deja saltar a las que no necesitan una corrida en
/// curso.
///
/// La navegación real la hace la app con sus `CTR,<comando>`; esto es para
/// forzar casos (un popup, un diálogo) sin tener que llegar a ellos.
class St456webView extends StatelessWidget {
  const St456webView({required this.controller, super.key});

  final SimulatorController controller;

  @override
  Widget build(BuildContext context) {
    final SimulatorViewState state = controller.state;
    final St456webState st456web = state.st456web;
    final St456webScreen actual = st456web.screen;

    return SimulatorScaffold(
      controller: controller,
      title: 'Jaguar BLE Scale',
      subtitle: 'Peripheral/GATT Server para pruebas',
      sections: <Widget>[
        const SizedBox(height: 8),
        SectionCard(
          title: 'Pantalla ST456web',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Notificando: ${actual.label}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<St456webScreen>(
                // initialValue sólo se lee al crear el campo; la key lo
                // recrea cuando la pantalla cambia sola (un popup que se
                // cierra, un comando de la app).
                key: ValueKey<St456webScreen>(actual),
                // La pantalla actual puede no estar en la lista (las de peso
                // sólo se alcanzan con comandos), y el dropdown no acepta un
                // valor que no figure entre sus ítems.
                initialValue:
                    St456webScreen.forzables.contains(actual) ? actual : null,
                isExpanded: true,
                hint: const Text('Ir a pantalla…'),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
                items: St456webScreen.forzables
                    .map(
                      (St456webScreen s) => DropdownMenuItem<St456webScreen>(
                        value: s,
                        child: Text(s.label),
                      ),
                    )
                    .toList(),
                onChanged: (St456webScreen? next) {
                  if (next != null) {
                    controller.selectSt456webScreen(next);
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
            'Protocolo ST456web (remoto): cabecera binaria de 5 bytes y cadena '
            'separada por coma, sobre el mismo perfil ABF3 que el ST407 y el '
            'ST567.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.90),
                ),
          ),
        ),
      ],
    );
  }
}
