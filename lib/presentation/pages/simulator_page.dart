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
        final ColorScheme scheme = Theme.of(context).colorScheme;

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
                      'Peripheral/GATT Server para pruebas industriales',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF3A5E56),
                          ),
                    ),
                    const SizedBox(height: 14),
                    _HeroWeightCard(
                      weight: state.weight,
                      phase: state.phaseName,
                      sensorInduc: state.sensorInduc,
                    ),
                    const SizedBox(height: 12),
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
                          const SizedBox(height: 8),
                          _kv('Characteristic UUID', state.characteristicUuid),
                          const SizedBox(height: 8),
                          _kv(
                            'Central activa',
                            state.connectedDeviceId ?? 'Sin central conectada',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SectionCard(
                      title: 'Ultimo JSON enviado',
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
                    const SizedBox(height: 16),
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
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 3,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Icon(
                                            Icons.bolt_rounded,
                                            size: 16,
                                            color: scheme.primary,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(child: Text(line)),
                                        ],
                                      ),
                                    ),
                                  )
                                  .toList(),
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
    required this.weight,
    required this.phase,
    required this.sensorInduc,
  });

  final int weight;
  final String phase;
  final int sensorInduc;

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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _HeroBadge(label: phase),
              _HeroBadge(label: 'sensorInduc: $sensorInduc'),
            ],
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
