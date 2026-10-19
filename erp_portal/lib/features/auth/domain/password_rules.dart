/// One rule in the live checklist on the registration form (board S04).
class PasswordRule {
  const PasswordRule(this.label, this.isMet);

  final String label;
  final bool isMet;
}

/// Password rules from board S04. [name] and [email] are optional so the
/// reset and invitation forms can use the same rules.
List<PasswordRule> passwordRules(
  String password, {
  String name = '',
  String email = '',
}) {
  final lower = password.toLowerCase();
  final personal = [
    ...name.toLowerCase().split(RegExp(r'\s+')),
    email.toLowerCase().split('@').first,
  ].where((part) => part.length >= 3);

  return [
    PasswordRule('At least 10 characters', password.length >= 10),
    PasswordRule('Contains a number', password.contains(RegExp(r'\d'))),
    PasswordRule(
      'Upper and lower case letters',
      password.contains(RegExp('[A-Z]')) && password.contains(RegExp('[a-z]')),
    ),
    PasswordRule(
      'Not your name or email',
      password.isNotEmpty && !personal.any(lower.contains),
    ),
  ];
}

bool isStrongPassword(String password, {String name = '', String email = ''}) =>
    passwordRules(password, name: name, email: email).every((r) => r.isMet);
