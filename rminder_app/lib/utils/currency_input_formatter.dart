import 'package:flutter/services.dart';

/// A TextInputFormatter that treats the input as a stream of digits and always
/// formats it as a fixed 2-decimal currency string.
///
/// Examples (user types):
/// - "3"   -> 0.03
/// - "34"  -> 0.34
/// - "346" -> 3.46
/// - "3465"-> 34.65
///
/// Non-digit characters are ignored. Selection is moved to the end.
class CurrencyInputFormatter extends TextInputFormatter {
  CurrencyInputFormatter({this.maxDigits = 12});

  /// Maximum number of digits to keep (before decimals). This prevents overly
  /// large values and performance issues. Does not include the decimal places.
  final int maxDigits;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digitsOnly = _extractDigits(newValue.text);
    final limited = digitsOnly.length > maxDigits + 2
        ? digitsOnly.substring(digitsOnly.length - (maxDigits + 2))
        : digitsOnly;

    final formatted = _formatAsCurrency(limited);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
      composing: TextRange.empty,
    );
  }

  String _extractDigits(String input) {
    final sb = StringBuffer();
    for (final ch in input.codeUnits) {
      if (ch >= 48 && ch <= 57) sb.writeCharCode(ch); // '0'..'9'
    }
    return sb.toString();
  }

  String _formatAsCurrency(String digits) {
    if (digits.isEmpty) return '0.00';

    // Ensure at least 3 digits so we always have two decimals
    final padded = digits.padLeft(3, '0');
    final len = padded.length;
    final integerPart = padded.substring(0, len - 2).replaceFirst(RegExp(r'^0+(?!$)'), '');
    final fractionPart = padded.substring(len - 2);
    return '${integerPart.isEmpty ? '0' : integerPart}.$fractionPart';
  }
}
