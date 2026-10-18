/// Comma handling for typed numbers ("1,5" is 1.5, "1,500" is 1500, "1.234,5" is 1234.5).
///
/// A number-like text (only digits, `.`, `,`, `-`, spaces) is rewritten with a plain `.` decimal point; anything else is
/// returned unchanged. A last comma followed by 1-2 digits is a decimal comma (or "0,xxx"); every other comma is a
/// thousands separator and is dropped.
String normalizeNumberText(String s) {
  if (!s.contains(',')) return s;
  final t = s.trim();
  if (!RegExp(r'^-?[\d.,\s]+$').hasMatch(t)) return s;
  final last = t.lastIndexOf(',');
  final tail = t.substring(last + 1);
  final head = t.substring(0, last);
  if (t.lastIndexOf('.') > last) return t.replaceAll(',', ''); // "1,234.5": comma = thousands
  final headDigits = head.replaceAll(RegExp(r'[^\d]'), '');
  final zeroHead = headDigits.replaceFirst(RegExp(r'^0+'), '').isEmpty;
  final decimal = RegExp(r'^\d{1,2}$').hasMatch(tail) || (RegExp(r'^\d+$').hasMatch(tail) && zeroHead);
  if (decimal) {
    final neg = head.trimLeft().startsWith('-') ? '-' : '';
    return '$neg${headDigits.isEmpty ? '0' : headDigits}.$tail';
  }
  return t.replaceAll(',', '');
}
