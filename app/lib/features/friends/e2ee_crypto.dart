import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// End-to-end encryption primitives, wire-compatible with frontend/src/e2ee/crypto.js
/// (docs/MA_HOA_2_DAU.md):
///
///  * identity   ECDH P-256 key pair; the public half is a JWK `{kty:'EC', crv:'P-256', x, y}` (base64url, no padding)
///  * session    ECDH x-coordinate (32 bytes) -> HKDF-SHA-256 (salt = SHA-256 of the two user ids sorted and joined with
///               `|`, info = `mamba-e2ee-v1`) -> AES-256-GCM key
///  * message    AES-GCM, random 96-bit IV, AAD = `from|to|id`, ciphertext = encrypted bytes followed by the 16-byte
///               tag (WebCrypto layout); `iv` and `ct` travel as standard base64
///  * frame      `[uint32 BE header length][header JSON {v:1,t,ts,a,k?}][raw file bytes]`
///
/// Dart's `cryptography` package has no pure-Dart ECDH, so P-256 arithmetic lives in this file (BigInt, with
/// on-curve validation of every peer key).

// ---- base64 helpers -------------------------------------------------------

String b64encode(List<int> bytes) => base64.encode(bytes);
Uint8List b64decode(String s) => Uint8List.fromList(base64.decode(base64.normalize(s)));
String b64urlEncode(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
Uint8List b64urlDecode(String s) => Uint8List.fromList(base64Url.decode(base64Url.normalize(s)));

// ---- P-256 ----------------------------------------------------------------

final _p = BigInt.parse('ffffffff00000001000000000000000000000000ffffffffffffffffffffffff', radix: 16);
final _a = _p - BigInt.from(3);
final _b = BigInt.parse('5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b', radix: 16);
final _n = BigInt.parse('ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551', radix: 16);
final _gx = BigInt.parse('6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296', radix: 16);
final _gy = BigInt.parse('4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5', radix: 16);

class _Pt {
  const _Pt(this.x, this.y);
  final BigInt x;
  final BigInt y;
}

BigInt _mod(BigInt v) {
  final r = v % _p;
  return r.isNegative ? r + _p : r;
}

BigInt _inv(BigInt v) => _mod(v).modInverse(_p);

_Pt? _add(_Pt? p, _Pt? q) {
  if (p == null) return q;
  if (q == null) return p;
  BigInt lambda;
  if (p.x == q.x) {
    if (_mod(p.y + q.y) == BigInt.zero) return null;
    lambda = _mod((BigInt.from(3) * p.x * p.x + _a) * _inv(BigInt.two * p.y));
  } else {
    lambda = _mod((q.y - p.y) * _inv(q.x - p.x));
  }
  final x = _mod(lambda * lambda - p.x - q.x);
  final y = _mod(lambda * (p.x - x) - p.y);
  return _Pt(x, y);
}

_Pt? _mul(BigInt k, _Pt p) {
  _Pt? result;
  _Pt? addend = p;
  var e = k;
  while (e > BigInt.zero) {
    if (e.isOdd) result = _add(result, addend);
    addend = _add(addend, addend);
    e >>= 1;
  }
  return result;
}

bool _onCurve(BigInt x, BigInt y) {
  if (x.isNegative || y.isNegative || x >= _p || y >= _p) return false;
  return _mod(y * y) == _mod(x * x * x + _a * x + _b);
}

Uint8List _bigToBytes(BigInt v, [int len = 32]) {
  final out = Uint8List(len);
  var t = v;
  for (var i = len - 1; i >= 0; i--) {
    out[i] = (t & BigInt.from(0xff)).toInt();
    t >>= 8;
  }
  return out;
}

BigInt _bytesToBig(List<int> b) {
  var r = BigInt.zero;
  for (final v in b) {
    r = (r << 8) | BigInt.from(v);
  }
  return r;
}

// ---- identity ---------------------------------------------------------------

/// Public JWK of a device: only `kty, crv, x, y` (what `/me/e2ee-key` stores).
typedef PublicJwk = Map<String, dynamic>;

PublicJwk pickPublic(Map<String, dynamic> jwk) => {'kty': jwk['kty'], 'crv': jwk['crv'], 'x': jwk['x'], 'y': jwk['y']};

bool samePublicKey(Map<String, dynamic>? a, Map<String, dynamic>? b) => a != null && b != null && a['x'] == b['x'] && a['y'] == b['y'];

/// True if [jwk] is a valid P-256 point.
bool isValidPublicJwk(Object? jwk) {
  if (jwk is! Map || jwk['kty'] != 'EC' || jwk['crv'] != 'P-256' || jwk['x'] is! String || jwk['y'] is! String) return false;
  try {
    final x = b64urlDecode(jwk['x'] as String);
    final y = b64urlDecode(jwk['y'] as String);
    return x.length == 32 && y.length == 32 && _onCurve(_bytesToBig(x), _bytesToBig(y));
  } catch (_) {
    return false;
  }
}

/// This device's ECDH key pair. [toStorage] holds the private scalar - keep it in the secure storage only.
class E2eeIdentity {
  E2eeIdentity._(this._d, this.publicJwk);
  final BigInt _d;
  final PublicJwk publicJwk;

  static E2eeIdentity generate({Random? random}) {
    final rnd = random ?? Random.secure();
    while (true) {
      final bytes = Uint8List.fromList(List<int>.generate(32, (_) => rnd.nextInt(256)));
      final d = _bytesToBig(bytes);
      if (d > BigInt.zero && d < _n) return fromScalar(d);
    }
  }

  static E2eeIdentity fromScalar(BigInt d) {
    final q = _mul(d, _Pt(_gx, _gy))!;
    return E2eeIdentity._(d, {'kty': 'EC', 'crv': 'P-256', 'x': b64urlEncode(_bigToBytes(q.x)), 'y': b64urlEncode(_bigToBytes(q.y))});
  }

  /// From a private JWK (`d` present), e.g. exported by WebCrypto.
  static E2eeIdentity fromPrivateJwk(Map<String, dynamic> jwk) => fromScalar(_bytesToBig(b64urlDecode(jwk['d'] as String)));

  String toStorage() => jsonEncode({'v': 1, 'd': b64urlEncode(_bigToBytes(_d)), ...publicJwk});

  static E2eeIdentity? fromStorage(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final id = fromPrivateJwk(m);
      // A corrupted blob must not silently become a different key.
      return samePublicKey(id.publicJwk, m) ? id : null;
    } catch (_) {
      return null;
    }
  }

  /// ECDH shared secret: the x coordinate, 32 bytes (WebCrypto `deriveBits(..., 256)`).
  Uint8List sharedSecret(Map<String, dynamic> peerJwk) {
    if (!isValidPublicJwk(peerJwk)) throw ArgumentError('invalid peer key');
    final pt = _Pt(_bytesToBig(b64urlDecode(peerJwk['x'] as String)), _bytesToBig(b64urlDecode(peerJwk['y'] as String)));
    final s = _mul(_d, pt);
    if (s == null) throw StateError('ECDH failed');
    return _bigToBytes(s.x);
  }
}

