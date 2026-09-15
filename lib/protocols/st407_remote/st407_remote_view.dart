import 'package:flutter/material.dart';
import 'package:test_jaguar/presentation/controllers/simulator_controller.dart';
import 'package:test_jaguar/presentation/state/simulator_view_state.dart';
import 'package:test_jaguar/presentation/widgets/hero_weight_card.dart';
import 'package:test_jaguar/presentation/widgets/section_card.dart';
import 'package:test_jaguar/presentation/widgets/simulator_scaffold.dart';
import 'package:test_jaguar/protocols/st407_remote/st407_screen.dart';

/// Pantalla del modo Remoto ST407: se elige que pantalla del indicador simular
/// y el simulador notifica su cadena.
///
/// No muestra los chips de estado de balanza porque en este protocolo no viajan
/// esos campos: la trama es una cadena separada por coma, no el JSON.
class St407RemoteView extends StatelessWidget {
  const St407RemoteView({required this.controller, super.key});

  final SimulatorController controller;

  @override
  Widget build(BuildContext context) {
    final SimulatorViewState state = controller.state;

    return SimulatorScaffold(
      controller: controller,
      title: 'Jaguar BLE Scale',
      subtitle: 'Peripheral/GATT Server para pruebas',
      sections: <Widget>[
        const SizedBox(height: 8),
        SectionCard(
          title: 'Pantalla ST407',
          child: DropdownButtonFormField<St407Screen>(
            initialValue: state.st407Screen,
            isExpanded: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            items: St407Screen.values
                .map(
                  (St407Screen s) => DropdownMenuItem<St407Screen>(
                    value: s,
                    child: Text(s.label),
                  ),
                )
                .toList(),
            onChanged: (St407Screen? next) {
              if (next != null) {
                controller.selectSt407Screen(next);
              }
            },
          ),
        ),
        const SizedBox(height: 4),
        HeroWeightCard(
          weight: state.weight,
          footer: Text(
            'Protocolo ST407 (remoto): se envía una cabecera binaria de 5 '
            'bytes antes de la cadena, separada por coma.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.90),
                ),
          ),
        ),
      ],
    );
  }
}
