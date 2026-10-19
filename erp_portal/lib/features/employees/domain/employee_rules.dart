import '../../../core/permissions/system_roles.dart';
import '../../../core/utils/validators.dart';
import '../../organization/domain/branch.dart';
import 'custom_field.dart';
import 'employee.dart';

/// A shift a branch offers (board S43 "Shift").
typedef BranchShift = ({String name, int start, int end});

String _hhmm(int minutes) {
  final m = minutes % (24 * 60);
  return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

String shiftLabel(BranchShift s) =>
    '${s.name} (${_hhmm(s.start)}–${_hhmm(s.end)})';

/// "General" follows the branch's working hours; branches with several
/// shifts also offer the overnight "Night" shift.
List<BranchShift> shiftsFor(Branch branch) {
  final day = branch.hours.where((d) => d.open).firstOrNull;
  return [
    (
      name: 'General',
      start: day?.opensAt ?? hm(9, 30),
      end: day?.closesAt ?? hm(18, 30),
    ),
    if (branch.attendance?.shiftMode == ShiftMode.several)
      (name: 'Night', start: hm(21, 0), end: hm(6, 0)),
  ];
}

/// "General (09:30–18:30)" for the employee's shift at [branch].
String describeShift(Employee e, Branch? branch) {
  if (branch == null) return e.shift;
  final s = shiftsFor(branch).where((s) => s.name == e.shift).firstOrNull;
  return s == null ? e.shift : shiftLabel(s);
}

/// Validates an employee record. The add form, the edit form and the import
/// all use this, so the rules can't drift apart (PRD §6.3, §18).
///
/// [others] = every other employee in the organization. [sendInvite]: an
/// invitation needs a work email.
Map<String, String> validateEmployee(
  Employee e, {
  required Iterable<Employee> others,
  required Iterable<CustomField> fields,
  required Branch? branch,
  required bool sendInvite,
}) {
  final errors = <String, String>{};
  if (e.firstName.trim().isEmpty) errors['firstName'] = 'Enter a first name.';
  if (e.lastName.trim().isEmpty) errors['lastName'] = 'Enter a last name.';

  final code = e.code.trim().toUpperCase();
  if (code.isEmpty) {
    errors['code'] = 'Enter an employee ID.';
  } else if (!RegExp(r'^[A-Z0-9][A-Z0-9-]{1,19}$').hasMatch(code)) {
    errors['code'] = 'Use letters, numbers and dashes, e.g. EMP-0244.';
  } else if (others.where((o) => o.code.toUpperCase() == code).firstOrNull
      case final o?) {
    errors['code'] = '$code already belongs to ${o.fullName}.';
  }

  final email = e.workEmail.trim().toLowerCase();
  if (email.isEmpty) {
    if (sendInvite) {
      errors['workEmail'] = 'Enter a work email to send the invitation.';
    }
  } else if (!Validators.isEmail(email)) {
    errors['workEmail'] =
        '“${e.workEmail.trim()}” is not a valid email address.';
  } else if (others.where((o) => o.workEmail.toLowerCase() == email).firstOrNull
      case final o?) {
    errors['workEmail'] =
        'This email belongs to ${o.fullName} (${o.code}). '
        'Use a different address.';
  }
  if (e.personalEmail.trim().isNotEmpty &&
      !Validators.isEmail(e.personalEmail)) {
    errors['personalEmail'] = 'Check the email address.';
  }
  final digits = e.mobile.replaceAll(RegExp(r'\D'), '');
  if (digits.isNotEmpty && (digits.length < 10 || digits.length > 12)) {
    errors['mobile'] = 'Enter a 10-digit mobile number, with or without +91.';
  }

  if (e.designation.trim().isEmpty) {
    errors['designation'] = 'Enter a designation.';
  }
  if (!departments.contains(e.department)) {
    errors['department'] = 'Choose a department.';
  }

  if (branch == null) {
    errors['branchId'] = 'Choose a branch.';
  } else {
    if (!branch.isActive) {
      errors['branchId'] =
          '${branch.name} is inactive. Choose an active branch.';
    }
    final shifts = shiftsFor(branch);
    if (!shifts.any((s) => s.name == e.shift)) {
      final names = shifts.map(shiftLabel).join(' and ');
      errors['shift'] = 'Choose a shift. ${branch.name} has $names.';
    }
  }

  final manager = e.managerId == null
      ? null
      : others.where((o) => o.id == e.managerId).firstOrNull;
  if (e.managerId == null) {
    // Branch managers and HR admins may report straight to the owner.
    if (!reportsToOwnerAllowed(e)) {
      errors['managerId'] = 'Choose who this person reports to.';
    }
  } else if (manager == null || !manager.status.isEmployed) {
    errors['managerId'] = 'That manager is no longer employed. Choose another.';
  } else if (branch != null && manager.branchId != e.branchId) {
    errors['managerId'] =
        'Required — ${manager.fullName} is not at ${branch.name}.';
  }

  for (final field in fields) {
    if (!field.appliesToEmployee(e)) continue;
    final error = validateCustomValue(field, e.customValues[field.key]);
    if (error != null) errors['custom.${field.key}'] = error;
  }
  return errors;
}

bool reportsToOwnerAllowed(Employee e) =>
    e.role == SystemRole.branchManager || e.role == SystemRole.hrAdmin;

/// What a branch move also changes (board S44 "Moving branches changes these
/// too").
List<String> branchMoveConsequences({
  required Employee before,
  required Branch to,
  required int pendingLeaveRequests,
}) {
  final general = shiftsFor(to).first;
  return [
    'Schedule becomes ${shiftLabel(general)} (${to.name} default)',
    'Reporting manager must be someone at ${to.name}',
    if (pendingLeaveRequests > 0)
      '$pendingLeaveRequests pending leave '
          '${pendingLeaveRequests == 1 ? 'request moves' : 'requests move'} '
          'to the new manager',
    'Holidays switch to the ${to.name} calendar from the effective date',
  ];
}
