abstract interface class WeightInterpolationService {
  int interpolate({
    required int from,
    required int to,
    required double progress,
  });
}
