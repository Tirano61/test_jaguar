import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:test_jaguar/application/dto/simulator_status_dto.dart';
import 'package:test_jaguar/application/services/simulator_orchestrator.dart';
import 'package:test_jaguar/core/constants/ble_constants.dart';
import 'package:test_jaguar/domain/entities/ble_peripheral_status.dart';
import 'package:test_jaguar/domain/entities/scale_measurement.dart';
import 'package:test_jaguar/domain/repositories/ble_peripheral_repository.dart';
import 'package:test_jaguar/domain/repositories/scale_simulation_repository.dart';
import 'package:test_jaguar/domain/value_objects/send_protocol.dart';
import 'package:test_jaguar/domain/value_objects/simulation_phase.dart';

class _FakeBleRepository implements BlePeripheralRepository {
  final StreamController<BlePeripheralStatus> _statusController =
      StreamController<BlePeripheralStatus>.broadcast();

  final List<String> notifiedPayloads = <String>[];
  int _sequence = 0;

  /// Simula un characteristic write de la app conectada: cada comando va con
  /// su propio commandSequence, que es lo que el orquestador usa para no
  /// reprocesar el mismo write dos veces.
  void receiveCommand(String command) {
    _sequence++;
    _statusController.add(
      BlePeripheralStatus.initial.copyWith(
        advertising: true,
        connected: true,
        lastReceivedCommand: command,
        commandSequence: _sequence,
      ),
    );
  }

  @override
  Stream<BlePeripheralStatus> watchStatus() => _statusController.stream;

  @override
  Future<void> startAdvertising() async {}

  @override
  Future<void> stopAdvertising() async {}

  @override
  Future<void> updateBleUuids(BleUuids uuids) async {}

  @override
  Future<void> notifyUtf8Json(String payload) async {
    notifiedPayloads.add(payload);
  }

  @override
  Future<void> dispose() async {
    await _statusController.close();
  }
}

class _FakeSimulationRepository implements ScaleSimulationRepository {
  final StreamController<bool> _runningController =
      StreamController<bool>.broadcast();
  final StreamController<SimulationPhase> _phaseController =
      StreamController<SimulationPhase>.broadcast();
  final StreamController<ScaleMeasurement> _measurementController =
      StreamController<ScaleMeasurement>.broadcast();

  /// Un tick del motor de simulación: es lo único que hace bajar el peso
  /// durante una descarga hidráulica. Con la simulación detenida no hay ticks.
  void tick() => _measurementController.add(ScaleMeasurement.baseline);

  @override
  Stream<bool> watchRunning() => _runningController.stream;

  @override
  Stream<SimulationPhase> watchPhase() => _phaseController.stream;

  @override
  Stream<ScaleMeasurement> watchMeasurements() => _measurementController.stream;

  @override
  Future<void> start() async => _runningController.add(true);

  @override
  Future<void> stop() async => _runningController.add(false);

  @override
  Future<void> dispose() async {
    await _runningController.close();
    await _phaseController.close();
    await _measurementController.close();
  }
}

class _Harness {
  _Harness() {
    orchestrator = SimulatorOrchestrator(
      bleRepository: ble,
      simulationRepository: simulation,
    );
    _subscription = orchestrator.watchStatus().listen((SimulatorStatusDto s) {
      latest = s;
    });
  }

  final _FakeBleRepository ble = _FakeBleRepository();
  final _FakeSimulationRepository simulation = _FakeSimulationRepository();
  late final SimulatorOrchestrator orchestrator;
  late final StreamSubscription<SimulatorStatusDto> _subscription;

  SimulatorStatusDto latest = SimulatorStatusDto.initial;

  int get pesoEnJson =>
      (jsonDecode(latest.lastJson) as Map<String, dynamic>)['peso'] as int;

  Future<void> receive(String command) async {
    ble.receiveCommand(command);
    await pumpEventQueue();
  }

  Future<void> tick() async {
    simulation.tick();
    await pumpEventQueue();
  }

  Future<void> dispose() async {
    await _subscription.cancel();
    await orchestrator.dispose();
  }
}

/// Simulador en modo Hidráulico BLE con [peso] kg en la tolva y la simulación
/// detenida (que es como queda al abrir la app).
Future<_Harness> _hydraulicHarness({required int peso}) async {
  final _Harness harness = _Harness();
  addTearDown(harness.dispose);
  await harness.orchestrator.setSendProtocol(SendProtocol.hidraulicoBle);
  await harness.orchestrator.setHydraulicPeso(peso);
  // watchStatus() es un broadcast stream: entrega en microtask, así que el
  // harness no puede devolverse con emisiones todavía en vuelo.
  await pumpEventQueue();
  return harness;
}

void main() {
  test('el peso editado a mano viaja en el JSON sin esperar un tick', () async {
    final _Harness harness = await _hydraulicHarness(peso: 1500);

    expect(harness.pesoEnJson, 1500);
    expect(harness.latest.measurement.peso, 1500);
  });

  test('AT+INICIO por todo el peso de la tolva inicia la descarga', () async {
    final _Harness harness = await _hydraulicHarness(peso: 1500);

    await harness.receive('AT+INICIO=1500,300,100,3,2\r\n');

    expect(harness.latest.hydraulicDischargeActive, isTrue);
    expect(harness.latest.hydraulicInitialPeso, 1500.0);
    expect(harness.latest.hydraulicTargetPeso, 0.0);
  });

  test('AT+INICIO por más kg de los cargados se rechaza', () async {
    final _Harness harness = await _hydraulicHarness(peso: 1500);

    await harness.receive('AT+INICIO=1501,300,100,3,2\r\n');

    expect(harness.latest.hydraulicDischargeActive, isFalse);
    expect(harness.latest.logs.first, contains('parámetros inválidos'));
  });

  test('AT+INICIO con kgDescarga <= kgTubo se rechaza', () async {
    final _Harness harness = await _hydraulicHarness(peso: 1500);

    await harness.receive('AT+INICIO=300,300,100,3,2\r\n');

    expect(harness.latest.hydraulicDischargeActive, isFalse);
    expect(harness.latest.logs.first, contains('parámetros inválidos'));
  });

  test('la descarga total vacía la tolva y cierra con AT+GUARDAR', () async {
    final _Harness harness = await _hydraulicHarness(peso: 1500);
    await harness.receive('AT+INICIO=1500,300,100,3,2\r\n');

    // Velocidad 2 (normal) baja 50 kg por tick: 1500 kg son 30 ticks.
    for (int i = 0; i < 40 && harness.latest.hydraulicDischargeActive; i++) {
      await harness.tick();
    }

    expect(harness.latest.hydraulicDischargeActive, isFalse);
    expect(harness.pesoEnJson, 0);
    expect(harness.ble.notifiedPayloads.last, 'AT+GUARDAR\r\n');
  });

  test('la descarga en modo 2 cierra con AT+GUARDARDOS', () async {
    final _Harness harness = await _hydraulicHarness(peso: 1500);
    await harness.receive('AT+INICIO=1500,300,100,2,2\r\n');

    for (int i = 0; i < 40 && harness.latest.hydraulicDischargeActive; i++) {
      await harness.tick();
    }

    expect(harness.ble.notifiedPayloads.last, 'AT+GUARDARDOS\r\n');
  });

  test('sin ticks del motor la descarga aceptada no mueve el peso', () async {
    final _Harness harness = await _hydraulicHarness(peso: 1500);

    await harness.receive('AT+INICIO=1500,300,100,3,2\r\n');

    expect(harness.latest.hydraulicDischargeActive, isTrue);
    expect(harness.pesoEnJson, 1500);
  });
}
