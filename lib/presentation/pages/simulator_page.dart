import 'package:flutter/material.dart';
import 'package:test_jaguar/presentation/controllers/simulator_controller.dart';
import 'package:test_jaguar/presentation/widgets/status_tile.dart';

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
              StatusTile(label: 'BLE', value: state.bleEnabled ? 'ON' : 'OFF'),
              StatusTile(
                label: 'Advertising',
                value: state.advertising ? 'ACTIVO' : 'INACTIVO',
              ),
              StatusTile(
                label: 'Conexion',
                value: state.connected ? 'CONECTADO' : 'DESCONECTADO',
              ),
              StatusTile(label: 'UUID Service', value: state.serviceUuid),
              StatusTile(
                label: 'UUID Characteristic',
                value: state.characteristicUuid,
              ),
              StatusTile(label: 'Estado simulador', value: state.phaseName),
              StatusTile(label: 'Peso actual', value: '${state.weight}'),
              StatusTile(
                label: 'sensorInduc',
                value: '${state.sensorInduc}',
              ),
              const SizedBox(height: 16),
              Text('Ultimo JSON enviado',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SelectableText(state.lastJson),
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
              Text('Logs BLE', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...state.logs.take(20).map((line) => Text('- $line')),
            ],
          ),
        );
      },
    );
  }
}
