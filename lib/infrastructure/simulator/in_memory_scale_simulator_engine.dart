import 'dart:async';
import 'dart:math';

import 'package:test_jaguar/domain/entities/scale_measurement.dart';
import 'package:test_jaguar/domain/entities/simulation_state.dart';
import 'package:test_jaguar/domain/services/linear_weight_interpolation_service.dart';
import 'package:test_jaguar/domain/services/simulation_domain_service.dart';
import 'package:test_jaguar/domain/services/weight_interpolation_service.dart';
import 'package:test_jaguar/domain/value_objects/simulation_phase.dart';
import 'package:test_jaguar/infrastructure/simulator/scale_simulator_engine.dart';

class InMemoryScaleSimulatorEngine implements ScaleSimulatorEngine {
  InMemoryScaleSimulatorEngine({
    SimulationDomainService? domainService,
    WeightInterpolationService? interpolationService,
    Random? random,
  })  : _domainService = domainService ?? const SimulationDomainService(),
        _interpolationService =
            interpolationService ?? const LinearWeightInterpolationService(),
        _random = random ?? Random() {
    _state = _domainService.initialState(
      initialLoadedWeight: _randomInRange(
        SimulationDomainService.loadedRange.min,
        SimulationDomainService.loadedRange.max,
      ),
    );
  }

  final StreamController<bool> _runningController =
      StreamController<bool>.broadcast();
  final StreamController<SimulationPhase> _phaseController =
      StreamController<SimulationPhase>.broadcast();
  final StreamController<ScaleMeasurement> _measurementController =
      StreamController<ScaleMeasurement>.broadcast();

  final SimulationDomainService _domainService;
  final WeightInterpolationService _interpolationService;
  final Random _random;

  Timer? _ticker;
  bool _running = false;
  late SimulationState _state;

  @override
  Stream<bool> watchRunning() async* {
    yield _running;
    yield* _runningController.stream;
  }

  @override
  Stream<SimulationPhase> watchPhase() async* {
    yield _state.phase;
    yield* _phaseController.stream;
  }

  @override
  Stream<ScaleMeasurement> watchMeasurements() async* {
    yield _domainService.measurementFrom(
      weight: _state.currentWeight,
      phase: _state.phase,
    );
    yield* _measurementController.stream;
  }

  @override
  Future<void> start() async {
    if (_running) return;

    _ticker?.cancel();
    _running = true;
    _runningController.add(true);
    _phaseController.add(_state.phase);
    _emitMeasurement();

    _ticker = Timer.periodic(
      Duration(seconds: _domainService.timing.tickIntervalSeconds),
      (_) => _onTick(),
    );
  }

  @override
  Future<void> stop() async {
    _ticker?.cancel();
    _ticker = null;

    if (!_running) {
      return;
    }

    _running = false;
    _runningController.add(false);
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _runningController.close();
    await _phaseController.close();
    await _measurementController.close();
  }

  void _onTick() {
    if (!_running) {
      return;
    }

    final int nextWeight = _nextWeight();
    final int nextTickInPhase = _state.tickInPhase + 1;
    final bool shouldTransition =
        nextTickInPhase >= _domainService.timing.ticksPerPhase();

    if (shouldTransition) {
      final SimulationPhase nextPhase = _domainService.phaseAfter(_state.phase);
      final int nextCycle = nextPhase == SimulationPhase.loadedWaiting
          ? _state.cycle + 1
          : _state.cycle;

      _state = _state.copyWith(
        phase: nextPhase,
        tickInPhase: 0,
        cycle: nextCycle,
        currentWeight: nextWeight,
        phaseStartWeight: nextWeight,
        phaseTargetWeight: _targetForPhase(nextPhase, nextWeight),
      );
      _phaseController.add(_state.phase);
    } else {
      _state = _state.copyWith(
        tickInPhase: nextTickInPhase,
        currentWeight: nextWeight,
      );
    }

    _emitMeasurement();
  }

