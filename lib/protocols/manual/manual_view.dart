import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:test_jaguar/presentation/controllers/simulator_controller.dart';
import 'package:test_jaguar/presentation/state/simulator_view_state.dart';
import 'package:test_jaguar/presentation/widgets/hero_weight_card.dart';
import 'package:test_jaguar/presentation/widgets/section_card.dart';
import 'package:test_jaguar/presentation/widgets/simulator_scaffold.dart';

/// Pantalla del modo Manual: la balanza clasica mas los sliders que fijan cada
/// campo del JSON a mano.
class ManualView extends StatelessWidget {
  const ManualView({required this.controller, super.key});

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
            HeroBadge(label: 'sensorInduc: ${state.sensorInduc}'),
            HeroBadge(label: 'estable: ${state.estBalanza}'),
            if (state.weightHoldSecondsRemaining > 0)
              HeroBadge(
                label: 'Peso congelado: ${state.weightHoldSecondsRemaining}s',
              ),
          ],
          footer: Text(
            'Modo manual activo: el JSON se envia con los valores definidos '
            'abajo.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.90),
                ),
          ),
        ),
        const SizedBox(height: 8),
        _ManualPayloadCard(
          tara: state.manual.tara,
          taraMax: state.manualTaraMax,
          hold: state.manual.hold,
          vbat: state.manual.vbat,
          peso: state.manual.peso,
          pesoMax: state.manualWeightMax,
          estBalanza: state.manual.estBalanza,
          humedad: state.manual.humedad,
          sensorInduc: state.manual.sensorInduc,
          onTaraChanged: controller.setManualTara,
          onTaraMaxChanged: controller.setManualTaraMax,
          onHoldChanged: controller.setManualHold,
          onVbatChanged: controller.setManualVbat,
          onPesoChanged: controller.setManualWeight,
          onPesoMaxChanged: controller.setManualWeightMax,
          onEstBalanzaChanged: controller.setManualEstBalanza,
          onHumedadChanged: controller.setManualHumidity,
          onSensorInducChanged: controller.setManualSensorInduc,
        ),
      ],
    );
  }
}

class _ManualPayloadCard extends StatelessWidget {
  const _ManualPayloadCard({
    required this.tara,
    required this.taraMax,
    required this.hold,
    required this.vbat,
    required this.peso,
    required this.pesoMax,
    required this.estBalanza,
    required this.humedad,
    required this.sensorInduc,
    required this.onTaraChanged,
    required this.onTaraMaxChanged,
    required this.onHoldChanged,
    required this.onVbatChanged,
    required this.onPesoChanged,
    required this.onPesoMaxChanged,
    required this.onEstBalanzaChanged,
    required this.onHumedadChanged,
    required this.onSensorInducChanged,
  });

  final int tara;
  final int taraMax;
  final int hold;
  final double vbat;
  final int peso;
  final int pesoMax;
  final int estBalanza;
  final double humedad;
  final int sensorInduc;

