/// Optional phone number on a customer: digits with an optional leading +,
/// spaces, dots, dashes and parentheses are tolerated, 6-20 chars once
/// trimmed. Returns the cleaned string, '' for "none", or null if invalid.
String? normalizePhone(Object? raw) {
  if (raw == null) return '';
  final s = raw.toString().trim();
  if (s.isEmpty) return '';
  if (s.length > 20 || !RegExp(r'^\+?[\d\s().-]+$').hasMatch(s)) return null;
  if (s.replaceAll(RegExp(r'\D'), '').length < 6) return null;
  return s;
}
