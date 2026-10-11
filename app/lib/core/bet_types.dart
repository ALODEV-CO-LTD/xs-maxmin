/// Shared by Nhập số, Nhập kết quả, Tính điểm and the scoring settings (port of frontend/src/betTypes.js).
const knownBetLabels = {'de': 'Đề', 'lo': 'Lô'};

String betTypeLabel(String? key) {
  if (key == null || key.isEmpty) return '';
  return knownBetLabels[key] ?? key;
}

/// The prize groups a lottery result is split into; a bet type's config picks which ones its numbers are checked against.
class PrizeTier {
  const PrizeTier(this.key, this.label);
  final String key;
  final String label;
}

const prizeTiers = [
  PrizeTier('dacBiet', 'Đặc biệt'),
  PrizeTier('giaiNhat', 'Giải nhất'),
  PrizeTier('giaiNhi', 'Giải nhì'),
  PrizeTier('giaiBa', 'Giải ba'),
  PrizeTier('giaiTu', 'Giải tư'),
  PrizeTier('giaiNam', 'Giải năm'),
  PrizeTier('giaiSau', 'Giải sáu'),
  PrizeTier('giaiBay', 'Giải bảy'),
  PrizeTier('giaiTam', 'Giải tám (MN, MT)'),
];

String tierLabel(String key) {
  for (final t in prizeTiers) {
    if (t.key == key) return t.label;
  }
  return key;
}
