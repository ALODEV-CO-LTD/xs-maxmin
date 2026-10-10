import 'dart:convert';
import 'dart:typed_data';

import 'package:server/src/attachments.dart';
import 'package:test/test.dart';

// Real pictures made with Pillow, each carrying EXIF/GPS, text, comment, XMP and ICC data
// (the words "TestPhone", "Nguyen", "PhoneCam", "secret comment" mark the metadata).
const _jpeg = '/9j/4AAQSkZJRgABAQAAAQABAAD/4QCoRXhpZgAATU0AKgAAAAgABAEPAAIAAAAPAAAAPgEQAAIAAAAIAAAATgEyAAIAAAAUAAAAVoglAAQAAAABAAAAagAAAABUZXN0UGhvbmUgQ29ycAAATW9kZWwtWAAyMDI2OjEwOjA5IDEyOjM0OjU2AAACAAEAAgAAAAJOAAAAAAIABQAAAAMAAACIAAAAAAAAAAoAAAABAAAALgAAAAEAAAAMAAAAAf/iAOVJQ0NfUFJPRklMRQABAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAVGVzdFBob25lLUlDQ//+ABBzZWNyZXQgY29tbWVudP/bAEMACAYGBwYFCAcHBwkJCAoMFA0MCwsMGRITDxQdGh8eHRocHCAkLicgIiwjHBwoNyksMDE0NDQfJzk9ODI8LjM0Mv/bAEMBCQkJDAsMGA0NGDIhHCEyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMv/AABEIADwAUAMBIgACEQEDEQH/xAAfAAABBQEBAQEBAQAAAAAAAAAAAQIDBAUGBwgJCgv/xAC1EAACAQMDAgQDBQUEBAAAAX0BAgMABBEFEiExQQYTUWEHInEUMoGRoQgjQrHBFVLR8CQzYnKCCQoWFxgZGiUmJygpKjQ1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4eLj5OXm5+jp6vHy8/T19vf4+fr/xAAfAQADAQEBAQEBAQEBAAAAAAAAAQIDBAUGBwgJCgv/xAC1EQACAQIEBAMEBwUEBAABAncAAQIDEQQFITEGEkFRB2FxEyIygQgUQpGhscEJIzNS8BVictEKFiQ04SXxFxgZGiYnKCkqNTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqCg4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2dri4+Tl5ufo6ery8/T19vf4+fr/2gAMAwEAAhEDEQA/APDEt/arKW/tVxLf2qylv7U4silXKaW/tVlLf2q4lv7VZS39q3iz06Vcppb+1WUt/ariW/tVlLf2reLPTpVymlv7VZS39quJb+1WUt/at4s9OlXKaW/tVlLf2q4lv7VZS39q3iz06Vc4JLf2qylv7VcS39qspb+1fPRZ+M0q5TS39qspb+1XEt/arKW/tXRFnp0q5TS39qspb+1XEt/arKW/tW8WenSrlNLf2qylv7VcS39qspb+1bxZ6dKuU0t/arKW/tVxLf2qylv7VvFnp0q5wSW/tVlLf2q4lv7VZS39q+eiz8YpVymlv7VZS39quJb+1WUt/at4s9OlXKaW/tVlLf2q4lv7VZS39q3iz06Vcppb+1WUt/ariW/tVlLf2reLPTpVymlv7VZS39quJb+1WUt/at4s9OlXODS39qspb+1WI0X0qzGi+lfPRZ+NUqzK6W/tVlLf2qxGi+lWY0X0reLPUpVmV0t/arKW/tViNF9KsxovpXRFnp0qzK6W/tVlLf2qxGi+lWY0X0reLPTpVmV0t/ao7h9uY4/vd29Ku3JMUAKcEnGapoi+lfLcSZ1Uw3+yUdG1dvy7L/P7j2sHK/vM/9k=';
const _progressiveJpeg = '/9j/4AAQSkZJRgABAQAAAQABAAD/4QCoRXhpZgAATU0AKgAAAAgABAEPAAIAAAAPAAAAPgEQAAIAAAAIAAAATgEyAAIAAAAUAAAAVoglAAQAAAABAAAAagAAAABUZXN0UGhvbmUgQ29ycAAATW9kZWwtWAAyMDI2OjEwOjA5IDEyOjM0OjU2AAACAAEAAgAAAAJOAAAAAAIABQAAAAMAAACIAAAAAAAAAAoAAAABAAAALgAAAAEAAAAMAAAAAf/bAEMACAYGBwYFCAcHBwkJCAoMFA0MCwsMGRITDxQdGh8eHRocHCAkLicgIiwjHBwoNyksMDE0NDQfJzk9ODI8LjM0Mv/bAEMBCQkJDAsMGA0NGDIhHCEyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMv/CABEIADwAUAMBIgACEQEDEQH/xAAXAAEBAQEAAAAAAAAAAAAAAAADBQIG/8QAGQEAAwEBAQAAAAAAAAAAAAAAAgMEBQYA/9oADAMBAAIQAxAAAAHhVZPCKsjKhVkOkVZGVCrIdMFGXP4wUZWVCjKdIoysqFGU6YCsmfxgqyHSKsjKhVkOkVZGVQVRM7jDVEZUaojKjVEOk8uOXb//xAAYEAEBAQEBAAAAAAAAAAAAAAAAEgECIf/aAAgBAQABBQKUpSlKUpSlKUpSlKUpSlKUpSlKUpSlKUpSlKUpSlKUpSlKUpSlKUpSlKUpdMYxjGMY68x//8QAGBEBAQADAAAAAAAAAAAAAAAAAgABA0H/2gAIAQMBAT8BLi4uLi4uLi4uLi4uLi4uLi4uLtOe3//EABoRAQEAAgMAAAAAAAAAAAAAAAABAgMEBSP/2gAIAQIBAT8BiIiIiIiIiIiIjsublr8sH//EABcQAAMBAAAAAAAAAAAAAAAAAAERMGD/2gAIAQEABj8CwqE//8QAGBABAQEBAQAAAAAAAAAAAAAAAQBREUH/2gAIAQEAAT8hIQhCEIQhCEIQhCEIQhCEIQhCEIQhCEIQhCEIQhCEIQhCEIQhCEIQhCEIQi5psCBAgQIECBeGAv/aAAwDAQACAAMAAAAQnknknZYbYbknknknlknx/8QAGBEBAQADAAAAAAAAAAAAAAAAAAERITD/2gAIAQMBAT8Q7/8A/wD/AP2WWWZNn//EABsRAQEAAQUAAAAAAAAAAAAAAAEAEUFRYZHR/9oACAECAQE/EFKUpSlKUpSlKUpSlaDKZXjY96v/xAAaEAEBAQEBAQEAAAAAAAAAAAAAYVEBESFx/9oACAEBAAE/EJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJPq/RhiYmJiYmJiYnfeffnve+esz//Z';
const _png = 'iVBORw0KGgoAAAANSUhEUgAAAFAAAAA8CAIAAAB+RarbAAAAJWlDQ1BJQ0MgUHJvZmlsZQAAeJwLSS0uCcjIz0vV9XR2ZiAZAAAIEQSXRTB7SQAAABN0RVh0QXV0aG9yAE5ndXllbiBWYW4gQVOz7tYAAAARdEVYdFNvZnR3YXJlAFBob25lQ2FtK6YqGwAAAHJJREFUeJztzwENgAAQxLBnzL9mfBxLaqDP3b3Hf3hy9yMWZpuF2WZhtlmYbRZmm4XZZmG2WZhtFmabhdlmYbZZmG0WZpuF2WZhtlmYbRZmm4XZZmG2WZhtFmabhdlmYbZZmG0WZpuF2WZhtlmYbRZm2wce6ihFxwsneAAAAABJRU5ErkJggg==';
const _webp = 'UklGRioCAABXRUJQVlA4WAoAAAAsAAAATwAAOwAASUNDUA0AAABUZXN0UGhvbmUtSUNDAFZQOCA2AQAAkAoAnQEqUAA8AD5tMJJGJCMuoaZ7/nnQDYliLYGJ5yQDzAfoB/AH/b4Rgn1HKBj6TGM23pBjulB8tubUivEQ4eFKPhY9UrhkLggQYPjanqsVQ//96++4IMx2zkwAAP77gdH/2hv//2Gs2g+VfvuZUdf6aW4GPW/+ggHxPZt1mJyP1T6XgfzcG3WK+2R1PZReBrD/U6plN/Z8JktdLVFAUsm2upvCrfRjjQkiSPHGSWBrnmjLZbAQtVstewZKa3BIWYkY8jSCYR08oyPIPxvLBERXUeMbRVMA3aKNTuAJAwikb/t+fHxsjDpKntn+544hXm4aEmAUsXWTwq+R2RQl1/3i9Dh0EoAJk2qWyAI4lFf/3/+gHnrBX/n/rb0/NLnf/r5+/Z/7/dp7pyP5fkzTsWj56QAAAEVYSUagAAAATU0AKgAAAAgABAEPAAIAAAAPAAAAPgEQAAIAAAAIAAAATgEyAAIAAAAUAAAAVoglAAQAAAABAAAAagAAAABUZXN0UGhvbmUgQ29ycAAATW9kZWwtWAAyMDI2OjEwOjA5IDEyOjM0OjU2AAACAAEAAgAAAAJOAAAAAAIABQAAAAMAAACIAAAAAAAAAAoAAAABAAAALgAAAAEAAAAMAAAAAVhNUCAQAAAAPHg+VGVzdFBob25lPC94Pg==';
const _animatedWebp = 'UklGRoQDAABXRUJQVlA4WAoAAAAKAAAATwAAOwAAQU5JTQYAAAAAAAAAAABBTk1GUAEAAAAAAAAAAE8AADsAAGQAAAJWUDggOAEAANAIAJ0BKlAAPAA+bTaWSCQjIiEhqvCADYlibZaXP/+sGIzywH9VeYD9JdoAqNgv0s/MgSvnOfjgsTEttjrM0f////2y/////wh///9idQAA/v9YXTk0JfLgowKyHiKob1T4mytDh28HN9M9wkkhbT8UTGUSJsjcbIulSfRdQBNS/VqnxxRv+uDzUfI2nM1eQtwU2LaW8HhaKYOHkyN/bqufjWPMR0c4mIVJ/Sc4nIv8lE2AFBYa5boDJYxr1mxIS9xor/QX/9VffjWP7+/uZUqhZRjoIT/4eptidysbax8pF/disSjJWdwr1Ye4XXoJgbxTFOOh3aP57zfFc+bCMhwP8eZTTOaFV3B9jLh5lNUkBCGNv3/+gHnrBX/n/rb0/NLgf/nz9+z/3+7T3Tkf5ECL9OfriSQAAEFOTUZSAQAAAAAAAAAATwAAOwAAZAAAAFZQOCA6AQAANAgAnQEqUAA8AD5tNJVJAjWAjgAA2JZm0xNzvbWDEdzgZ4B5QNhAsAQvzG/CfKAAJ1v//xUBIt8NLH////553////0Nb////vgAA/uw/YXvyb5x+Ocz0y2nf/ggdfzGx//3PQtxEmsYgD6uu2fL3fZRc9ZGA9UnQkfpRcKFuM81j7KH8Pf/1TIpoXD6Uz1+MxO50F0zXFdfoER4CxB//mD8yA5TFEd/u/AN+NlqP2FwEt32vTjNTmV7QSnCe92exw32UeUNZSvxN//QbyPxstR+wt/mcItsrQ20l3ANlud5vcM1dGy87jLiwWfO91wNFnERCFaI3C7hLKfpYpJVo/5gajgT/y55Y+z8/9FO7eV/zABvn/tA+/Y/7/9ZrnhguH+OR3ANisN0efCbBVawCqUYTI8sOj4jAAABFWElGpgAAAEV4aWYAAE1NACoAAAAIAAQBDwACAAAADwAAAD4BEAACAAAACAAAAE4BMgACAAAAFAAAAFaIJQAEAAAAAQAAAGoAAAAAVGVzdFBob25lIENvcnAAAE1vZGVsLVgAMjAyNjoxMDowOSAxMjozNDo1NgAAAgABAAIAAAACTgAAAAACAAUAAAADAAAAiAAAAAAAAAAKAAAAAQAAAC4AAAABAAAADAAAAAE=';

