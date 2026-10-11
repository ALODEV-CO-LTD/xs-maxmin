import 'dart:async';

import 'package:flutter/services.dart';

/// Fallback ring for an incoming call when notifications are not allowed (app on screen): the system alert sound and a
/// buzz every 2 s. Normally the incoming-call NOTIFICATION rings (the phone's own ringtone, repeating, with vibration,
/// see notifications.dart), so the sound follows the phone's ringer mode and stops as soon as it is cancelled.
abstract class CallRinger {
  bool get ringing;
  Future<void> start();
  Future<void> stop();
}

class SystemCallRinger implements CallRinger {
  Timer? _timer;

  @override
  bool get ringing => _timer != null;

  void _once() {
    SystemSound.play(SystemSoundType.alert);
    HapticFeedback.vibrate();
  }

  @override
  Future<void> start() async {
    if (_timer != null) return;
    _once();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _once());
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }
}

class SilentRinger implements CallRinger {
  @override
  bool ringing = false;
  @override
  Future<void> start() async => ringing = true;
  @override
  Future<void> stop() async => ringing = false;
}
