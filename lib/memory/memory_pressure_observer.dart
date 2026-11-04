import 'dart:async';
import 'package:flutter/widgets.dart';
import 'model_memory_policy.dart';

/// Respond to OS pressure, not a periodic forced-GC/cache-clearing loop.
class MemoryPressureObserver with WidgetsBindingObserver {
  MemoryPressureObserver(this.policy);
  final ModelMemoryPolicy policy;
  @override
  void didHaveMemoryPressure() {
    // Flutter already clears reclaimable image cache entries on pressure.
    // Feature owners must release live image references on disposal.
    unawaited(policy.releaseIfIdle());
  }
}
