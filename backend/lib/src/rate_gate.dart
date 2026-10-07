import 'package:dart_frog/dart_frog.dart';

import 'package:server/src/sessions.dart' show clientIp;

/// In-memory throttles that stop someone from sweeping the 6-digit Mã ID space
/// (900 000 codes) to map IDs to names/usernames. Memory only on purpose:
/// they only delay a guesser, never touch data, and a restart merely resets
/// the counters.

/// Sliding window: at most [limit] hits per [window] per key. Used for
/// `GET /me/friends/search`.
class SlidingWindowGate {
  SlidingWindowGate({required this.limit, required this.window, DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final int limit;
  final Duration window;
  final DateTime Function() _now;
  final Map<String, List<DateTime>> _hits = {};
  int _sinceSweep = 0;

  /// Records one hit for [key]. Returns 0 if allowed, otherwise the number of
  /// seconds to wait (the hit is then NOT counted).
  int hit(String key) {
    final now = _now();
    _sweepMaybe(now);
    final list = (_hits[key] ??= <DateTime>[]);
    list.removeWhere((t) => now.difference(t) >= window);
    if (list.length >= limit) {
      final wait = window - now.difference(list.first);
      return wait.inSeconds + 1;
    }
    list.add(now);
    return 0;
  }

  void _sweepMaybe(DateTime now) {
    if (++_sinceSweep < 200) return;
    _sinceSweep = 0;
    _hits.removeWhere((_, l) => l.isEmpty || now.difference(l.last) >= window);
  }

  int get trackedKeys => _hits.length;
}

/// Failure counter with escalating lock: after [freeFailures] failures inside
/// [window] the key is locked for [baseLock], then 2x, 4x ... up to [maxLock]
/// on every further failure. Used for failed friend lookups/adds (404).
class FailureGate {
  FailureGate({
    this.freeFailures = 10,
    this.window = const Duration(minutes: 10),
    this.baseLock = const Duration(seconds: 30),
    this.maxLock = const Duration(minutes: 30),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final int freeFailures;
  final Duration window;
  final Duration baseLock;
  final Duration maxLock;
  final DateTime Function() _now;
  final Map<String, _Fails> _state = {};
  int _sinceSweep = 0;

  /// Seconds the key must still wait, or 0 if it may try.
  int lockedSecondsLeft(String key) {
    final s = _state[key];
    if (s == null || s.lockedUntil == null) return 0;
    final left = s.lockedUntil!.difference(_now());
    return left.isNegative || left == Duration.zero ? 0 : left.inSeconds + 1;
  }

  /// Counts one failure; returns the lock length in seconds if it triggered
  /// (or extended) a lock, else 0.
  int recordFailure(String key) {
    final now = _now();
    _sweepMaybe(now);
    final s = (_state[key] ??= _Fails(now));
    final unlocked = s.lockedUntil == null || now.isAfter(s.lockedUntil!);
    if (unlocked && now.difference(s.lastFail) >= window) {
      s.count = 0;
      s.level = 0;
    }
    s.lastFail = now;
    s.count++;
    if (s.count < freeFailures) return 0;
    var lock = baseLock * (1 << s.level.clamp(0, 12));
    if (lock > maxLock) lock = maxLock;
    s.level++;
    s.lockedUntil = now.add(lock);
    return lock.inSeconds;
  }

  void _sweepMaybe(DateTime now) {
    if (++_sinceSweep < 200) return;
    _sinceSweep = 0;
    _state.removeWhere((_, s) =>
        now.difference(s.lastFail) >= window * 3 && (s.lockedUntil == null || now.isAfter(s.lockedUntil!)));
  }

  int get trackedKeys => _state.length;
}

class _Fails {
  _Fails(this.lastFail);
  DateTime lastFail;
  int count = 0;
  int level = 0;
  DateTime? lockedUntil;
}

/// Shared instances used by the friends routes.
final friendSearchPerUser = SlidingWindowGate(limit: 30, window: const Duration(minutes: 1));
final friendSearchPerIp = SlidingWindowGate(limit: 90, window: const Duration(minutes: 1));
final friendAddFailPerUser = FailureGate();
final friendAddFailPerIp = FailureGate(freeFailures: 30);

Response tooManyRequests(int seconds, String what) => Response.json(
      statusCode: 429,
      headers: {'Retry-After': '$seconds'},
      body: {'error': 'Bạn $what quá nhanh. Vui lòng thử lại sau $seconds giây.', 'retryAfter': seconds},
    );

/// Search throttle: a 429 response if [userId] or the caller's IP is over the
/// limit, else null.
Response? throttleFriendSearch(RequestContext context, String userId) {
  final w1 = friendSearchPerUser.hit('u:$userId');
  final w2 = friendSearchPerIp.hit('ip:${clientIp(context)}');
  final wait = w1 > w2 ? w1 : w2;
  return wait > 0 ? tooManyRequests(wait, 'tìm kiếm') : null;
}

/// Add-friend throttle checked BEFORE a lookup; null if the caller may try.
Response? checkFriendAddLock(RequestContext context, String userId) {
  final a = friendAddFailPerUser.lockedSecondsLeft('u:$userId');
  final b = friendAddFailPerIp.lockedSecondsLeft('ip:${clientIp(context)}');
  final wait = a > b ? a : b;
  return wait > 0 ? tooManyRequests(wait, 'thử mã ID sai') : null;
}

/// Records a failed lookup (code/user not found).
void recordFriendAddFailure(RequestContext context, String userId) {
  friendAddFailPerUser.recordFailure('u:$userId');
  friendAddFailPerIp.recordFailure('ip:${clientIp(context)}');
}
