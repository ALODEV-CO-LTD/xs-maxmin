import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mamba_app/features/friends/e2ee_crypto.dart';

// Vectors produced by frontend/src/e2ee/crypto.js running under Node (WebCrypto).
const idA = 'user-aaaa-1111';
const idB = 'user-bbbb-2222';
const msgId = 'AbCdEfGhIjKlMnOpQrStUv';
final aPrivate = <String, dynamic>{'kty': 'EC', 'crv': 'P-256', 'x': 'JDYgQ2CE4BGUyuBSlF4UxKA-ebWshu0uPknfe5CN9Xg', 'y': '3tT6t2xBvNeXuHLx9-TE6Cx-wF4wcjnWGxccJjcXtao', 'd': 'nriZigdJm3VJk3rLkv416IYOc5ySVs8dZta86WyLDfo'};
final bPrivate = <String, dynamic>{'kty': 'EC', 'crv': 'P-256', 'x': '_4EBvvPt0HyMogmvaFjlb21eJIrivmoJ8ObhoD35fzE', 'y': 'Cc7JGeKlfzR8ISbIRuEg7nobNK7Wpb2DME6dWlRx5rI', 'd': 'CbzYqn6qMIYfHFwglZqNiyS71pglVD0w2UAnFTAyBIw'};
const fpA = '1DEFA-E7662-4B147-83C46';
const fpB = '9AF2F-C6BE3-D5586-4EE1E';
const sessionKeyB64 = 'CfWHygQKzFUpOWSahXudW09B/bHcpBg30ZMJuIB+aN4=';
const nodePlainB64 = 'AAAAeHsidiI6MSwidCI6IlhpbiBjaMOgbywgxJHDonkgbMOgIHRpbiB0aOG7rSDinJMiLCJ0cyI6MTc2MDAwMDAwMDAwMCwiYSI6eyJuYW1lIjoiYW5oLTEucG5nIiwidHlwZSI6ImltYWdlL3BuZyIsInNpemUiOjV9fQECAwQF';
const nodeIv = 'O4n+2mcPmFzEXR8k';
const nodeCt = 'xnIYQGMv+GgKeGl+8lfGd19IDuPX/nQwpgXC1XaNxvJPbD4mZWJPuOoBhzmCiZIb8LVUSxQnswKj67t4d8HFegD2AmXidb5ajuTcmSNKymv1EBuQv4qeZeWZ5oSpIVoqtOWUdHPVkBQpJq3B3+j94x2RtmvNuZZo78YeWnjP8UxZWhQtpjaRxYMkjgNymdNejw==';

// Produced by Dart with a fixed IV (message below) and then decrypted successfully by frontend/src/e2ee/crypto.js
// under Node (user B -> user A, id DartMsgId0123456789abcd).
const dartIv = 'AQIDBAUGBwgJCgsM';
const dartCt = 'COq2hOKvEMtd8vXSNrqS2n2z2P7dtUp6uEQ9ASwnYScZrEX++LHE3s95P7+MTESC+sKaefyR896ZpqLnAtRsyDPQUjpIdoaqnOKMSPFdo1uJZhBdVpIVm3HxjA==';

