import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mamba_app/features/friends/call_service.dart' show callLine, isMissedCall;
import 'package:mamba_app/features/friends/chat_models.dart';
import 'package:mamba_app/features/friends/friends_controller.dart' show foldVi;
import 'package:mamba_app/features/friends/realtime_socket.dart';

ChatMessage msg(String id, int at, {bool image = false, String text = 'x'}) => ChatMessage(
      id: id,
      peerId: 'p',
      mine: true,
      text: text,
      createdAt: at,
      status: MsgStatus.sent,
      att: image ? const ChatAttachment(name: 'a.png', type: 'image/png', size: 3, path: 'p') : null,
    );

void main() {
  group('relay frames', () {
    test('parses an e2ee-msg frame as the server sends it', () {
      final f = E2eeFrame.tryParse({'type': 'e2ee-msg', 'id': 'abcdefgh', 'from': 'u1', 'fromName': 'An', 'iv': 'AA==', 'ct': 'BB==', 'part': 0, 'parts': 1, 'ts': 1760000000000})!;
      expect(f.from, 'u1');
      expect(f.fromName, 'An');
      expect(f.ts, 1760000000000);
    });

    test('rejects malformed frames (bad part indexes, too many parts, wrong types)', () {
      Map<String, dynamic> base() => {'id': 'abcdefgh', 'from': 'u1', 'iv': 'AA==', 'ct': 'BB=='};
      expect(E2eeFrame.tryParse({...base(), 'part': 2, 'parts': 2}), isNull);
      expect(E2eeFrame.tryParse({...base(), 'part': 0, 'parts': 9}), isNull);
      expect(E2eeFrame.tryParse({...base(), 'part': -1, 'parts': 2}), isNull);
      expect(E2eeFrame.tryParse({...base(), 'ct': 5}), isNull);
      expect(E2eeFrame.tryParse({'id': 'abcdefgh'}), isNull);
      expect(E2eeFrame.tryParse(base()), isNotNull); // part/parts default to 0/1
    });

    test('splitCiphertext slices at 1,000,000 chars and reassembles in any order', () {
      final ct = List.generate(2500000, (i) => 'ABCD'[i % 4]).join();
      final slices = splitCiphertext(ct);
      expect(slices.map((s) => s.length), [1000000, 1000000, 500000]);
      final a = PartAssembler();
      E2eeFrame frame(int i) => E2eeFrame(id: 'm1', from: 'u', fromName: null, iv: 'iv', ct: slices[i], part: i, parts: 3);
      expect(a.add(frame(2)), isNull);
      expect(a.add(frame(0)), isNull);
      expect(a.add(frame(0)), isNull); // duplicate part ignored
      final whole = a.add(frame(1))!;
      expect(whole.ct, ct);
      expect(whole.parts, 1);
      expect(splitCiphertext('abc'), ['abc']);
    });

    test('incomplete messages are forgotten after the wait time', () {
      var now = DateTime(2026, 1, 1);
      final a = PartAssembler(now: () => now);
      E2eeFrame frame(int i) => E2eeFrame(id: 'm1', from: 'u', fromName: null, iv: 'iv', ct: 'p$i', part: i, parts: 2);
      expect(a.add(frame(0)), isNull);
      now = now.add(const Duration(seconds: 61));
      expect(a.add(frame(1)), isNull); // part 0 expired, so this alone is incomplete
      expect(a.add(frame(0))!.ct, 'p0p1');
    });
  });

  group('retention', () {
    final now = DateTime(2026, 10, 11, 12).millisecondsSinceEpoch;
    final hour = 3600 * 1000;

    test('removes only messages older than the cutoff', () {
      final list = [msg('old', now - 2 * hour), msg('new', now - hour ~/ 2), msg('edge', now - hour)];
      final gone = expiredMessages(list, const RetentionRule(3600, 'all'), now).map((m) => m.id);
      expect(gone, ['old']);
    });

    test('scope images keeps text messages', () {
      final list = [msg('t', now - 5 * hour), msg('i', now - 5 * hour, image: true)];
      expect(expiredMessages(list, const RetentionRule(3600, 'images'), now).map((m) => m.id), ['i']);
      expect(expiredMessages(list, const RetentionRule(3600, 'all'), now).length, 2);
    });

    test('rule serialisation round trip and bad input', () {
      final r = RetentionRule.tryParse(const RetentionRule(604800, 'images').toJson())!;
      expect(r.ttlSeconds, 604800);
      expect(r.scope, 'images');
      expect(r.describe, 'Tự xoá ảnh cũ hơn 7 ngày (trên thiết bị này)');
      expect(RetentionRule.tryParse(null), isNull);
      expect(RetentionRule.tryParse('nope'), isNull);
      expect(RetentionRule.tryParse('{"ttlSeconds":0}'), isNull);
    });
  });

  group('attachments', () {
    test('sniffs real image types and rejects others (GIF, PDF)', () {
      expect(sniffImageType(Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 0])), 'image/jpeg');
      expect(sniffImageType(Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])), 'image/png');
      expect(sniffImageType(Uint8List.fromList([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50])), 'image/webp');
      expect(sniffImageType(Uint8List.fromList('GIF89a......'.codeUnits)), isNull);
      expect(sniffImageType(Uint8List.fromList('%PDF-1.7.....'.codeUnits)), isNull);
    });

    test('anonymous names hide the original file name', () {
      var i = 0;
      expect(anonymousName('image/png', () => i++), 'anh-0001020304.png');
      expect(anonymousName('image/webp'), endsWith('.webp'));
      expect(anonymousName('image/jpeg'), endsWith('.jpg'));
    });
  });

  group('text helpers', () {
    test('foldVi removes Vietnamese accents', () {
      expect(foldVi('Đỗ Ngọc Mai'), 'do ngoc mai');
      expect(foldVi('Nguyễn Thị Hương'), 'nguyen thi huong');
      expect(foldVi('ƯƠN'), 'uon');
    });

    test('call history lines match the web', () {
      expect(callLine({'direction': 'outgoing', 'status': 'completed', 'durationSeconds': 75}), 'Cuộc gọi thoại đi · 1:15');
      expect(callLine({'direction': 'incoming', 'status': 'completed', 'durationSeconds': 5}), 'Cuộc gọi thoại đến · 0:05');
      expect(callLine({'direction': 'incoming', 'status': 'missed'}), 'Cuộc gọi nhỡ');
      expect(callLine({'direction': 'outgoing', 'status': 'busy'}), 'Cuộc gọi đi · Máy bận');
      expect(callLine({'direction': 'incoming', 'status': 'rejected'}), 'Bạn đã từ chối cuộc gọi');
      expect(isMissedCall({'direction': 'incoming', 'status': 'busy'}), isTrue);
      expect(isMissedCall({'direction': 'outgoing', 'status': 'missed'}), isFalse);
    });

    test('failure reasons are readable', () {
      expect(reasonText('offline'), contains('offline'));
      expect(reasonText('whatever'), 'Chưa gửi được.');
    });

    test('reconnect backoff doubles and caps at 30 s', () {
      int ms(int attempt) => reconnectDelay(attempt).inMilliseconds;
      expect(ms(0), inInclusiveRange(1000, 1250));
      expect(ms(2), inInclusiveRange(4000, 5000));
      expect(ms(20), inInclusiveRange(30000, 37500));
    });
  });
}
