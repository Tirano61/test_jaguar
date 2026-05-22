import 'package:flutter/material.dart';
import 'package:test_jaguar/presentation/controllers/simulator_controller.dart';

class SimulatorPage extends StatelessWidget {
  const SimulatorPage({required this.controller, super.key});

  final SimulatorController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? child) {
        final state = controller.state;

        return Scaffold(
          appBar: AppBar(
            title: const Text('BLE Scale Peripheral Simulator'),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              _SectionCard(
                title: 'Estado BLE',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    _StateChip(
                      label: 'BLE',
                      active: state.bleEnabled,
                      activeText: 'ON',
                      inactiveText: 'OFF',
                    ),
                    _StateChip(
                      label: 'Advertising',
                      active: state.advertising,
                      activeText: 'ACTIVO',
                      inactiveText: 'INACTIVO',
                    ),
                    _StateChip(
                      label: 'Conexion',
                      active: state.connected,
                      activeText: 'CONECTADO',
                      inactiveText: 'DESCONECTADO',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: 'Identificadores BLE',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _kv('Service UUID', state.serviceUuid),
                    const SizedBox(height: 6),
                    _kv('Characteristic UUID', state.characteristicUuid),
                    const SizedBox(height: 6),
                    _kv(
                      'Central activa',
                      state.connectedDeviceId ?? 'Sin central conectada',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: 'Simulador',
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: _highlightMetric(
                        context,
                        label: 'Estado',
                        value: state.phaseName,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _highlightMetric(
                        context,
                        label: 'Peso',
                        value: '${state.weight}',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _highlightMetric(
                        context,
                        label: 'sensorInduc',
                        value: '${state.sensorInduc}',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Ultimo JSON enviado',
                child: SelectableText(
                  state.lastJson,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontFamily: 'monospace',
                      ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton(
                      onPressed: state.running
                          ? null
                          : () => controller.startSimulation(),
                      child: const Text('Iniciar simulacion'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: state.running
                          ? () => controller.stopSimulation()
                          : null,
                      child: const Text('Detener simulacion'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Historial BLE',
                child: state.logs.isEmpty
                    ? const Text('Sin eventos por el momento')
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: state.logs
                            .take(30)
                            .map(
                              (line) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Text('- $line'),
                              ),
                            )
                            .toList(),
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

  Widget _highlightMetric(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({
    required this.label,
    required this.active,
    required this.activeText,
    required this.inactiveText,
  });

  final String label;
  final bool active;
  final String activeText;
  final String inactiveText;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(
        active ? Icons.check_circle : Icons.cancel,
        size: 18,
        color: active ? scheme.primary : scheme.error,
      ),
      label: Text('$label: ${active ? activeText : inactiveText}'),
    );
  }
}