void main() {
  final a = E2eeIdentity.fromPrivateJwk(aPrivate);
  final b = E2eeIdentity.fromPrivateJwk(bPrivate);

  test('public key derived from the private scalar equals the WebCrypto JWK', () {
    expect(a.publicJwk, {'kty': 'EC', 'crv': 'P-256', 'x': aPrivate['x'], 'y': aPrivate['y']});
    expect(b.publicJwk['x'], bPrivate['x']);
    expect(isValidPublicJwk(a.publicJwk), isTrue);
    expect(isValidPublicJwk({...a.publicJwk, 'y': b.publicJwk['y']}), isFalse);
  });

  test('fingerprint matches the web (20 hex chars in groups of 5)', () async {
    expect(await fingerprint(a.publicJwk), fpA);
    expect(await fingerprint(b.publicJwk), fpB);
    expect(RegExp(r'^[0-9A-F]{5}(-[0-9A-F]{5}){3}$').hasMatch(fpA), isTrue);
  });

  test('ECDH + HKDF session key equals the web key, from both sides', () async {
    final k1 = await deriveSessionKey(a, b.publicJwk, idA, idB);
    final k2 = await deriveSessionKey(b, a.publicJwk, idB, idA);
    expect(b64encode(k1), sessionKeyB64);
    expect(k2, k1);
  });

  test('Dart decrypts what Node (WebCrypto) encrypted', () async {
    final key = await deriveSessionKey(b, a.publicJwk, idB, idA);
    final plain = await decryptBytes(key, const Envelope(nodeIv, nodeCt), from: idA, to: idB, id: msgId);
    expect(b64encode(plain), nodePlainB64);
    final m = unpackMessage(plain);
    expect(m.text, 'Xin chào, đây là tin thử ✓');
    expect(m.ts, 1760000000000);
    expect(m.att, {'name': 'anh-1.png', 'type': 'image/png', 'size': 5});
    expect(m.file, [1, 2, 3, 4, 5]);
    expect(m.kind, isNull);
  });

  test('Dart encryption is byte-identical to the vector Node decrypted', () async {
    final key = await deriveSessionKey(b, a.publicJwk, idB, idA);
    final plain = packMessage(text: 'Dart gửi: chào Node ✓', ts: 1760000001234, file: Uint8List.fromList([9, 8, 7]));
    final env = await encryptBytes(key, plain, from: idB, to: idA, id: 'DartMsgId0123456789abcd', iv: Uint8List.fromList(List.generate(12, (i) => i + 1)));
    expect(env.iv, dartIv);
    expect(env.ct, dartCt);
  });

  test('AAD binds sender, recipient and message id', () async {
    final key = await deriveSessionKey(b, a.publicJwk, idB, idA);
    const env = Envelope(nodeIv, nodeCt);
    expect(decryptBytes(key, env, from: idB, to: idA, id: msgId), throwsA(anything));
    expect(decryptBytes(key, env, from: idA, to: idB, id: 'other-id-000000'), throwsA(anything));
  });

  test('packMessage reproduces the web frame byte for byte', () {
    final packed = packMessage(text: 'Xin chào, đây là tin thử ✓', ts: 1760000000000, att: {'name': 'anh-1.png', 'type': 'image/png', 'size': 5}, file: Uint8List.fromList([1, 2, 3, 4, 5]));
    expect(b64encode(packed), nodePlainB64);
  });

  test('screenshot notice kind round-trips', () {
    final m = unpackMessage(packMessage(ts: 5, kind: 'screenshot'));
    expect(m.kind, 'screenshot');
    expect(m.text, '');
    expect(m.att, isNull);
  });

  test('unpackMessage rejects malformed frames', () {
    expect(() => unpackMessage(Uint8List.fromList([0, 0, 0, 9, 1])), throwsFormatException);
    expect(() => unpackMessage(Uint8List(2)), throwsFormatException);
    final bad = Uint8List.fromList([0, 0, 0, 12, ...utf8.encode('{"v":2,"t":1}')]);
    expect(() => unpackMessage(bad), throwsFormatException);
  });

  test('round trip with random keys, a large payload (isolate path) and tamper detection', () async {
    final x = E2eeIdentity.generate();
    final y = E2eeIdentity.generate();
    expect(isValidPublicJwk(x.publicJwk), isTrue);
    expect(E2eeIdentity.fromStorage(x.toStorage())!.publicJwk, x.publicJwk);
    expect(E2eeIdentity.fromStorage('garbage'), isNull);
    final kx = await deriveSessionKey(x, y.publicJwk, 'u1', 'u2');
    final ky = await deriveSessionKey(y, x.publicJwk, 'u2', 'u1');
    expect(kx, ky);
    final big = Uint8List.fromList(List<int>.generate(400000, (i) => i % 251));
    final id = newMessageId();
    expect(id.length, 22);
    final env = await encryptBytes(kx, big, from: 'u1', to: 'u2', id: id);
    expect(b64decode(env.ct).length, big.length + 16);
    expect(await decryptBytes(ky, env, from: 'u1', to: 'u2', id: id), big);
    final raw = b64decode(env.ct)..[10] ^= 1;
    expect(decryptBytes(ky, Envelope(env.iv, b64encode(raw)), from: 'u1', to: 'u2', id: id), throwsA(anything));
  });

  test('refuses off-curve peer keys', () {
    final bad = {'kty': 'EC', 'crv': 'P-256', 'x': a.publicJwk['x'], 'y': b.publicJwk['y']};
    expect(() => a.sharedSecret(bad), throwsArgumentError);
  });
}
