import 'package:flutter/material.dart';
import 'package:test_jaguar/domain/value_objects/hydraulic_actuator_position.dart';
import 'package:test_jaguar/domain/value_objects/hydraulic_discharge_command.dart';
import 'package:test_jaguar/domain/value_objects/hydraulic_movement_command.dart';
import 'package:test_jaguar/domain/value_objects/hydraulic_pto.dart';
import 'package:test_jaguar/presentation/controllers/simulator_controller.dart';
import 'package:test_jaguar/presentation/state/simulator_view_state.dart';
import 'package:test_jaguar/presentation/widgets/protocol_status_header.dart';
import 'package:test_jaguar/presentation/widgets/section_card.dart';

/// Pantalla dedicada al modo "Hidráulico BLE". A diferencia de los otros
/// protocolos (que sólo agregan una card dentro de la pantalla clásica),
/// acá el comportamiento a probar es distinto: hay que representar el
/// estado del tubo y la guillotina al recibir AT+MOVIMIENTO, además de
/// AT+INICIO y AT+GUARDAR. `SimulatorPage` actúa como router y muestra esta
/// pantalla completa cuando `sendProtocol == hidraulicoBle` (mismo patrón
/// que un `WorkShellPage` que rutea por estado).
class HydraulicSimulatorPage extends StatelessWidget {
  const HydraulicSimulatorPage({required this.controller, super.key});

  final SimulatorController controller;

