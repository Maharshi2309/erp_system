/// Field validators shared by forms and imports, so both apply the same
/// rules (PRD §7.2, D-78). Phone rules follow Indian numbering.
abstract final class Validators {
  static final _email = RegExp(
    r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)*\.[A-Za-z]{2,}$",
  );

  static bool isEmail(String value) {
    final v = value.trim();
    return v.length <= 254 &&
        !v.contains('..') &&
        !v.startsWith('.') &&
        !v.contains('.@') &&
        _email.hasMatch(v);
  }

  /// The 10-digit national number, without +91, 91 or a leading 0;
  /// null when the text isn't a phone number of that shape. Spaces,
  /// dashes and brackets are allowed.
  static String? nationalNumber(String value) {
    final v = value.trim();
    if (v.isEmpty || !RegExp(r'^[+\d\s\-().]+$').hasMatch(v)) return null;
    var digits = v.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 12 && digits.startsWith('91')) {
      digits = digits.substring(2);
    } else if (digits.length == 11 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return digits.length == 10 ? digits : null;
  }

  /// An Indian mobile number: 10 digits starting 6–9.
  static bool isMobile(String value) =>
      RegExp(r'^[6-9]\d{9}$').hasMatch(nationalNumber(value) ?? '');

  /// A mobile or landline (STD code + number, 10 digits, not starting 0/1).
  static bool isPhone(String value) =>
      RegExp(r'^[2-9]\d{9}$').hasMatch(nationalNumber(value) ?? '');

  /// Letters (any script), spaces, dots, apostrophes and hyphens; must
  /// contain a letter; up to [max] characters.
  static bool isPersonName(String value, {int max = 50}) {
    final v = value.trim();
    return v.isNotEmpty &&
        v.length <= max &&
        RegExp(r"^[\p{L}\p{M}][\p{L}\p{M} .'\-]*$", unicode: true).hasMatch(v);
  }

  /// Free text such as a designation: has a letter, not only digits or
  /// symbols, between [min] and [max] characters.
  static bool isLabel(String value, {int min = 2, int max = 60}) {
    final v = value.trim();
    return v.length >= min &&
        v.length <= max &&
        RegExp(r'\p{L}', unicode: true).hasMatch(v);
  }

  /// Indian PIN code: 6 digits, not starting with 0.
  static bool isPin(String value) =>
      RegExp(r'^[1-9]\d{5}$').hasMatch(value.trim());

  /// The phone number written inside free text such as an emergency
  /// contact ("Ravi Shah, +91 98250 12345"), or null.
  static String? phoneIn(String text) {
    for (final m in RegExp(r'[+\d][\d\s\-()]{8,16}\d').allMatches(text)) {
      final n = nationalNumber(m.group(0)!);
      if (n != null && isPhone(n)) return n;
    }
    return null;
  }

  /// Whole years between [birth] and [on].
  static int ageOn(DateTime birth, DateTime on) {
    var years = on.year - birth.year;
    if (on.month < birth.month ||
        (on.month == birth.month && on.day < birth.day)) {
      years--;
    }
    return years;
  }

  // Messages, so every form says the same thing.
  static const mobileMessage =
      'Enter a 10-digit mobile number starting with 6, 7, 8 or 9, with or without +91.';
  static const phoneMessage =
      'Enter a 10-digit phone number with its area code, e.g. 079 4000 2210 or 98250 12345.';
  static const emailMessage = 'Enter an email like name@company.in.';
  static const nameMessage =
      'Use letters, spaces, dots, apostrophes or hyphens (up to 50).';
  static const pinMessage = 'PIN codes have 6 digits and don’t start with 0.';
}

/// "ankit@meridiantex.in" → "an•••@meridiantex.in" (board S05).
String maskEmail(String email) {
  final at = email.indexOf('@');
  if (at <= 0) return email;
  final name = email.substring(0, at);
  final visible = name.length <= 2
      ? name.substring(0, 1)
      : name.substring(0, 2);
  return '$visible•••${email.substring(at)}';
}
