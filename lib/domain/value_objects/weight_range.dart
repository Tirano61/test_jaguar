class WeightRange {
  const WeightRange({required this.min, required this.max})
      : assert(min <= max, 'min must be <= max');

  final int min;
  final int max;

  int clamp(int value) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  int midpoint() => ((min + max) / 2).round();

  bool contains(int value) => value >= min && value <= max;
}