  final ValueChanged<double> onTaraChanged;
  final ValueChanged<double> onTaraMaxChanged;
  final ValueChanged<double> onHoldChanged;
  final ValueChanged<double> onVbatChanged;
  final ValueChanged<double> onPesoChanged;
  final ValueChanged<double> onPesoMaxChanged;
  final ValueChanged<double> onEstBalanzaChanged;
  final ValueChanged<double> onHumedadChanged;
  final ValueChanged<double> onSensorInducChanged;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Payload manual',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _ManualSliderWithEditableMax(
            label: 'tara',
            valueLabel: '$tara',
            currentMax: taraMax.toDouble(),
            hardMax: 22000,
            value: tara.toDouble(),
            onChanged: onTaraChanged,
            onMaxChanged: onTaraMaxChanged,
          ),
          _ManualCompactControlsRow(
            hold: hold == 1,
            sensorInduc: sensorInduc == 1,
            estBalanza: estBalanza,
            onHoldChanged: (bool enabled) => onHoldChanged(enabled ? 1.0 : 0.0),
            onSensorInducChanged: (bool enabled) =>
                onSensorInducChanged(enabled ? 1.0 : 0.0),
            onEstBalanzaChanged: (int value) =>
                onEstBalanzaChanged(value.toDouble()),
          ),
          _ManualSliderWithEditableMax(
            label: 'peso',
            valueLabel: '$peso',
            currentMax: pesoMax.toDouble(),
            hardMax: 22000,
            value: peso.toDouble(),
            onChanged: onPesoChanged,
            onMaxChanged: onPesoMaxChanged,
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: _ManualSliderRow(
                  label: 'vbat',
                  valueLabel: vbat.toStringAsFixed(1),
                  min: 0,
                  max: 5,
                  divisions: 50,
                  value: vbat,
                  onChanged: onVbatChanged,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ManualSliderRow(
                  label: 'humedad',
                  valueLabel: humedad.toStringAsFixed(1),
                  min: 0,
                  max: 22,
                  divisions: 220,
                  value: humedad,
                  onChanged: onHumedadChanged,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ManualCompactControlsRow extends StatelessWidget {
  const _ManualCompactControlsRow({
    required this.hold,
    required this.sensorInduc,
    required this.estBalanza,
    required this.onHoldChanged,
    required this.onSensorInducChanged,
    required this.onEstBalanzaChanged,
  });

  final bool hold;
  final bool sensorInduc;
  final int estBalanza;
  final ValueChanged<bool> onHoldChanged;
  final ValueChanged<bool> onSensorInducChanged;
  final ValueChanged<int> onEstBalanzaChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Row(
              children: <Widget>[
                const Text('hold'),
                const SizedBox(width: 4),
                Switch(
                  value: hold,
                  onChanged: onHoldChanged,
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: <Widget>[
                const Text('sensorInduc'),
                const SizedBox(width: 4),
                Switch(
                  value: sensorInduc,
                  onChanged: onSensorInducChanged,
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: <Widget>[
                Text(
                  'estable',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: estBalanza.clamp(0, 5),
                    isExpanded: true,
                    isDense: true,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 12,
                        ),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    ),
                    items: List<DropdownMenuItem<int>>.generate(
                      6,
                      (int index) => DropdownMenuItem<int>(
                        value: index,
                        child: Text(
                          '$index',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontSize: 12,
                              ),
                        ),
                      ),
                    ),
                    onChanged: (int? value) {
                      if (value != null) {
                        onEstBalanzaChanged(value);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ManualSliderRow extends StatelessWidget {
  const _ManualSliderRow({
    required this.label,
    required this.valueLabel,
    required this.min,
    required this.max,
    required this.divisions,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String valueLabel;
  final double min;
  final double max;
  final int divisions;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '$label: $valueLabel',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          Slider(
            min: min,
            max: max,
            divisions: divisions,
            value: value.clamp(min, max),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _ManualSliderWithEditableMax extends StatefulWidget {
  const _ManualSliderWithEditableMax({
    required this.label,
    required this.valueLabel,
    required this.currentMax,
    required this.hardMax,
    required this.value,
    required this.onChanged,
    required this.onMaxChanged,
  });

  final String label;
  final String valueLabel;
  final double currentMax;
  final double hardMax;
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onMaxChanged;

  @override
  State<_ManualSliderWithEditableMax> createState() =>
      _ManualSliderWithEditableMaxState();
}

class _ManualSliderWithEditableMaxState
    extends State<_ManualSliderWithEditableMax> {
  late final TextEditingController _maxController;
  late final FocusNode _maxFocusNode;
  late double _currentMax;

  @override
  void initState() {
    super.initState();
    _currentMax = widget.currentMax.clamp(1, widget.hardMax);
    _maxController = TextEditingController(
      text: _currentMax.round().toString(),
    );
    _maxFocusNode = FocusNode()..addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant _ManualSliderWithEditableMax oldWidget) {
    super.didUpdateWidget(oldWidget);
    final double nextMax = widget.currentMax.clamp(1, widget.hardMax);
    if (_maxFocusNode.hasFocus || nextMax == _currentMax) {
      return;
    }

    _currentMax = nextMax;
    final String normalizedText = _currentMax.round().toString();
    _maxController.value = TextEditingValue(
      text: normalizedText,
      selection: TextSelection.collapsed(offset: normalizedText.length),
    );
  }

  @override
  void dispose() {
    _maxFocusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    _maxController.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!_maxFocusNode.hasFocus) {
      _applyMaxValue();
    }
  }

  void _applyMaxValue() {
    final int? parsed = int.tryParse(_maxController.text);
    final double nextMax = (parsed ?? _currentMax.round())
        .clamp(1, widget.hardMax.toInt())
        .toDouble();

    if (nextMax != _currentMax) {
      setState(() {
        _currentMax = nextMax;
      });
    }

    final String normalizedText = nextMax.round().toString();
    if (_maxController.text != normalizedText) {
      _maxController.value = TextEditingValue(
        text: normalizedText,
        selection: TextSelection.collapsed(offset: normalizedText.length),
      );
    }

    widget.onMaxChanged(nextMax);

    final double clampedValue = widget.value.clamp(0, _currentMax);
    if (clampedValue != widget.value) {
      widget.onChanged(clampedValue);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: Text(
                  '${widget.label}: ${widget.valueLabel}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 96,
                child: TextField(
                  controller: _maxController,
                  focusNode: _maxFocusNode,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        height: 1.1,
                      ),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: InputDecoration(
                    labelText: 'Max',
                    labelStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                        ),
                    isDense: true,
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                  ),
                  onSubmitted: (_) => _applyMaxValue(),
                ),
              ),
            ],
          ),
          Slider(
            min: 0,
            max: _currentMax,
            divisions: _currentMax.round(),
            value: widget.value.clamp(0, _currentMax),
            onChanged: widget.onChanged,
          ),
        ],
      ),
    );
  }
}