const _markers = ['Exif', 'TestPhone', 'secret comment', 'Nguyen', 'PhoneCam', 'XMP', 'ICC', 'EXIF'];

bool _leaks(Uint8List b) {
  final s = String.fromCharCodes(b);
  return _markers.any(s.contains);
}

Map<String, dynamic> _upload(List<int> bytes, {String name = 'IMG_20261009_123456.jpg', String type = 'image/jpeg'}) =>
    {'name': name, 'type': type, 'data': base64Encode(bytes)};

void main() {
  for (final entry in {'JPEG': _jpeg, 'progressive JPEG': _progressiveJpeg, 'PNG': _png, 'WebP': _webp, 'animated WebP': _animatedWebp}.entries) {
    test('${entry.key}: all metadata removed, picture kept', () {
      final input = base64Decode(entry.value);
      expect(_leaks(input), isTrue, reason: 'fixture must carry metadata');
      final out = sanitizeImage(input)!;
      expect(_leaks(out), isFalse);
      expect(out.length, lessThan(input.length));
      expect(imageKind(out), imageKind(input));
    });
  }

  test('parseAttachment: random name and type from the bytes, whatever the client says', () {
    final p = parseAttachment(_upload(base64Decode(_png), name: 'Nguyen-Van-A-iPhone.pdf', type: 'application/pdf')).attachment!;
    expect(p.type, 'image/png');
    expect(RegExp(r'^anh-[0-9a-f]{10}\.png$').hasMatch(p.name), isTrue, reason: p.name);
    expect(_leaks(p.data), isFalse);
    final q = parseAttachment(_upload(base64Decode(_webp))).attachment!;
    expect(q.type, 'image/webp');
    expect(q.name.endsWith('.webp'), isTrue);
    expect(_leaks(q.data), isFalse);
  });

  test('GIF, PDF, zip, text and empty files are refused', () {
    final gif = [...'GIF89a'.codeUnits, 1, 0, 1, 0, 0, 0, 0, 0x3B];
    for (final bytes in [gif, '%PDF-1.4 /Author (X)'.codeUnits, [0x50, 0x4B, 3, 4, 0, 0], 'hello'.codeUnits]) {
      expect(parseAttachment(_upload(bytes)).error, isNotNull);
    }
    expect(parseAttachment(_upload(const [])).error, isNotNull);
    expect(parseAttachment(null).attachment, isNull);
    expect(parseAttachment(null).error, isNull);
  });

  test('declared as an image but not a valid one: refused (never stored as-is)', () {
    final truncated = base64Decode(_jpeg).sublist(0, 400); // no EOI
    expect(parseAttachment(_upload(truncated)).error, isNotNull);
    expect(parseAttachment(_upload([0xFF, 0xD8, 0xFF, 0xE1, 0xFF, 0xFF, 1, 2, 3])).error, isNotNull);
    expect(sanitizeImage(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 5])), isNull);
  });

  test('data hidden after the end of the picture is dropped', () {
    final tail = [...base64Decode(_jpeg), ...'TestPhone-hidden-tail'.codeUnits];
    final out = sanitizeImage(Uint8List.fromList(tail))!;
    expect(String.fromCharCodes(out).contains('hidden-tail'), isFalse);
  });

  test('over 5 MB is refused', () {
    final big = Uint8List(maxAttachmentBytes + 1)..setRange(0, 3, [0xFF, 0xD8, 0xFF]);
    expect(parseAttachment(_upload(big)).error, isNotNull);
  });
}
