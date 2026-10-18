import 'package:flutter/services.dart';

/// Keyboard for number fields (Số, Điểm, hạn mức...). On iPhone this is the phone's NORMAL system keyboard on its
/// "numbers and punctuation" layer (has the return key and a switch back to letters, and `.` `-`), not the bare numeric pad
/// that has no letters and no way to close it. On Android it is the number keyboard with `.` and `-`.
const kNumbersKeyboard = TextInputType.numberWithOptions(signed: true, decimal: true);

/// With the normal keyboard the person can switch to letters, so number fields keep only number characters
/// (digits, `.` `,` `-`; xiên numbers are written `22.67`).
final kNumberCharsOnly = <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]'))];
final kDigitsOnly = <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly];