/// 20 hex characters of SHA-256(`x.y`) in groups of five, e.g. `1DEFA-E7662-4B147-83C46` (crypto.js `fingerprint`).
Future<String> fingerprint(Map<String, dynamic> jwk) async {
  final hash = await Sha256().hash(utf8.encode('${jwk['x']}.${jwk['y']}'));
  final hex = hash.bytes.take(10).map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
  return [for (var i = 0; i < hex.length; i += 5) hex.substring(i, i + 5)].join('-');
}

final _info = utf8.encode('mamba-e2ee-v1');

/// Raw 32-byte AES key shared by [myId] and [peerId].
Future<Uint8List> deriveSessionKey(E2eeIdentity me, Map<String, dynamic> peerJwk, String myId, String peerId) async {
  final bits = me.sharedSecret(peerJwk);
  final ids = [myId, peerId]..sort();
  final salt = (await Sha256().hash(utf8.encode(ids.join('|')))).bytes;
  final key = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(secretKey: SecretKey(bits), nonce: salt, info: _info);
  return Uint8List.fromList(await key.extractBytes());
}

// ---- AES-GCM ----------------------------------------------------------------

List<int> _aad(String from, String to, String id) => utf8.encode('$from|$to|$id');

/// `iv` and `ct` as standard base64 (ct = ciphertext || 16-byte tag).
class Envelope {
  const Envelope(this.iv, this.ct);
  final String iv;
  final String ct;
}

const _isolateThreshold = 150000;

