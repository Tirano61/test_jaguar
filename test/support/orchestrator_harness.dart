import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:test_jaguar/application/dto/simulator_status_dto.dart';
import 'package:test_jaguar/application/services/simulator_orchestrator.dart';
import 'package:test_jaguar/core/constants/ble_constants.dart';
import 'package:test_jaguar/core/constants/payload_framing.dart';
import 'package:test_jaguar/domain/entities/ble_peripheral_status.dart';
import 'package:test_jaguar/domain/entities/scale_measurement.dart';
import 'package:test_jaguar/domain/repositories/ble_peripheral_repository.dart';
import 'package:test_jaguar/domain/repositories/scale_simulation_repository.dart';
import 'package:test_jaguar/domain/value_objects/simulation_phase.dart';

/// Repositorio BLE falso: registra lo que sale por notify y permite simular
/// los characteristic write de la app conectada.
class FakeBleRepository implements BlePeripheralRepository {
  final StreamController<BlePeripheralStatus> _statusController =
      StreamController<BlePeripheralStatus>.broadcast();

  final List<String> notifiedPayloads = <String>[];

  /// Perfiles que el orquestador pidió anunciar, en orden. Sirve para
  /// verificar que cambiar de protocolo rearma el advertising con los UUIDs y
  /// el framing correctos.
  final List<({BleUuids uuids, PayloadFraming framing})> uuidUpdates =
      <({BleUuids uuids, PayloadFraming framing})>[];

  int _sequence = 0;

  /// Simula un characteristic write de la app conectada: cada comando va con
  /// su propio commandSequence, que es lo que el orquestador usa para no
  /// reprocesar el mismo write dos veces.
  void receiveCommand(String command, {int? sequence}) {
    _sequence = sequence ?? (_sequence + 1);
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
  Future<void> updateBleProfile({
    required BleUuids uuids,
    required PayloadFraming framing,
  }) async {
    uuidUpdates.add((uuids: uuids, framing: framing));
  }

  @override
  Future<void> notifyUtf8Json(String payload) async {
    notifiedPayloads.add(payload);
  }

  @override
  Future<void> dispose() async {
    await _statusController.close();
  }
}

/// Motor de simulación falso: los ticks los dispara el test, no un Timer.
class FakeSimulationRepository implements ScaleSimulationRepository {
  final StreamController<bool> _runningController =
      StreamController<bool>.broadcast();
  final StreamController<SimulationPhase> _phaseController =
      StreamController<SimulationPhase>.broadcast();
  final StreamController<ScaleMeasurement> _measurementController =
      StreamController<ScaleMeasurement>.broadcast();

  /// Un tick del motor. Sin [measurement] emite `ScaleMeasurement.baseline`,
  /// que es lo que necesitan las pruebas del modo Hidráulico (ahí el tick sólo
  /// hace de reloj). Los demás protocolos sí miran el peso y el sensorInduc
  /// que llegan, así que pueden pasar el suyo.
  void tick([ScaleMeasurement? measurement]) {
    _measurementController.add(measurement ?? ScaleMeasurement.baseline);
  }

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

/// Orquestador cableado a los dos falsos, con los accesorios que necesitan las
/// pruebas de caracterización.
///
/// Los getters (`hydraulicActive`, `logs`, ...) existen para que los tests no
/// lean campos de `SimulatorStatusDto` directamente: ese DTO se va a partir en
/// sub-objetos por protocolo más adelante y así el cambio toca sólo este
/// archivo.
class Harness {
  Harness() {
    orchestrator = SimulatorOrchestrator(
      bleRepository: ble,
      simulationRepository: simulation,
    );
    _subscription = orchestrator.watchStatus().listen((SimulatorStatusDto s) {
      latest = s;
    });
  }

  final FakeBleRepository ble = FakeBleRepository();
  final FakeSimulationRepository simulation = FakeSimulationRepository();
  late final SimulatorOrchestrator orchestrator;
  late final StreamSubscription<SimulatorStatusDto> _subscription;

  SimulatorStatusDto latest = SimulatorStatusDto.initial;

  // --- accesorios de lectura ---

  List<String> get payloads => ble.notifiedPayloads;

  String get lastPayload => ble.notifiedPayloads.last;

  List<String> get logs => latest.logs;

  /// Primera línea del log, que es la más reciente (el orquestador antepone).
  ///
  /// Sólo sirve cuando la línea la escribió `_pushLog`. Los logs derivados de
  /// un cambio de estado BLE se anteponen de a varios y en orden inverso, así
  /// que para esos conviene `logs, contains(...)`.
  String get lastLog => latest.logs.first;

  /// Líneas de "Comando aplicado: ...", que son las que escribe el orquestador
  /// cuando un comando efectivamente se procesó. Su ausencia es lo que prueba
  /// que un comando se ignoró.
  Iterable<String> get logsAplicados =>
      latest.logs.where((String l) => l.startsWith('Comando aplicado'));

  int get pesoEnJson =>
      (jsonDecode(latest.lastJson) as Map<String, dynamic>)['peso'] as int;

  Map<String, dynamic> get jsonEnviado =>
      jsonDecode(latest.lastJson) as Map<String, dynamic>;

  int get pesoEmitido => latest.measurement.peso;

  int get weightHoldSecondsRemaining => latest.weightHoldSecondsRemaining;

  int get manualHold => latest.manualMeasurement.hold;

  int get manualTara => latest.manualMeasurement.tara;

  int get manualPeso => latest.manualMeasurement.peso;

  int get manualEstBalanza => latest.manualMeasurement.estBalanza;

  bool get hydraulicActive => latest.hidraulico.dischargeActive;

  bool get hydraulicPaused => latest.hidraulico.dischargePaused;

  double get hydraulicInitialPeso => latest.hidraulico.initialPeso;

  double get hydraulicTargetPeso => latest.hidraulico.targetPeso;

  // --- acciones ---

  Future<void> receive(String command) async {
    ble.receiveCommand(command);
    await pumpEventQueue();
  }

  /// Reenvía un comando con el mismo `commandSequence` que el anterior, que es
  /// lo que hace una emisión de `watchStatus()` no relacionada (adapter on/off,
  /// conexión de central) y que el orquestador debe ignorar.
  Future<void> receiveWithSameSequence(String command) async {
    ble.receiveCommand(command, sequence: ble._sequence);
    await pumpEventQueue();
  }

  /// Avanza el reloj de actuadores del modo Hidráulico [segundos] pasos. Es
  /// otro reloj que el del motor: mueve tubo y guillotina, no el peso.
  Future<void> actuatorSeconds(int segundos) async {
    for (int i = 0; i < segundos; i++) {
      await orchestrator.tickActuators();
    }
    await pumpEventQueue();
  }

  Future<void> tick([ScaleMeasurement? measurement]) async {
    simulation.tick(measurement);
    await pumpEventQueue();
  }

  /// Tick con un peso y un sensorInduc concretos, que es lo que hace falta para
  /// ejercitar el congelado de peso y los automatismos del ST407.
  Future<void> tickWith({required int peso, int sensorInduc = 0}) {
    return tick(
      ScaleMeasurement.baseline.copyWith(peso: peso, sensorInduc: sensorInduc),
    );
  }

  Future<void> dispose() async {
    await _subscription.cancel();
    await orchestrator.dispose();
  }
}

/// Harness listo para usar, con el teardown ya registrado.
Future<Harness> newHarness() async {
  final Harness harness = Harness();
  addTearDown(harness.dispose);
  await pumpEventQueue();
  return harness;
}
