import 'dart:math';

import 'package:test_jaguar/domain/services/weight_interpolation_service.dart';

class LinearWeightInterpolationService implements WeightInterpolationService {
  const LinearWeightInterpolationService();

  @override
  int interpolate({
    required int from,
    required int to,
    required double progress,
  }) {
    final double safeProgress = progress.clamp(0.0, 1.0);
    final double raw = from + (to - from) * safeProgress;
    return max(0, raw.round());
  }
}