  @override
  Widget build(BuildContext context) {
    final SimulatorViewState state = controller.state;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          children: <Widget>[
            Text(
              'Hidráulico BLE',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0B3D35),
                    letterSpacing: -0.6,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Control hidráulico de tubo y guillotina + AT+INICIO / AT+GUARDAR',
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
            const SizedBox(height: 4),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.icon(
                    onPressed:
                        state.running ? null : () => controller.startSimulation(),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Iniciar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        state.running ? () => controller.stopSimulation() : null,
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text('Detener'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _HydraulicDiagramCard(
              tuboPosicion: state.tuboPosicion,
              guillotinaPosicion: state.guillotinaPosicion,
              dischargeActive: state.hydraulicDischargeActive,
              dischargePaused: state.hydraulicDischargePaused,
            ),
            const SizedBox(height: 4),
            _HydraulicWeightCard(
              weight: state.weight,
              dischargeActive: state.hydraulicDischargeActive,
              dischargePaused: state.hydraulicDischargePaused,
              initialPeso: state.hydraulicInitialPeso,
              targetPeso: state.hydraulicTargetPeso,
              humidity: state.humidity,
              onHumidityChanged: controller.setHumidity,
              onWeightChanged: controller.setHydraulicPeso,
            ),
            const SizedBox(height: 4),
            SectionCard(
              title: 'Último AT+INICIO recibido',
              child: _InicioSummary(command: state.lastHydraulicInicio),
            ),
            const SizedBox(height: 4),
            SectionCard(
              title: 'Último AT+MOVIMIENTO recibido',
              child: _MovimientoSummary(command: state.lastHydraulicMovimiento),
            ),
            const SizedBox(height: 4),
            SectionCard(
              title: 'Controles del protocolo',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  DropdownButtonFormField<int>(
                    initialValue: state.tomaFuerza.clamp(
                      HydraulicPtoState.off,
                      HydraulicPtoState.requestOff,
                    ),
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'tomaFuerza',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    items: const <DropdownMenuItem<int>>[
                      DropdownMenuItem<int>(
                        value: HydraulicPtoState.off,
                        child: Text('0 - Apagada'),
                      ),
                      DropdownMenuItem<int>(
                        value: HydraulicPtoState.on,
                        child: Text('1 - Encendida'),
                      ),
                      DropdownMenuItem<int>(
                        value: HydraulicPtoState.requestOn,
                        child: Text('2 - Encienda toma de fuerza'),
                      ),
                      DropdownMenuItem<int>(
                        value: HydraulicPtoState.requestOff,
                        child: Text('3 - Apague toma de fuerza'),
                      ),
                    ],
                    onChanged: (int? value) {
                      if (value != null) {
                        controller.setTomaFuerza(value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  _PtoRpmField(
                    value: state.tomaFuerzaRpm,
                    ptoOn: HydraulicPtoState.isOn(state.tomaFuerza),
                    onChanged: controller.setTomaFuerzaRpm,
                  ),
                  const SizedBox(height: 12),
                  _ErrorEcuField(
                    value: state.errorEcu,
                    onChanged: controller.setErrorEcu,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed:
                        state.connected ? () => controller.sendGuardarEvent() : null,
                    icon: const Icon(Icons.save_alt_rounded),
                    label: const Text('Enviar AT+GUARDAR'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            SectionCard(
              title: 'Log de comandos recibidos',
              child: _CommandLog(logs: state.logs),
            ),
          ],
        ),
      ),
    );
  }
}

class _HydraulicDiagramCard extends StatelessWidget {
  const _HydraulicDiagramCard({
    required this.tuboPosicion,
    required this.guillotinaPosicion,
    required this.dischargeActive,
    required this.dischargePaused,
  });

  final int tuboPosicion;
  final int guillotinaPosicion;
  final bool dischargeActive;
  final bool dischargePaused;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Diagrama hidráulico (tolva → tubo → guillotina)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _ActuatorPositionBar(
            label: 'Tubo',
            icon: Icons.horizontal_rule_rounded,
            position: tuboPosicion,
          ),
          const SizedBox(height: 14),
          _ActuatorPositionBar(
            label: 'Guillotina',
            icon: Icons.vertical_align_bottom_rounded,
            position: guillotinaPosicion,
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Icon(
                dischargeActive
                    ? (dischargePaused
                        ? Icons.pause_circle_outline_rounded
                        : Icons.lock_rounded)
                    : Icons.tune_rounded,
                size: 16,
                color: const Color(0xFF3A5E56),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  dischargeActive
                      ? (dischargePaused
                          ? 'Descarga pausada por AT+DETENER: los '
                              'AT+MOVIMIENTO siguen ignorándose hasta '
                              'AT+REANUDAR'
                          : 'Descarga en curso: los AT+MOVIMIENTO de '
                              'abrir/cerrar se ignoran')
                      : 'Cada AT+MOVIMIENTO mueve un paso '
                          '(${HydraulicActuatorPosition.steps} pasos entre '
                          'cerrado y abierto)',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF3A5E56),
                      ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Barra gruesa que muestra en qué paso quedó el actuador entre los topes
/// "cerrado" y "abierto".
class _ActuatorPositionBar extends StatelessWidget {
  const _ActuatorPositionBar({
    required this.label,
    required this.icon,
    required this.position,
  });

  final String label;
  final IconData icon;
  final int position;

  static const Color _closedColor = Color(0xFFB3261E);
  static const Color _partialColor = Color(0xFFB26A00);
  static const Color _openColor = Color(0xFF1E8C74);

  @override
  Widget build(BuildContext context) {
    final int step = HydraulicActuatorPosition.clamp(position);
    final Color color;
    if (HydraulicActuatorPosition.isClosed(step)) {
      color = _closedColor;
    } else if (HydraulicActuatorPosition.isFullyOpen(step)) {
      color = _openColor;
    } else {
      color = _partialColor;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            const Spacer(),
            Text(
              '${HydraulicActuatorPosition.label(step)} '
              '($step/${HydraulicActuatorPosition.steps})',
              style: TextStyle(color: color, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.55), width: 1.4),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOut,
                  tween: Tween<double>(
                    end: HydraulicActuatorPosition.fraction(step),
                  ),
                  builder: (BuildContext context, double value, Widget? _) {
                    return FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: value,
                      child: ColoredBox(color: color),
                    );
                  },
                ),
              ),
              Positioned.fill(child: _StepTicks(filledSteps: step)),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              'Cerrado',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF3A5E56),
                  ),
            ),
            Text(
              'Abierto',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF3A5E56),
                  ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Divisiones internas de la barra: una por cada paso intermedio. Las que
/// caen sobre la parte ya recorrida se dibujan claras y el resto oscuras,
/// para que se lean sobre el relleno y sobre el fondo.
class _StepTicks extends StatelessWidget {
  const _StepTicks({required this.filledSteps});

  final int filledSteps;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List<Widget>.generate(
        HydraulicActuatorPosition.steps,
        (int index) {
          final bool isLast = index == HydraulicActuatorPosition.steps - 1;
          final bool overFill = index + 1 <= filledSteps;
          return Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: isLast
                  ? const SizedBox.shrink()
                  : SizedBox(
                      width: 1.5,
                      height: double.infinity,
                      child: ColoredBox(
                        color: overFill
                            ? Colors.white.withValues(alpha: 0.75)
                            : const Color(0xFF0B3D35).withValues(alpha: 0.22),
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }
}

class _HydraulicWeightCard extends StatelessWidget {
  const _HydraulicWeightCard({
    required this.weight,
    required this.dischargeActive,
    required this.dischargePaused,
    required this.initialPeso,
    required this.targetPeso,
    required this.humidity,
    required this.onHumidityChanged,
    required this.onWeightChanged,
  });

  final int weight;
  final bool dischargeActive;
  final bool dischargePaused;
  final double initialPeso;
  final double targetPeso;
  final double humidity;
  final ValueChanged<double> onHumidityChanged;
  final ValueChanged<int> onWeightChanged;

  @override
  Widget build(BuildContext context) {
    double? progress;
    if (dischargeActive && initialPeso != targetPeso) {
      progress = ((initialPeso - weight) / (initialPeso - targetPeso))
          .clamp(0.0, 1.0);
    }

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
          const SizedBox(height: 4),
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
              min: 0,
              max: 22000,
              divisions: 220,
              value: weight.toDouble().clamp(0, 22000),
              label: '$weight kg',
              onChanged: dischargeActive
                  ? null
                  : (double value) => onWeightChanged(value.round()),
            ),
          ),
          Text(
            dischargeActive
                ? (dischargePaused
                    ? 'Peso congelado: descarga pausada por AT+DETENER'
                    : 'El peso lo maneja la descarga en curso')
                : 'Peso editable (fijo hasta que llegue AT+INICIO)',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.75),
                ),
          ),
          const SizedBox(height: 10),
          if (dischargeActive) ...<Widget>[
            Text(
              dischargePaused
                  ? 'Descarga hidráulica pausada -> objetivo '
                      '${targetPeso.round()} kg (esperando AT+REANUDAR)'
                  : 'Descarga hidráulica en curso -> objetivo '
                      '${targetPeso.round()} kg',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: Colors.white.withValues(alpha: 0.26),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          ] else
            Text(
              'Sin descarga hidráulica en curso',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
            ),
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
        ],
      ),
    );
  }
}

class _InicioSummary extends StatelessWidget {
  const _InicioSummary({required this.command});

  final HydraulicDischargeCommand? command;

  @override
  Widget build(BuildContext context) {
    final HydraulicDischargeCommand? value = command;
    if (value == null) {
      return const Text('Sin comando recibido');
    }
    return Text(value.summary);
  }
}

class _MovimientoSummary extends StatelessWidget {
  const _MovimientoSummary({required this.command});

  final HydraulicMovementCommand? command;

  @override
  Widget build(BuildContext context) {
    final HydraulicMovementCommand? value = command;
    if (value == null) {
      return const Text('Sin comando recibido');
    }
    return Text('${value.label} (tipo=${value.tipo})');
  }
}

/// Slider de rpm simuladas de la toma de fuerza
/// (`HydraulicPtoRpm.min` - `HydraulicPtoRpm.max`). El valor se puede
/// configurar en cualquier estado, pero solo viaja en la key `rpm` del JSON
/// con la toma de fuerza encendida: en el resto se manda `rpm: 0`.
class _PtoRpmField extends StatelessWidget {
  const _PtoRpmField({
    required this.value,
    required this.ptoOn,
    required this.onChanged,
  });

  final int value;
  final bool ptoOn;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final int rpm = HydraulicPtoRpm.clamp(value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'rpm toma de fuerza: $rpm',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        Slider(
          min: HydraulicPtoRpm.min.toDouble(),
          max: HydraulicPtoRpm.max.toDouble(),
          divisions: (HydraulicPtoRpm.max - HydraulicPtoRpm.min) ~/
              HydraulicPtoRpm.step,
          value: rpm.toDouble(),
          label: '$rpm rpm',
          onChanged: (double next) => onChanged(next.round()),
        ),
        Text(
          ptoOn
              ? 'Toma de fuerza encendida: el JSON envía rpm: $rpm'
              : 'Toma de fuerza no encendida: el JSON envía rpm: 0',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _ErrorEcuField extends StatefulWidget {
  const _ErrorEcuField({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_ErrorEcuField> createState() => _ErrorEcuFieldState();
}

class _ErrorEcuFieldState extends State<_ErrorEcuField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode()..addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant _ErrorEcuField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_focusNode.hasFocus || widget.value == _controller.text) {
      return;
    }
    _controller.value = TextEditingValue(
      text: widget.value,
      selection: TextSelection.collapsed(offset: widget.value.length),
    );
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus) {
      widget.onChanged(_controller.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      decoration: const InputDecoration(
        labelText: 'errorEcu',
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => widget.onChanged(_controller.text),
    );
  }
}

class _CommandLog extends StatelessWidget {
  const _CommandLog({required this.logs});

  final List<String> logs;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final List<String> commandLogs = logs
        .where((String line) => line.startsWith('Comando recibido:'))
        .toList()
        .reversed
        .toList();

    if (commandLogs.isEmpty) {
      return const Text('Sin comandos recibidos por el momento');
    }

    return SizedBox(
      height: 220,
      child: ListView.separated(
        itemCount: commandLogs.length,
        separatorBuilder: (_, _) => const Divider(height: 10),
        itemBuilder: (BuildContext context, int index) {
          final String line = commandLogs[index];
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
    );
  }
}
