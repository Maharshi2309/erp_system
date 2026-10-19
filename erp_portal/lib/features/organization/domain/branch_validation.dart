import '../../../core/utils/validators.dart';
import 'branch.dart';

/// Inline errors for the branch form, keyed by field (board S19 messages).
/// Per-day hour errors use the keys `hours.0` … `hours.6`; `hours` alone
/// means no day is open.
Map<String, String> validateBranchDetails({
  required String name,
  required String address,
  required String city,
  required String pin,
  required String email,
  required WeeklyHours hours,
  required Iterable<String> otherBranchNames,
  String? code,
  Iterable<String> otherBranchCodes = const [],
}) {
  final errors = <String, String>{};
  final trimmedName = name.trim();
  if (trimmedName.isEmpty) {
    errors['name'] = 'Enter a branch name.';
  } else if (otherBranchNames.any(
    (n) => n.trim().toLowerCase() == trimmedName.toLowerCase(),
  )) {
    errors['name'] = 'You already have a branch with this name.';
  }
  if (code != null) {
    final c = code.trim().toUpperCase();
    if (c.isEmpty) {
      errors['code'] = 'Enter a branch code.';
    } else if (otherBranchCodes.any((o) => o.toUpperCase() == c)) {
      errors['code'] =
          '$c is already used by another branch. Choose another code.';
    }
  }
  if (address.trim().isEmpty) errors['address'] = 'Enter the branch address.';
  if (city.trim().isEmpty) errors['city'] = 'Enter the city.';
  if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
    errors['pin'] = 'PIN codes have 6 digits.';
  }
  if (email.trim().isNotEmpty && !Validators.isEmail(email)) {
    errors['email'] = 'Check the email address.';
  }
  for (var i = 0; i < hours.length; i++) {
    if (!hours[i].isValid) {
      errors['hours.$i'] = 'Closing time must be after opening time.';
    }
  }
  if (!hours.any((d) => d.open)) {
    errors['hours'] = 'Open the branch on at least one day.';
  }
  return errors;
}
