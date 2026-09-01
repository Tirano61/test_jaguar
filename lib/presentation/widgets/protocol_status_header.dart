import 'package:flutter/material.dart';
import 'package:test_jaguar/domain/value_objects/send_protocol.dart';
import 'package:test_jaguar/presentation/widgets/section_card.dart';

/// Bloque superior compartido por todas las pantallas del simulador:
/// selector de protocolo de envío + chips de estado BLE. Cambiar de
/// protocolo desde acá es la forma de "volver" desde una pantalla dedicada
/// (como `HydraulicSimulatorPage`) al modo clásico, sin necesitar
/// navegación con botón atrás.
class ProtocolStatusHeader extends StatelessWidget {
  const ProtocolStatusHeader({
    required this.sendProtocol,
    required this.onProtocolChanged,
    required this.bleEnabled,
    required this.advertising,
    required this.connected,
    super.key,
  });

  final SendProtocol sendProtocol;
  final ValueChanged<SendProtocol> onProtocolChanged;
  final bool bleEnabled;
  final bool advertising;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionCard(
          title: 'Protocolo de envio',
          child: SegmentedButton<SendProtocol>(
            segments: SendProtocol.values
                .map(
                  (SendProtocol protocol) => ButtonSegment<SendProtocol>(
                    value: protocol,
                    label: Text(protocol.label),
                  ),
                )
                .toList(),
            selected: <SendProtocol>{sendProtocol},
            onSelectionChanged: (Set<SendProtocol> selection) {
              if (selection.isEmpty) {
                return;
              }
              onProtocolChanged(selection.first);
            },
          ),
        ),
        const SizedBox(height: 4),
        SectionCard(
          title: 'Estado BLE',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _StateChip(
                label: 'BLE',
                active: bleEnabled,
                activeText: 'ON',
                inactiveText: 'OFF',
              ),
              _StateChip(
                label: 'Advertising',
                active: advertising,
                activeText: 'ACTIVO',
                inactiveText: 'INACTIVO',
              ),
              _StateChip(
                label: 'Conexion',
                active: connected,
                activeText: 'CONECTADO',
                inactiveText: 'DESCONECTADO',
              ),
            ],
          ),
        ),
      ],
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
