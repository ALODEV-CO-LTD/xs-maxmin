/// Shared by Nhập số, Nhập kết quả, Tính điểm and the scoring settings (port of frontend/src/betTypes.js).
const knownBetLabels = {'de': 'Đề', 'lo': 'Lô', 'dau': 'Đầu', 'duoi': 'Đuôi', 'cang3': '3 càng', 'cang4': '4 càng', 'lo3': 'Bao lô 3 số', 'lo4': 'Bao lô 4 số', 'truot4': 'Trượt xiên 4', 'truot8': 'Trượt xiên 8', 'truot10': 'Trượt xiên 10', 'tai_xiu': 'Tài/Xỉu', 'chan_le': 'Chẵn/Lẻ', 'xien2': 'Xiên 2', 'xien3': 'Xiên 3', 'xien4': 'Xiên 4'};

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
