import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/features/friends/call_service.dart';
import 'package:mamba_app/features/friends/realtime_socket.dart';

class _Sink implements FrameSink {
  final List<Map<String, dynamic>> sent = [];
  @override
  bool ready = true;
  @override
  void send(Map<String, dynamic> frame) => sent.add(frame);
}

CallService _svc(_Sink sink, {bool canCall = true}) => CallService(api: ApiClient(AuthStore(), client: MockClient((_) async => http.Response('{}', 404))), socket: sink, canCall: canCall);

void main() {
  group('reduceCall (pure state machine)', () {
    test('happy path: ringing -> connecting -> active -> ended', () {
      var s = reduceCall(CallStatus.idle, CallEvent.localInvite);
      expect(s.status, CallStatus.outgoing);
      s = reduceCall(s.status, CallEvent.remoteRinging);
      expect(s.status, CallStatus.outgoing);
      s = reduceCall(s.status, CallEvent.remoteAccept);
      expect(s.status, CallStatus.connecting);
      s = reduceCall(s.status, CallEvent.mediaUp);
      expect(s.status, CallStatus.connected);
      s = reduceCall(s.status, CallEvent.localHangup);
      expect(s.status, CallStatus.idle);
      expect(s.outcome, CallOutcome.ended);
    });

    test('incoming: accept goes connecting -> active; remote hang-up ends it', () {
      var s = reduceCall(CallStatus.idle, CallEvent.remoteInvite);
      expect(s.status, CallStatus.incoming);
      s = reduceCall(s.status, CallEvent.localAccept);
      expect(s.status, CallStatus.connecting);
      s = reduceCall(s.status, CallEvent.mediaUp);
      s = reduceCall(s.status, CallEvent.remoteEnd);
      expect((s.status, s.outcome), (CallStatus.idle, CallOutcome.ended));
    });

    test('missed: caller gives up or the ring times out', () {
      expect(reduceCall(CallStatus.incoming, CallEvent.remoteEnd).outcome, CallOutcome.missed);
      expect(reduceCall(CallStatus.incoming, CallEvent.ringTimeout).outcome, CallOutcome.missed);
      expect(reduceCall(CallStatus.outgoing, CallEvent.ringTimeout).outcome, CallOutcome.missed);
    });

    test('rejected / busy / unavailable / cancelled', () {
      expect(reduceCall(CallStatus.incoming, CallEvent.localReject).outcome, CallOutcome.rejected);
      expect(reduceCall(CallStatus.outgoing, CallEvent.remoteReject).outcome, CallOutcome.rejected);
      expect(reduceCall(CallStatus.outgoing, CallEvent.remoteBusy).outcome, CallOutcome.busy);
      expect(reduceCall(CallStatus.outgoing, CallEvent.unavailable).outcome, CallOutcome.unavailable);
      expect(reduceCall(CallStatus.outgoing, CallEvent.localHangup).outcome, CallOutcome.cancelled);
    });

    test('a second invitation while in a call is answered busy and leaves the call alone', () {
      for (final st in [CallStatus.outgoing, CallStatus.incoming, CallStatus.connecting, CallStatus.connected]) {
        final s = reduceCall(st, CallEvent.remoteInvite);
        expect(s.status, st);
        expect(s.outcome, CallOutcome.busy);
        expect(s.over, isFalse);
      }
    });

    test('failures end any running call; idle ignores stray events', () {
      expect(reduceCall(CallStatus.connected, CallEvent.socketLost).outcome, CallOutcome.failed);
      expect(reduceCall(CallStatus.connecting, CallEvent.failure).outcome, CallOutcome.failed);
      expect(reduceCall(CallStatus.idle, CallEvent.remoteEnd), isA<CallStep>().having((s) => s.status, 'status', CallStatus.idle).having((s) => s.outcome, 'outcome', isNull));
    });
  });

  group('CallService follows the machine', () {
    test('incoming -> rejected sends call-reject and records the outcome', () {
      final sink = _Sink();
      final c = _svc(sink);
      c.onFrame({'type': 'call-invite', 'from': 'u2', 'fromName': 'Bình'});
      expect(c.status, CallStatus.incoming);
      expect(c.busy, isTrue);
      c.reject();
      expect(c.status, CallStatus.idle);
      expect(sink.sent.single, {'type': 'call-reject', 'to': 'u2'});
      expect(c.lastEnd!.outcome, CallOutcome.rejected);
      expect(c.lastEnd!.incoming, isTrue);
      expect(c.lastEnd!.missedIncoming, isFalse);
      c.dispose();
    });

    test('incoming -> caller hangs up first = missed incoming call', () {
      final c = _svc(_Sink());
      c.onFrame({'type': 'call-invite', 'from': 'u2', 'fromName': 'Bình'});
      c.onFrame({'type': 'call-end', 'from': 'u2'});
      expect(c.status, CallStatus.idle);
      expect(c.lastEnd!.missedIncoming, isTrue);
      expect(c.lastEnd!.peerName, 'Bình');
      expect(c.endedTick, 1);
      expect(c.error, contains('nhỡ'));
      c.dispose();
    });

    test('busy: a second invitation is rejected with reason busy and reported as missed', () {
      final sink = _Sink();
      final c = _svc(sink);
      final missed = <String>[];
      c.onBusyMissed = (id, name) => missed.add('$id/$name');
      c.onFrame({'type': 'call-invite', 'from': 'u2', 'fromName': 'Bình'});
      c.onFrame({'type': 'call-invite', 'from': 'u3', 'fromName': 'Chi'});
      expect(sink.sent.single, {'type': 'call-reject', 'to': 'u3', 'reason': 'busy'});
      expect(missed, ['u3/Chi']);
      expect(c.status, CallStatus.incoming);
      expect(c.peer!.id, 'u2'); // the first call is untouched
      c.dispose();
    });

    test('outgoing: ringing -> rejected / busy / unavailable', () {
      for (final (frame, outcome) in [
        ({'type': 'call-reject', 'from': 'u2'}, CallOutcome.rejected),
        ({'type': 'call-reject', 'from': 'u2', 'reason': 'busy'}, CallOutcome.busy),
        ({'type': 'call-unavailable', 'from': 'u2'}, CallOutcome.unavailable),
      ]) {
        final c = _svc(_Sink());
        c.debugStartOutgoing('u2', 'Bình');
        expect(c.status, CallStatus.outgoing);
        c.onFrame({'type': 'call-ringing', 'from': 'u2'});
        expect(c.ringing, isTrue);
        c.onFrame(frame);
        expect(c.status, CallStatus.idle);
        expect(c.lastEnd!.outcome, outcome);
        expect(c.lastEnd!.incoming, isFalse);
        c.dispose();
      }
    });

    test('hanging up a ringing outgoing call is cancelled; the socket dropping fails an active call', () {
      final sink = _Sink();
      final c = _svc(sink);
      c.debugStartOutgoing('u2', 'Bình');
      c.hangUp();
      expect(c.lastEnd!.outcome, CallOutcome.cancelled);
      expect(sink.sent.last['type'], 'call-end');
      c.debugSetStatus(CallStatus.connected, withPeer: const CallPeer('u2', 'Bình'));
      c.onSocketLost();
      expect(c.status, CallStatus.idle);
      expect(c.lastEnd!.outcome, CallOutcome.failed);
      c.dispose();
    });

    test('admin accounts never ring', () {
      final sink = _Sink();
      final c = _svc(sink, canCall: false);
      c.onFrame({'type': 'call-invite', 'from': 'u2'});
      expect(c.status, CallStatus.idle);
      expect(sink.sent.single['reason'], 'busy');
      c.dispose();
    });
  });
}
