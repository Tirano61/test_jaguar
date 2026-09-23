import 'package:flutter/material.dart';
import 'package:test_jaguar/domain/value_objects/send_protocol.dart';
import 'package:test_jaguar/presentation/controllers/simulator_controller.dart';
import 'package:test_jaguar/protocols/hidraulico_ble/hydraulic_view.dart';
import 'package:test_jaguar/protocols/jaguar_ble/jaguar_ble_view.dart';
import 'package:test_jaguar/protocols/manual/manual_view.dart';
import 'package:test_jaguar/protocols/st407_remote/st407_remote_view.dart';
import 'package:test_jaguar/protocols/st567/st567_view.dart';

/// Rutea a la pantalla del protocolo seleccionado.
///
/// El `switch` es exhaustivo sobre `SendProtocol`, asi que agregar un protocolo
/// al enum no compila hasta que tenga su vista: es el mismo chequeo que hace
/// `protocol_registry_test.dart` del lado de la logica.
///
/// Se vuelve de una pantalla a otra con el selector del encabezado, que todas
/// comparten; no hay navegacion con boton atras.
class SimulatorPage extends StatelessWidget {
  const SimulatorPage({required this.controller, super.key});

  final SimulatorController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? child) {
        switch (controller.state.sendProtocol) {
          case SendProtocol.jaguarBle:
            return JaguarBleView(controller: controller);
          case SendProtocol.st407Remote:
            return St407RemoteView(controller: controller);
          case SendProtocol.manual:
            return ManualView(controller: controller);
          case SendProtocol.hidraulicoBle:
            return HydraulicView(controller: controller);
          case SendProtocol.st567:
            return St567View(controller: controller);
        }
      },
    );
  }
}
