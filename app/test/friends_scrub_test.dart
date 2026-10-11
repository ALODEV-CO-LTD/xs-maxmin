import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mamba_app/features/friends/chat_models.dart';
import 'package:mamba_app/features/friends/image_scrub.dart';

void main() {
  test('scrubImage drops EXIF/GPS and keeps the pixels', () async {
    final src = img.Image(width: 40, height: 20);
    img.fill(src, color: img.ColorRgb8(200, 30, 30));
    src.exif.gpsIfd.data[0x0002] = img.IfdValueAscii('10.77N');
    src.exif.imageIfd.make = 'SecretPhone';
    final jpg = Uint8List.fromList(img.encodeJpg(src));
    expect(String.fromCharCodes(jpg), contains('SecretPhone')); // the input really carries metadata

    final out = await scrubImage(jpg);
    expect(out.type, 'image/jpeg');
    expect(String.fromCharCodes(out.bytes), isNot(contains('SecretPhone')));
    final back = img.decodeJpg(out.bytes)!;
    expect(back.exif.isEmpty, isTrue);
    expect((back.width, back.height), (40, 20));
    expect(back.getPixel(5, 5).r, greaterThan(150));
  });

  test('PNG stays PNG; GIF and garbage are refused', () async {
    final png = Uint8List.fromList(img.encodePng(img.Image(width: 8, height: 8)));
    expect((await scrubImage(png)).type, 'image/png');
    expect(scrubImage(Uint8List.fromList('GIF89a....'.codeUnits)), throwsA(predicate((e) => e.toString().contains(imageOnlyMessage))));
    expect(scrubImage(Uint8List.fromList([0xff, 0xd8, 0xff, 1, 2, 3])), throwsException);
  });
}