  int _nextWeight() {
    switch (_state.phase) {
      case SimulationPhase.loadedWaiting:
        return _stableWeight(
          currentWeight: _state.currentWeight,
          minWeight: SimulationDomainService.loadedRange.min,
          maxWeight: SimulationDomainService.loadedRange.max,
        );
      case SimulationPhase.unloading:
        return _progressiveWeight(
          currentWeight: _state.currentWeight,
          from: _state.phaseStartWeight,
          to: _state.phaseTargetWeight,
          increasing: false,
          minWeight: SimulationDomainService.emptyRange.min,
          maxWeight: SimulationDomainService.loadedRange.max,
        );
      case SimulationPhase.emptyWaiting:
        return _stableWeight(
          currentWeight: _state.currentWeight,
          minWeight: SimulationDomainService.emptyRange.min,
          maxWeight: SimulationDomainService.emptyRange.max,
        );
      case SimulationPhase.loading:
        return _progressiveWeight(
          currentWeight: _state.currentWeight,
          from: _state.phaseStartWeight,
          to: _state.phaseTargetWeight,
          increasing: true,
          minWeight: SimulationDomainService.emptyRange.min,
          maxWeight: SimulationDomainService.loadedRange.max,
        );
    }
  }

  int _stableWeight({
    required int currentWeight,
    required int minWeight,
    required int maxWeight,
  }) {
    final int jitter = _randomInRange(-45, 45);
    final int candidate = currentWeight + jitter;
    return candidate.clamp(minWeight, maxWeight);
  }

  int _progressiveWeight({
    required int currentWeight,
    required int from,
    required int to,
    required bool increasing,
    required int minWeight,
    required int maxWeight,
  }) {
    final int ticksPerPhase = _domainService.timing.ticksPerPhase();
    final int nextTick = (_state.tickInPhase + 1).clamp(1, ticksPerPhase);
    final double progress = nextTick / ticksPerPhase;

    final int interpolated = _interpolationService.interpolate(
      from: from,
      to: to,
      progress: progress,
    );
    final int noisy = interpolated + _randomInRange(-25, 25);

    final int direction = increasing ? 1 : -1;
    final int remaining = (to - currentWeight).abs();
    final int ticksRemaining = max(1, ticksPerPhase - _state.tickInPhase);
    final int baseStep = max(35, (remaining / ticksRemaining).round());
    final int step = (baseStep + _randomInRange(-18, 18)).clamp(20, 320);

    final int limitedByStep = currentWeight + (direction * step);
    final int directionalCandidate = increasing
        ? min(noisy, limitedByStep)
        : max(noisy, limitedByStep);

    final int monotonic = increasing
        ? max(currentWeight, directionalCandidate)
        : min(currentWeight, directionalCandidate);

    final int notPastTarget = increasing ? min(monotonic, to) : max(monotonic, to);
    return notPastTarget.clamp(minWeight, maxWeight);
  }

  int _targetForPhase(SimulationPhase phase, int currentWeight) {
    switch (phase) {
      case SimulationPhase.loadedWaiting:
        return currentWeight.clamp(
          SimulationDomainService.loadedRange.min,
          SimulationDomainService.loadedRange.max,
        );
      case SimulationPhase.unloading:
        return _randomInRange(
          SimulationDomainService.emptyRange.min,
          SimulationDomainService.emptyRange.max,
        );
      case SimulationPhase.emptyWaiting:
        return currentWeight.clamp(
          SimulationDomainService.emptyRange.min,
          SimulationDomainService.emptyRange.max,
        );
      case SimulationPhase.loading:
        return _randomInRange(
          SimulationDomainService.loadedRange.min,
          SimulationDomainService.loadedRange.max,
        );
    }
  }

  int _randomInRange(int minInclusive, int maxInclusive) {
    return minInclusive + _random.nextInt(maxInclusive - minInclusive + 1);
  }

  void _emitMeasurement() {
    if (_measurementController.isClosed) {
      return;
    }

    _measurementController.add(
      _domainService.measurementFrom(
        weight: _state.currentWeight,
        phase: _state.phase,
      ),
    );
  }
}
