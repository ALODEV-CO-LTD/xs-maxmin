import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import 'lottery_columns.dart';
import '../../core/photo_errors.dart';

/// What the reader found in a photo.
class OcrResult {
  const OcrResult(this.text, this.words);
  final String text;
  final List<OcrWord> words;
}

/// Reads a photo on the device with ML Kit (Latin model, bundled: works offline, nothing is uploaded).
class OcrService {
  final ImagePicker _picker = ImagePicker();

  /// Asks the user for a photo ([camera] = take one, else pick from the gallery); null when cancelled.
  Future<String?> pick({required bool camera}) async {
    final f = await _picker.pickImage(source: camera ? ImageSource.camera : ImageSource.gallery);
    return f?.path;
  }

  Future<OcrResult> read(String path) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final text = await recognizer.processImage(InputImage.fromFilePath(path));
      final words = <OcrWord>[];
      for (final b in text.blocks) {
        for (final l in b.lines) {
          for (final e in l.elements) {
            final r = e.boundingBox;
            words.add(OcrWord(e.text, r.left, r.top, r.right, r.bottom));
          }
        }
      }
      return OcrResult(text.text, words);
    } finally {
      await recognizer.close();
    }
  }
}

/// The sentence shown for any failure of the reader.
String describeOcrError(Object err) {
  final photo = describePhotoError(err);
  if (photo != null) return photo;
  final t = '$err';
  if (RegExp(r'memory|OutOfMemory', caseSensitive: false).hasMatch(t)) {
    return 'Ảnh quá lớn hoặc thiết bị không đủ bộ nhớ để đọc. Hãy chụp hoặc cắt ảnh nhỏ hơn rồi thử lại.';
  }
  if (RegExp(r'permission|denied', caseSensitive: false).hasMatch(t)) {
    return 'Ứng dụng chưa được cấp quyền dùng máy ảnh hoặc ảnh. Hãy cấp quyền trong Cài đặt rồi thử lại.';
  }
  return 'Không đọc được ảnh. Bạn có thể chọn ảnh khác hoặc nhập tay.';
}
