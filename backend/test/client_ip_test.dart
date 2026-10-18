import 'package:server/src/sessions.dart';
import 'package:test/test.dart';

void main() {
  group('resolveClientIp', () {
    test('behind a loopback proxy the forwarded client IP is used (CF first, then XFF first value, then X-Real-IP)', () {
      expect(resolveClientIp('127.0.0.1', {'CF-Connecting-IP': '203.0.113.9', 'X-Forwarded-For': '1.1.1.1'}), '203.0.113.9');
      expect(resolveClientIp('::1', {'x-forwarded-for': '198.51.100.4, 10.0.0.1'}), '198.51.100.4');
      expect(resolveClientIp('::ffff:127.0.0.1', {'X-Real-IP': '2001:db8::1'}), '2001:db8::1');
    });
    test('invalid forwarded values fall through; no headers gives the peer', () {
      expect(resolveClientIp('127.0.0.1', {'CF-Connecting-IP': 'evil<script>', 'X-Forwarded-For': '1.2.3.4'}), '1.2.3.4');
      expect(resolveClientIp('127.0.0.1', {'CF-Connecting-IP': 'nope'}), '127.0.0.1');
      expect(resolveClientIp('127.0.0.1', {}), '127.0.0.1');
    });
    test('a direct (non-loopback) client cannot spoof via headers', () {
      expect(resolveClientIp('198.51.100.7', {'CF-Connecting-IP': '1.2.3.4', 'X-Forwarded-For': '5.6.7.8'}), '198.51.100.7');
    });
  });
}
