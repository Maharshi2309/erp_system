/// Field validators shared by forms and (later) imports, so both apply the
/// same rules (PRD §7.2).
abstract final class Validators {
  static final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  static bool isEmail(String value) => _email.hasMatch(value.trim());
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
