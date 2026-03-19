import 'dart:async';

class VennuzoTicketOrderMonitor {
  static final Map<String, Timer> _timers = <String, Timer>{};
  static final Map<String, int> _pollCounts = <String, int>{};

  static void startMonitoring({
    required String orderId,
    required Future<void> Function() onPoll,
    Duration interval = const Duration(seconds: 30),
    int maxPolls = 10,
  }) {
    stopMonitoring(orderId);
    _pollCounts[orderId] = 0;
    _timers[orderId] = Timer.periodic(interval, (timer) async {
      final count = (_pollCounts[orderId] ?? 0) + 1;
      _pollCounts[orderId] = count;
      if (count > maxPolls) {
        stopMonitoring(orderId);
        return;
      }
      await onPoll();
    });
  }

  static void stopMonitoring(String orderId) {
    _timers.remove(orderId)?.cancel();
    _pollCounts.remove(orderId);
  }

  static void stopAll() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _pollCounts.clear();
  }
}