Future<Uint8List> _seal(Uint8List key, Uint8List iv, Uint8List plain, List<int> aad) async {
  final box = await AesGcm.with256bits().encrypt(plain, secretKey: SecretKey(key), nonce: iv, aad: aad);
  final out = Uint8List(box.cipherText.length + box.mac.bytes.length)
    ..setRange(0, box.cipherText.length, box.cipherText)
    ..setRange(box.cipherText.length, box.cipherText.length + box.mac.bytes.length, box.mac.bytes);
  return out;
}

Future<Uint8List> _open(Uint8List key, Uint8List iv, Uint8List ct, List<int> aad) async {
  if (ct.length < 16) throw const FormatException('ciphertext too short');
  final box = SecretBox(ct.sublist(0, ct.length - 16), nonce: iv, mac: Mac(ct.sublist(ct.length - 16)));
  return Uint8List.fromList(await AesGcm.with256bits().decrypt(box, secretKey: SecretKey(key), aad: aad));
}

/// Encrypts [plain]. A fixed [iv] exists for test vectors only; production code leaves it null (random).
Future<Envelope> encryptBytes(Uint8List key, Uint8List plain, {required String from, required String to, required String id, Uint8List? iv}) async {
  final nonce = iv ?? Uint8List.fromList(List<int>.generate(12, (_) => Random.secure().nextInt(256)));
  final aad = _aad(from, to, id);
  final ct = plain.length > _isolateThreshold ? await Isolate.run(() => _seal(key, nonce, plain, aad)) : await _seal(key, nonce, plain, aad);
  return Envelope(b64encode(nonce), b64encode(ct));
}

Future<Uint8List> decryptBytes(Uint8List key, Envelope env, {required String from, required String to, required String id}) async {
  final iv = b64decode(env.iv);
  final ct = b64decode(env.ct);
  final aad = _aad(from, to, id);
  return ct.length > _isolateThreshold ? Isolate.run(() => _open(key, iv, ct, aad)) : _open(key, iv, ct, aad);
}

// ---- plaintext frame --------------------------------------------------------

/// Decoded plaintext of one message (crypto.js `unpackMessage`). [kind] is `'screenshot'` for a system notice.
class PackedMessage {
  const PackedMessage({required this.text, required this.ts, this.att, this.kind, this.group, required this.file});
  final String text;
  final int ts;
  final Map<String, dynamic>? att;
  final String? kind;

  /// Group header (`g`): `{i: id, n: name, c: creator, u: updatedAt, m: [[id, name], ...]}`; null for a 1:1 message.
  final Map<String, dynamic>? group;
  final Uint8List file;
}

Uint8List packMessage({String text = '', required int ts, Map<String, dynamic>? att, String? kind, Map<String, dynamic>? group, Uint8List? file}) {
  final header = utf8.encode(jsonEncode({'v': 1, 't': text, 'ts': ts, 'a': att, 'k': ?kind, 'g': ?group}));
  final out = Uint8List(4 + header.length + (file?.length ?? 0));
  ByteData.sublistView(out).setUint32(0, header.length);
  out.setRange(4, 4 + header.length, header);
  if (file != null) out.setRange(4 + header.length, out.length, file);
  return out;
}

PackedMessage unpackMessage(Uint8List bytes) {
  if (bytes.length < 4) throw const FormatException('bad frame');
  final len = ByteData.sublistView(bytes).getUint32(0);
  if (len > bytes.length - 4) throw const FormatException('bad frame');
  final header = jsonDecode(utf8.decode(bytes.sublist(4, 4 + len))) as Map<String, dynamic>;
  if (header['v'] != 1) throw const FormatException('unsupported version');
  final ts = header['ts'];
  final att = header['a'];
  final k = header['k'];
  final g = header['g'];
  return PackedMessage(
    text: (header['t'] ?? '').toString(),
    ts: ts is num && ts != 0 ? ts.toInt() : DateTime.now().millisecondsSinceEpoch,
    att: att is Map<String, dynamic> ? att : null,
    kind: k == null || k == '' ? null : k.toString(),
    group: g is Map<String, dynamic> ? g : null,
    file: Uint8List.sublistView(bytes, 4 + len),
  );
}

/// 16 random bytes as base64url without padding (22 chars); the server accepts `[A-Za-z0-9_-]{8,64}`.
String newMessageId([Random? random]) {
  final rnd = random ?? Random.secure();
  return b64urlEncode(List<int>.generate(16, (_) => rnd.nextInt(256)));
}
