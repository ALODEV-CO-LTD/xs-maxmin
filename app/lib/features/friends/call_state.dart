/// Where a call is in its life. [incoming] / [outgoing] are the two "ringing" phases.
enum CallStatus { idle, outgoing, incoming, connecting, connected }

/// How a call ended, from the point of view of this device.
enum CallOutcome {
  /// Was talking (or setting up) and somebody hung up.
  ended,

  /// We called and hung up before the other side answered.
  cancelled,

  /// Incoming call nobody answered here (the caller gave up, or the ring timed out), or an outgoing call that rang
  /// out without an answer.
  missed,

  /// We declined an incoming call, or the other side declined ours.
  rejected,

  /// The other side was already in a call.
  busy,

  /// The other side is offline.
  unavailable,

  /// Network / microphone / signalling problem.
  failed,
}

/// Everything that can happen to a call.
enum CallEvent {
  localInvite,
  remoteInvite,
  remoteRinging,
  localAccept,
  remoteAccept,
  mediaUp,
  localReject,
  remoteReject,
  remoteBusy,
  localHangup,
  remoteEnd,
  ringTimeout,
  unavailable,
  failure,
  socketLost,
}

/// Result of one transition: the new status and, when the call is over, how it ended.
class CallStep {
  const CallStep(this.status, [this.outcome]);
  final CallStatus status;
  final CallOutcome? outcome;
  bool get over => outcome != null && status == CallStatus.idle;

  @override
  String toString() => 'CallStep($status, $outcome)';
}

/// The call state machine, pure so it can be tested without WebRTC:
/// ringing (outgoing / incoming) -> connecting -> connected -> ended, or out of ringing straight to
/// missed / rejected / busy / unavailable / cancelled. A new invitation while a call is running is answered with
/// busy and leaves the running call untouched (status unchanged, outcome busy).
CallStep reduceCall(CallStatus s, CallEvent e) {
  if (s == CallStatus.idle) {
    return switch (e) {
      CallEvent.localInvite => const CallStep(CallStatus.outgoing),
      CallEvent.remoteInvite => const CallStep(CallStatus.incoming),
      _ => const CallStep(CallStatus.idle),
    };
  }
  if (e == CallEvent.remoteInvite) return CallStep(s, CallOutcome.busy);
  final ringing = s == CallStatus.outgoing || s == CallStatus.incoming;
  CallStep over(CallOutcome o) => CallStep(CallStatus.idle, o);
  switch (e) {
    case CallEvent.remoteAccept:
      return s == CallStatus.outgoing ? const CallStep(CallStatus.connecting) : CallStep(s);
    case CallEvent.localAccept:
      return s == CallStatus.incoming ? const CallStep(CallStatus.connecting) : CallStep(s);
    case CallEvent.mediaUp:
      return s == CallStatus.connecting || s == CallStatus.connected ? const CallStep(CallStatus.connected) : CallStep(s);
    case CallEvent.localReject:
      return s == CallStatus.incoming ? over(CallOutcome.rejected) : CallStep(s);
    case CallEvent.remoteReject:
      return s == CallStatus.outgoing ? over(CallOutcome.rejected) : CallStep(s);
    case CallEvent.remoteBusy:
      return s == CallStatus.outgoing ? over(CallOutcome.busy) : CallStep(s);
    case CallEvent.unavailable:
      return s == CallStatus.outgoing ? over(CallOutcome.unavailable) : CallStep(s);
    case CallEvent.ringTimeout:
      return ringing ? over(CallOutcome.missed) : CallStep(s);
    case CallEvent.localHangup:
      if (s == CallStatus.outgoing) return over(CallOutcome.cancelled);
      if (s == CallStatus.incoming) return over(CallOutcome.rejected);
      return over(CallOutcome.ended);
    case CallEvent.remoteEnd:
      return s == CallStatus.incoming ? over(CallOutcome.missed) : over(CallOutcome.ended);
    case CallEvent.failure:
    case CallEvent.socketLost:
      return over(CallOutcome.failed);
    case CallEvent.remoteRinging:
    case CallEvent.localInvite:
    case CallEvent.remoteInvite:
      return CallStep(s);
  }
}

/// What a finished call looked like; the app uses it for the missed-call notification and the history.
class CallEnd {
  const CallEnd({required this.peerId, required this.peerName, required this.outcome, required this.incoming, required this.duration});
  final String peerId;
  final String peerName;
  final CallOutcome outcome;

  /// True when the other side called us.
  final bool incoming;
  final Duration duration;

  /// An incoming call we never talked on and did not decline ourselves.
  bool get missedIncoming => incoming && outcome == CallOutcome.missed;
}
