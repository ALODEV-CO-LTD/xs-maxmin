import 'package:server/src/text_fold.dart';
import 'package:test/test.dart';

void main() {
  test('strips Vietnamese diacritics and lower-cases', () {
    expect(foldVi('Đỗ Ngọc Mai'), 'do ngoc mai');
    expect(foldVi('Trần Thị Hương'), 'tran thi huong');
    expect(foldVi('NGUYỄN VĂN A'), 'nguyen van a');
    expect(foldVi('Lê Thị Bình'), 'le thi binh');
  });

  test('plain ASCII is only lower-cased', () {
    expect(foldVi('ABC xyz 123'), 'abc xyz 123');
  });

  test('decomposed (NFD) input folds the same way', () {
    // "ỗ" written as o + circumflex + tilde combining marks
    expect(foldVi('Dỗ'), 'do');
  });
}
