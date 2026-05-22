import 'dart:math';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/material.dart';
import 'package:test_jaguar/application/services/simulator_orchestrator.dart';
import 'package:test_jaguar/application/use_cases/observe_simulator_status_use_case.dart';
import 'package:test_jaguar/application/use_cases/start_simulation_use_case.dart';
import 'package:test_jaguar/application/use_cases/stop_simulation_use_case.dart';
import 'package:test_jaguar/domain/services/linear_weight_interpolation_service.dart';
import 'package:test_jaguar/domain/services/simulation_domain_service.dart';
import 'package:test_jaguar/infrastructure/datasource/bluetooth_low_energy_ble_peripheral_datasource.dart';
import 'package:test_jaguar/infrastructure/repositories/ble_peripheral_repository_impl.dart';
import 'package:test_jaguar/infrastructure/repositories/scale_simulation_repository_impl.dart';
import 'package:test_jaguar/infrastructure/simulator/in_memory_scale_simulator_engine.dart';
import 'package:test_jaguar/presentation/controllers/simulator_controller.dart';
import 'package:test_jaguar/presentation/pages/simulator_page.dart';

class AppBootstrap {
  AppBootstrap._();

  static Future<void> run() async {
    final PeripheralManager peripheralManager = PeripheralManager();
    final BluetoothLowEnergyBlePeripheralDataSource bleDataSource =
      BluetoothLowEnergyBlePeripheralDataSource(manager: peripheralManager);
    final BlePeripheralRepositoryImpl bleRepository =
        BlePeripheralRepositoryImpl(bleDataSource);

    final SimulationDomainService simulationDomainService =
      const SimulationDomainService();
    final LinearWeightInterpolationService interpolationService =
      const LinearWeightInterpolationService();

    final InMemoryScaleSimulatorEngine simulatorEngine =
      InMemoryScaleSimulatorEngine(
        domainService: simulationDomainService,
        interpolationService: interpolationService,
        random: Random(),
      );
    final ScaleSimulationRepositoryImpl simulationRepository =
        ScaleSimulationRepositoryImpl(simulatorEngine);

    final SimulatorOrchestrator orchestrator = SimulatorOrchestrator(
      bleRepository: bleRepository,
      simulationRepository: simulationRepository,
    );

    final SimulatorController controller = SimulatorController(
      startSimulationUseCase: StartSimulationUseCase(orchestrator),
      stopSimulationUseCase: StopSimulationUseCase(orchestrator),
      observeStatusUseCase: ObserveSimulatorStatusUseCase(orchestrator),
    );

    runApp(_AppRoot(
      controller: controller,
      disposeAll: () async {
        controller.dispose();
        await orchestrator.dispose();
      },
    ));
  }
}

class _AppRoot extends StatefulWidget {
  const _AppRoot({
    required this.controller,
    required this.disposeAll,
  });

  final SimulatorController controller;
  final Future<void> Function() disposeAll;

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  @override
  void dispose() {
    widget.disposeAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Scale Simulator',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: SimulatorPage(controller: widget.controller),
    );
  }
}
