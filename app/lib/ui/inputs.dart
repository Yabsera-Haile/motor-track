import 'package:flutter/services.dart';

import '../format.dart';

/// Shows 6000 as "6,000" while typing. Use after FilteringTextInputFormatter.digitsOnly.
class ThousandsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final n = int.tryParse(newValue.text);
    if (n == null) return newValue.copyWith(text: '');
    final text = rwf(n);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
