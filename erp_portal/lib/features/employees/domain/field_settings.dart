import 'package:flutter/foundation.dart';

/// How a built-in field is treated on the add and edit forms and in imports.
enum FieldRule {
  required('Required'),
  optional('Optional'),
  hidden('Hidden');

  const FieldRule(this.label);

  final String label;
}

const _all = [FieldRule.required, FieldRule.optional, FieldRule.hidden];
const _noHide = [FieldRule.required, FieldRule.optional];
const _noRequire = [FieldRule.optional, FieldRule.hidden];
const _locked = [FieldRule.required];

/// The built-in employee fields (D-73). Core fields are locked as required
/// because attendance, leave and approvals depend on them.
enum StandardField {
  code('Employee ID', 'Identity', _locked),
  firstName('First name', 'Identity', _locked),
  lastName('Last name', 'Identity', _locked),
  displayName('Display name', 'Identity', _all, FieldRule.optional),
  workEmail('Work email', 'Contact', _noHide, FieldRule.optional),
  mobile('Mobile number', 'Contact', _all, FieldRule.optional),
  personalEmail('Personal email', 'Contact', _all, FieldRule.optional),
  dateOfBirth('Date of birth', 'Contact', _all, FieldRule.optional),
  emergencyContact('Emergency contact', 'Contact', _all, FieldRule.optional),
  designation('Designation', 'Employment', _all),
  department('Department', 'Employment', _all),
  type('Employment type', 'Employment', _locked),
  joiningDate('Joining date', 'Employment', _locked),
  probation('Probation', 'Employment', _noRequire, FieldRule.optional),
  branch('Branch', 'Branch & location', _locked),
  workLocation('Work location', 'Branch & location', _all, FieldRule.optional),
  manager('Reporting manager', 'Reporting', _locked),
  shift('Shift', 'Schedule', _locked),
  weeklyOff('Weekly off', 'Schedule', _noRequire, FieldRule.optional);

  const StandardField(
    this.label,
    this.section,
    this.allowed, [
    this.defaultRule = FieldRule.required,
  ]);

  final String label;
  final String section;

  /// The rules an admin may pick; one entry means locked.
  final List<FieldRule> allowed;
  final FieldRule defaultRule;

  bool get locked => allowed.length == 1;

  /// Why a locked field can't change, or a note on a special rule.
  String? get note => switch (this) {
    code || firstName || lastName => 'Identifies the person',
    type || joiningDate => 'Used for leave eligibility and allowances',
    branch || shift => 'Attendance is calculated from it',
    manager => 'Leave and corrections are routed to them',
    workEmail => 'Always needed when an invitation is sent',
    personalEmail ||
    dateOfBirth ||
    emergencyContact => 'Asked only by people who can see restricted fields',
    _ => null,
  };
}

/// Which built-in fields the organization asks for (D-73).
@immutable
class EmployeeFieldSettings {
  const EmployeeFieldSettings({
    this.rules = const {},
    this.updatedAt,
    this.updatedBy = '',
  });

  /// Only the fields changed from their defaults.
  final Map<StandardField, FieldRule> rules;
  final DateTime? updatedAt;
  final String updatedBy;

  FieldRule ruleOf(StandardField f) {
    final r = rules[f];
    return r != null && f.allowed.contains(r) ? r : f.defaultRule;
  }

  bool requires(StandardField f) => ruleOf(f) == FieldRule.required;
  bool shows(StandardField f) => ruleOf(f) != FieldRule.hidden;

  EmployeeFieldSettings withRule(StandardField f, FieldRule rule) =>
      EmployeeFieldSettings(
        rules: {
          for (final e in rules.entries)
            if (e.key != f) e.key: e.value,
          if (rule != f.defaultRule) f: rule,
        },
        updatedAt: updatedAt,
        updatedBy: updatedBy,
      );

  /// Counts for the settings overview ("4 required · 2 hidden").
  int count(FieldRule rule) =>
      StandardField.values.where((f) => ruleOf(f) == rule).length;

  @override
  bool operator ==(Object other) =>
      other is EmployeeFieldSettings && mapEquals(other.rules, rules);

  @override
  int get hashCode => Object.hashAllUnordered(rules.entries);
}
