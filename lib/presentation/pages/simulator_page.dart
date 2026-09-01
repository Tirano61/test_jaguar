import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:test_jaguar/domain/value_objects/send_protocol.dart';
import 'package:test_jaguar/domain/value_objects/st456_screen.dart';
import 'package:test_jaguar/presentation/controllers/simulator_controller.dart';
import 'package:test_jaguar/presentation/pages/hydraulic_simulator_page.dart';
import 'package:test_jaguar/presentation/widgets/protocol_status_header.dart';
import 'package:test_jaguar/presentation/widgets/section_card.dart';

class SimulatorPage extends StatelessWidget {
  const SimulatorPage({required this.controller, super.key});

  final SimulatorController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? child) {
        final state = controller.state;

        if (state.sendProtocol == SendProtocol.hidraulicoBle) {
          return HydraulicSimulatorPage(controller: controller);
        }

        final ColorScheme scheme = Theme.of(context).colorScheme;
        final List<String> commandLogs = state.logs
            .where((String line) => line.startsWith('Comando recibido:'))
            .toList()
            .reversed
            .toList();

        return Scaffold(
          body: Stack(
            children: <Widget>[
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        const Color(0xFFE8F6F4),
                        const Color(0xFFF9FCFB),
                        const Color(0xFFEFF7F0),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: -90,
                right: -40,
                child: _GlowCircle(
                  size: 220,
                  color: const Color(0xFF1F8A70).withValues(alpha: 0.16),
                ),
              ),
              Positioned(
                top: 130,
                left: -70,
                child: _GlowCircle(
                  size: 180,
                  color: const Color(0xFFBFE3C0).withValues(alpha: 0.30),
                ),
              ),
              SafeArea(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  children: <Widget>[
                    Text(
                      'Jaguar BLE Scale',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0B3D35),
                            letterSpacing: -0.6,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Peripheral/GATT Server para pruebas',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF3A5E56),
                          ),
                    ),
                    const SizedBox(height: 4),
                    ProtocolStatusHeader(
                      sendProtocol: state.sendProtocol,
                      onProtocolChanged: controller.selectSendProtocol,
                      bleEnabled: state.bleEnabled,
                      advertising: state.advertising,
                      connected: state.connected,
                    ),
                    if (state.sendProtocol == SendProtocol.st456Remote) ...<Widget>[
                      const SizedBox(height: 8),
                      SectionCard(
                        title: 'Pantalla ST456',
                        child: DropdownButtonFormField<St456Screen>(
                          initialValue: state.st456Screen,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding:
                                EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          ),
                          items: St456Screen.values
                              .map(
                                (St456Screen s) => DropdownMenuItem<St456Screen>(
                                  value: s,
                                  child: Text(s.label),
                                ),
                              )
                              .toList(),
                          onChanged: (St456Screen? next) {
                            if (next != null) {
                              controller.selectSt456Screen(next);
                            }
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    _HeroWeightCard(
                      sendProtocol: state.sendProtocol,
                      weight: state.weight,
                      phase: state.phaseName,
                      sensorInduc: state.sensorInduc,
                      estBalanza: state.estBalanza,
                      weightHoldSecondsRemaining:
                          state.weightHoldSecondsRemaining,
                      humidity: state.humidity,
                      onHumidityChanged: controller.setHumidity,
                    ),
                    if (state.sendProtocol == SendProtocol.manual) ...<Widget>[
                      const SizedBox(height: 8),
                      _ManualPayloadCard(
                        tara: state.manualTara,
                        taraMax: state.manualTaraMax,
                        hold: state.manualHold,
                        vbat: state.manualVbat,
                        peso: state.manualWeight,
                        pesoMax: state.manualWeightMax,
                        estBalanza: state.manualEstBalanza,
                        humedad: state.manualHumidity,
                        sensorInduc: state.manualSensorInduc,
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
                    const SizedBox(height: 4),
                    Card(
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          dividerColor: Colors.transparent,
                        ),
                        child: ExpansionTile(
                          tilePadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 2,
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            12,
                            0,
                            12,
                            12,
                          ),
                          title: Text(
                            'Identificadores BLE',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          children: <Widget>[
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                _kv('Service UUID', state.serviceUuid),
                                const SizedBox(height: 8),
                                _kv(
                                  'Characteristic UUID',
                                  state.characteristicUuid,
                                ),
                                const SizedBox(height: 8),
                                _kv('Service WRITE UUID', state.serviceWriteUuid),
                                const SizedBox(height: 8),
                                _kv(
                                  'Characteristic WRITE UUID',
                                  state.characteristicWriteUuid,
                                ),
                                const SizedBox(height: 8),
                                _kv(
                                  'Central activa',
                                  state.connectedDeviceId ??
                                      'Sin central conectada',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SectionCard(
                      title: state.sendProtocol == SendProtocol.st456Remote
                          ? 'Ultima cadena enviada'
                          : 'Ultimo JSON enviado',
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: const Color(0xFF103A34),
                        ),
                        child: SelectableText(
                          state.lastJson,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontFamily: 'monospace',
                                    color: const Color(0xFFE8FFF5),
                                  ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: state.running
                                ? null
                                : () => controller.startSimulation(),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('Iniciar'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: state.running
                                ? () => controller.stopSimulation()
                                : null,
                            icon: const Icon(Icons.stop_rounded),
                            label: const Text('Detener'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SectionCard(
                      title: 'Log de comandos recibidos',
                      child: commandLogs.isEmpty
                          ? const Text('Sin comandos recibidos por el momento')
                          : SizedBox(
                              height: 220,
                              child: ListView.separated(
                                itemCount: commandLogs.length,
                                separatorBuilder: (_, __) => const Divider(
                                  height: 10,
                                ),
                                itemBuilder: (BuildContext context, int index) {
                                  final String line = commandLogs[index];
                                  return Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Icon(
                                        Icons.keyboard_command_key_rounded,
                                        size: 16,
                                        color: scheme.primary,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(child: Text(line)),
                                    ],
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _kv(String key, String value) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(color: Colors.black87),
        children: <InlineSpan>[
          TextSpan(
            text: '$key: ',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }

}

class _GlowCircle extends StatelessWidget {
  const _GlowCircle({
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}

class _HeroWeightCard extends StatelessWidget {
  const _HeroWeightCard({
    required this.sendProtocol,
    required this.weight,
    required this.phase,
    required this.sensorInduc,
    required this.estBalanza,
    required this.weightHoldSecondsRemaining,
    required this.humidity,
    required this.onHumidityChanged,
  });

  final SendProtocol sendProtocol;
  final int weight;
  final String phase;
  final int sensorInduc;
  final int estBalanza;
  final int weightHoldSecondsRemaining;
  final double humidity;
  final ValueChanged<double> onHumidityChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF0D5A5D), Color(0xFF1E8C74)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF1E8C74).withValues(alpha: 0.34),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Peso actual',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.85),
                  letterSpacing: 0.6,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            '$weight kg',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                ),
          ),
          const SizedBox(height: 10),
          // Para protocolo ST456 remoto no mostramos los chips de estado;
          // en su lugar mostramos una aclaración sobre la cabecera binaria.
          if (sendProtocol != SendProtocol.st456Remote)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                if (sendProtocol != SendProtocol.manual)
                  _HeroBadge(label: phase),
                _HeroBadge(label: 'sensorInduc: $sensorInduc'),
                _HeroBadge(label: 'estable: $estBalanza'),
                if (weightHoldSecondsRemaining > 0)
                  _HeroBadge(
                    label: 'Peso congelado: ${weightHoldSecondsRemaining}s',
                  ),
              ],
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 6.0),
              child: Text(
                'Protocolo ST456 (remoto): se envía una cabecera binaria de 5 bytes antes de la cadena, separada por coma.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.90),
                    ),
              ),
            ),
          if (sendProtocol == SendProtocol.jaguarBle) ...<Widget>[
            const SizedBox(height: 12),
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
                  onHumidityChanged(double.parse(value.toStringAsFixed(1)));
                },
              ),
            ),
          ] else if (sendProtocol == SendProtocol.st456Remote) ...<Widget>[
            const SizedBox(height: 8),
            // Ya mostramos la aclaración arriba, mantener separación visual
          ] else ...<Widget>[
            const SizedBox(height: 12),
            Text(
              'Modo manual activo: el JSON se envia con los valores definidos abajo.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.90),
                  ),
            ),
          ],
        ],
      ),
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
                    value: estBalanza.clamp(0, 5),
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

class _HeroBadge extends StatelessWidget {
  const _HeroBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

