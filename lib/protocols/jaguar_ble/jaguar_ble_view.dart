import 'package:flutter/material.dart';
import 'package:test_jaguar/presentation/controllers/simulator_controller.dart';
import 'package:test_jaguar/presentation/state/simulator_view_state.dart';
import 'package:test_jaguar/presentation/widgets/hero_weight_card.dart';
import 'package:test_jaguar/presentation/widgets/simulator_scaffold.dart';

/// Pantalla del modo Jaguar BLE: el peso lo genera el motor de simulacion, asi
/// que lo unico configurable es la humedad.
class JaguarBleView extends StatelessWidget {
  const JaguarBleView({required this.controller, super.key});

  final SimulatorController controller;

  @override
  Widget build(BuildContext context) {
    final SimulatorViewState state = controller.state;

    return SimulatorScaffold(
      controller: controller,
      title: 'Jaguar BLE Scale',
      subtitle: 'Peripheral/GATT Server para pruebas',
      sections: <Widget>[
        const SizedBox(height: 4),
        HeroWeightCard(
          weight: state.weight,
          badges: <Widget>[
            HeroBadge(label: state.phaseName),
            HeroBadge(label: 'sensorInduc: ${state.sensorInduc}'),
            HeroBadge(label: 'estable: ${state.estBalanza}'),
            if (state.weightHoldSecondsRemaining > 0)
              HeroBadge(
                label: 'Peso congelado: ${state.weightHoldSecondsRemaining}s',
              ),
          ],
          footer: _HumiditySlider(
            humidity: state.humidity,
            onChanged: controller.setHumidity,
          ),
        ),
      ],
    );
  }
}

class _HumiditySlider extends StatelessWidget {
  const _HumiditySlider({required this.humidity, required this.onChanged});

  final double humidity;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Humedad enviada: ${humidity.toStringAsFixed(1)}',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.white.withValues(alpha: 0.92),
                fontWeight: FontWeight.w700,
              ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.26),
            thumbColor: const Color(0xFF0D5A5D),
            overlayColor: Colors.white.withValues(alpha: 0.16),
            valueIndicatorColor: Colors.white,
            valueIndicatorTextStyle: const TextStyle(
              color: Color(0xFF0D5A5D),
              fontWeight: FontWeight.w700,
            ),
          ),
          child: Slider(
            min: 0.0,
            max: 22.0,
            divisions: 220,
            value: humidity.clamp(0.0, 22.0),
            label: humidity.toStringAsFixed(1),
            onChanged: (double value) {
              onChanged(double.parse(value.toStringAsFixed(1)));
            },
          ),
        ),
      ],
    );
  }
}
