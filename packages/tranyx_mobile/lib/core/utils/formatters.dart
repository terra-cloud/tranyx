import 'package:flutter/services.dart';

/// Formatter for Philippine Business Permit (BIN)
/// Format: YYYY-NNNNNNN (e.g. 2024-1234567)
class BusinessPermitFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.length < oldValue.text.length) {
      return newValue;
    }

    final text = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    var result = '';

    for (int i = 0; i < text.length; i++) {
      if (i == 4) result += '-';
      if (i < 11) result += text[i];
    }

    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: result.length),
    );
  }
}
