import 'package:flutter/material.dart';
import 'package:test_jaguar/domain/value_objects/send_protocol.dart';
import 'package:test_jaguar/presentation/controllers/simulator_controller.dart';
import 'package:test_jaguar/presentation/state/simulator_view_state.dart';
import 'package:test_jaguar/presentation/widgets/glow_circle.dart';
import 'package:test_jaguar/presentation/widgets/protocol_status_header.dart';
import 'package:test_jaguar/presentation/widgets/section_card.dart';

/// La pantalla común a los protocolos que mandan una balanza: fondo, selector
/// de protocolo, identificadores BLE, última trama enviada, botones de
/// simulación y log de comandos.
///
/// Cada protocolo aporta sólo lo suyo en [sections], que se insertan entre el
/// selector y el bloque de identificadores. El modo Hidráulico no usa este
/// scaffold: tiene una pantalla propia porque lo que hay que ver ahí es otra
/// cosa (el tubo y la guillotina).
class SimulatorScaffold extends StatelessWidget {
  const SimulatorScaffold({
    required this.controller,
    required this.title,
    required this.subtitle,
    required this.sections,
    super.key,
  });

  final SimulatorController controller;
  final String title;
  final String subtitle;

  /// Lo propio del protocolo activo.
  final List<Widget> sections;

  @override
  Widget build(BuildContext context) {
    final SimulatorViewState state = controller.state;
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
            child: GlowCircle(
              size: 220,
              color: const Color(0xFF1F8A70).withValues(alpha: 0.16),
            ),
          ),
          Positioned(
            top: 130,
            left: -70,
            child: GlowCircle(
              size: 180,
              color: const Color(0xFFBFE3C0).withValues(alpha: 0.30),
            ),
          ),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              children: <Widget>[
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0B3D35),
                        letterSpacing: -0.6,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
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
                ...sections,
                const SizedBox(height: 4),
                _BleIdentifiersCard(state: state),
                const SizedBox(height: 4),
                SectionCard(
                  title: state.sendProtocol == SendProtocol.st407Remote
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
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
                            separatorBuilder: (_, _) => const Divider(
                              height: 10,
                            ),
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

class _BleIdentifiersCard extends StatelessWidget {
  const _BleIdentifiersCard({required this.state});

  final SimulatorViewState state;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
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
                _kv('Characteristic UUID', state.characteristicUuid),
                const SizedBox(height: 8),
                _kv('Service WRITE UUID', state.serviceWriteUuid),
                const SizedBox(height: 8),
                _kv('Characteristic WRITE UUID', state.characteristicWriteUuid),
                const SizedBox(height: 8),
                _kv(
                  'Central activa',
                  state.connectedDeviceId ?? 'Sin central conectada',
                ),
              ],
            ),
          ],
        ),
      ),
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
