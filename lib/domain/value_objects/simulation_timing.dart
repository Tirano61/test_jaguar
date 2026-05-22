class SimulationTiming {
  const SimulationTiming({
    required this.phaseDurationSeconds,
    required this.tickIntervalSeconds,
  })  : assert(phaseDurationSeconds > 0),
        assert(tickIntervalSeconds > 0),
        assert(
          phaseDurationSeconds % tickIntervalSeconds == 0,
          'phaseDurationSeconds must be divisible by tickIntervalSeconds',
        );

  final int phaseDurationSeconds;
  final int tickIntervalSeconds;

  int ticksPerPhase() => phaseDurationSeconds ~/ tickIntervalSeconds;

  static const SimulationTiming oneMinutePerPhase = SimulationTiming(
    phaseDurationSeconds: 60,
    tickIntervalSeconds: 1,
  );
}
