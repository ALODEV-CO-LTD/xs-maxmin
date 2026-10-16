// Shared between EntriesView (pick a type per entry), ScoringView (look up
// the right payout rate/tiers per entry) and ScoringSettingsView (manage
// the type -> {rate, tiers} map). Known keys get a Vietnamese label; a
// user-added custom key just displays as typed.
export const KNOWN_LABELS = { de: 'Đề', lo: 'Lô', lo3: 'Bao lô 3 số', lo4: 'Bao lô 4 số', truot4: 'Trượt xiên 4', truot8: 'Trượt xiên 8', truot10: 'Trượt xiên 10', tai_xiu: 'Tài/Xỉu', chan_le: 'Chẵn/Lẻ', dau: 'Đầu', duoi: 'Đuôi', cang3: '3 càng', cang4: '4 càng', xien2: 'Xiên 2', xien3: 'Xiên 3', xien4: 'Xiên 4' }

export function betTypeLabel(key) {
  if (!key) return ''
  return KNOWN_LABELS[key] || key
}

// The 8 prize groups a lottery_results row is split into (see
// backend/routes/api/lottery-results) - a bet type's config picks which of
// these its numbers get compared against (see ScoringSettingsView).
export const PRIZE_TIERS = [
  { key: 'dacBiet', label: 'Đặc biệt' },
  { key: 'giaiNhat', label: 'Giải nhất' },
  { key: 'giaiNhi', label: 'Giải nhì' },
  { key: 'giaiBa', label: 'Giải ba' },
  { key: 'giaiTu', label: 'Giải tư' },
  { key: 'giaiNam', label: 'Giải năm' },
  { key: 'giaiSau', label: 'Giải sáu' },
  { key: 'giaiBay', label: 'Giải bảy' },
  { key: 'giaiTam', label: 'Giải tám (MN, MT)' },
]

export function tierLabel(key) {
  return PRIZE_TIERS.find((t) => t.key === key)?.label || key
}
