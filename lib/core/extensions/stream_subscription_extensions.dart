import 'dart:async';

extension StreamSubscriptionGroupX on List<StreamSubscription<dynamic>> {
  Future<void> cancelAll() async {
    for (final StreamSubscription<dynamic> subscription in this) {
      await subscription.cancel();
    }
    clear();
  }
}
