import 'dart:math';
import 'dart:async';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:test_jaguar/application/services/simulator_orchestrator.dart';
import 'package:test_jaguar/application/use_cases/observe_simulator_status_use_case.dart';
import 'package:test_jaguar/application/use_cases/set_humidity_use_case.dart';
import 'package:test_jaguar/application/use_cases/set_manual_measurement_use_case.dart';
import 'package:test_jaguar/application/use_cases/set_send_protocol_use_case.dart';
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
      setHumidityUseCase: SetHumidityUseCase(orchestrator),
      setSendProtocolUseCase: SetSendProtocolUseCase(orchestrator),
      setManualMeasurementUseCase: SetManualMeasurementUseCase(orchestrator),
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
  late final _LifecycleObserver _lifecycleObserver;

  @override
  void initState() {
    super.initState();
    _lifecycleObserver = _LifecycleObserver(onResume: _restoreBleIfNeeded);
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    unawaited(widget.disposeAll());
    super.dispose();
  }

  Future<void> _restoreBleIfNeeded() async {
    if (widget.controller.state.running &&
        !widget.controller.state.advertising) {
      await widget.controller.startSimulation();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF005B5E),
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: 'BLE Scale Simulator',
      theme: ThemeData(
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFFF2F6F5),
        textTheme: GoogleFonts.spaceGroteskTextTheme(),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: scheme.onSurface,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: scheme.onSurface,
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: const Color(0xFF005B5E).withValues(alpha: 0.08),
            ),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF005B5E),
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF005B5E),
            minimumSize: const Size.fromHeight(50),
            side: const BorderSide(color: Color(0xFF005B5E), width: 1.2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
      home: SimulatorPage(controller: widget.controller),
    );
  }
}

class _LifecycleObserver extends WidgetsBindingObserver {
  _LifecycleObserver({required this.onResume});

  final Future<void> Function() onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(onResume());
    }
  }
}
