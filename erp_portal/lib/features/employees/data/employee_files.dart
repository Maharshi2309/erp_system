import '../../organization/domain/branch.dart';
import '../domain/custom_field.dart';
import '../domain/employee.dart';
import '../domain/employee_import.dart';

String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String _value(Object? v) => switch (v) {
  null => '',
  final DateTime d => _date(d),
  final List<Object?> l => l.join(', '),
  final bool b => b ? 'Yes' : 'No',
  _ => '$v',
};

/// Import template: standard columns plus every active custom field, with
/// one example row (PRD §6.4, board S46 "Download template").
List<List<String>> templateRows(List<CustomField> fields) {
  final active = fields.where((f) => !f.archived).toList();
  return [
    [
      for (final f in ImportField.values)
        f == ImportField.joiningDate
            ? 'Joining date (DD/MM/YYYY)'
            : (f == ImportField.manager ? 'Reports to' : f.label),
      for (final f in active) f.label,
    ],
    [
      'EMP-0001',
      'Pooja',
      'Chauhan',
      'pooja.c@example.in',
      '+91 98250 61233',
      'Quality Inspector',
      'Quality',
      'Surat',
      'Bhavna Solanki',
      '19/10/2026',
      'Full-time',
      'General',
      for (final f in active)
        f.type.hasOptions && f.options.isNotEmpty ? f.options.first : '',
    ],
  ];
}

/// Directory export. Sensitive custom fields and personal details are left
/// out unless [includeSensitive] (PRD §6.1 privacy).
List<List<String>> exportRows(
  List<Employee> employees, {
  required List<Branch> branches,
  required List<Employee> everyone,
  required List<CustomField> fields,
  required bool includeSensitive,
}) {
  final exported = fields
      .where((f) => !f.archived && (includeSensitive || !f.sensitive))
      .toList();
  String branchName(String id) =>
      branches.where((b) => b.id == id).firstOrNull?.name ?? '';
  String managerName(String? id) =>
      everyone.where((e) => e.id == id).firstOrNull?.fullName ?? '';
  return [
    [
      'Employee ID',
      'First name',
      'Last name',
      'Work email',
      'Designation',
      'Department',
      'Branch',
      'Reports to',
      'Employment type',
      'Status',
      'Account',
      'Joining date',
      if (includeSensitive) ...['Mobile number', 'Personal email'],
      for (final f in exported) f.label,
    ],
    for (final e in employees)
      [
        e.code,
        e.firstName,
        e.lastName,
        e.workEmail,
        e.designation,
        e.department,
        branchName(e.branchId),
        managerName(e.managerId),
        e.type.label,
        e.status.label,
        e.accountStatus.label,
        _date(e.joiningDate),
        if (includeSensitive) ...[e.mobile, e.personalEmail],
        for (final f in exported) _value(e.customValues[f.key]),
      ],
  ];
}
