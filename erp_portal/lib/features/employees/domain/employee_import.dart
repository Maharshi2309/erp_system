import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../../core/permissions/system_roles.dart';
import '../../organization/domain/branch.dart';
import 'custom_field.dart';
import 'employee.dart';
import 'employee_rules.dart';
import 'field_settings.dart';

/// File limits (PRD §6.4, board S46).
const maxImportBytes = 5 * 1024 * 1024;
const maxImportRows = 2000;

/// A file that can't be imported (board S46 rejected-file state).
class ImportFileProblem implements Exception {
  const ImportFileProblem(this.title, this.detail);

  final String title;
  final String detail;

  @override
  String toString() => '$title $detail';
}

/// A spreadsheet read into text cells. Row 1 holds the headers.
@immutable
class ImportTable {
  const ImportTable({
    required this.fileName,
    required this.headers,
    required this.rows,
    this.sheetName = '',
    this.sizeBytes = 0,
  });

  final String fileName;
  final String sheetName;
  final List<String> headers;

  /// Data rows, each padded to [headers] length. Spreadsheet row n + 2.
  final List<List<String>> rows;
  final int sizeBytes;

  /// Up to three distinct non-empty values for the mapping table.
  String samples(int column) => rows
      .map((r) => r[column].trim())
      .where((v) => v.isNotEmpty)
      .toSet()
      .take(3)
      .join(', ');
}

/// Standard fields a column can be imported into (board S47).
enum ImportField {
  code('Employee ID', required: true),
  firstName('First name', required: true),
  lastName('Last name', required: true),
  workEmail('Work email'),
  mobile('Mobile number'),
  designation('Designation'),
  department('Department'),
  branch('Branch', required: true),
  manager('Reporting manager (by name)'),
  joiningDate('Joining date', required: true),
  type('Employment type'),
  shift('Shift');

  const ImportField(this.label, {this.required = false});

  final String label;

  /// Always required (core fields); others follow the field settings.
  final bool required;

  /// The built-in field the column fills, when its rule can change.
  StandardField? get standard => switch (this) {
    workEmail => StandardField.workEmail,
    mobile => StandardField.mobile,
    designation => StandardField.designation,
    department => StandardField.department,
    _ => null,
  };

  bool isRequired(EmployeeFieldSettings s) =>
      required || (standard != null && s.requires(standard!));

  bool isShown(EmployeeFieldSettings s) =>
      standard == null || s.shows(standard!);
}

/// Required fields that an import file can't carry; asked on the profile.
const _notImportable = {
  'displayName': 'Display name',
  'personalEmail': 'Personal email',
  'dateOfBirth': 'Date of birth',
  'emergencyContact': 'Emergency contact',
  'workLocation': 'Work location',
};

/// What a column goes into: a standard field, a custom field, or nothing.
@immutable
class ImportTarget {
  const ImportTarget.field(ImportField this.field) : customKey = null;
  const ImportTarget.custom(String this.customKey) : field = null;
  const ImportTarget.ignore() : field = null, customKey = null;

  final ImportField? field;
  final String? customKey;

  bool get isIgnored => field == null && customKey == null;

  String get id => field != null
      ? 'field:${field!.name}'
      : (customKey != null ? 'custom:$customKey' : '');

  @override
  bool operator ==(Object other) => other is ImportTarget && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// "Joining date (DD/MM/YYYY)" → "joiningdate": hints in brackets are
/// ignored, so our own template's headers match (D-80).
String _normal(String s) => s
    .replaceAll(RegExp(r'\(.*?\)'), '')
    .toLowerCase()
    .replaceAll(RegExp('[^a-z0-9]'), '');

const _synonyms = <ImportField, List<String>>{
  ImportField.code: [
    'employeeid',
    'empid',
    'empcode',
    'employeecode',
    'code',
    'staffid',
    'id',
  ],
  ImportField.firstName: ['firstname', 'givenname', 'first'],
  ImportField.lastName: ['lastname', 'surname', 'familyname', 'last'],
  ImportField.workEmail: [
    'email',
    'workemail',
    'emailaddress',
    'officialemail',
    'mail',
  ],
  ImportField.mobile: [
    'mobile',
    'mobilenumber',
    'phone',
    'phonenumber',
    'contact',
  ],
  ImportField.designation: [
    'designation',
    'title',
    'jobtitle',
    'position',
    'role',
  ],
  ImportField.department: ['department', 'dept', 'division'],
  ImportField.branch: ['branch', 'location', 'site', 'office', 'unit'],
  ImportField.manager: [
    'reportsto',
    'manager',
    'reportingmanager',
    'supervisor',
  ],
  ImportField.joiningDate: [
    'joiningdate',
    'joiningdt',
    'dateofjoining',
    'doj',
    'startdate',
    'joined',
  ],
  ImportField.type: ['employmenttype', 'emptype', 'type', 'contracttype'],
  ImportField.shift: ['shift', 'shiftname'],
};

/// Matches columns to fields by name. Returns one target per header.
List<ImportTarget> autoMatchColumns(
  List<String> headers,
  Iterable<CustomField> fields, [
  EmployeeFieldSettings settings = const EmployeeFieldSettings(),
]) {
  final used = <ImportTarget>{};
  return [
    for (final header in headers)
      () {
        final n = _normal(header);
        ImportTarget? target;
        for (final entry in _synonyms.entries) {
          if (entry.value.contains(n)) {
            // Hidden fields aren't imported (D-73).
            target = entry.key.isShown(settings)
                ? ImportTarget.field(entry.key)
                : const ImportTarget.ignore();
            break;
          }
        }
        if (target == null) {
          for (final f in fields.where((f) => !f.archived)) {
            if (n == _normal(f.key) ||
                n == _normal(f.label) ||
                _normal(f.label).startsWith(n) && n.length >= 4) {
              target = ImportTarget.custom(f.key);
              break;
            }
          }
        }
        if (target == null || used.contains(target)) {
          return const ImportTarget.ignore();
        }
        used.add(target);
        return target;
      }(),
  ];
}

enum DateOrder {
  dayFirst('DD/MM/YYYY'),
  monthFirst('MM/DD/YYYY');

  const DateOrder(this.label);

  final String label;
}

final _slashDate = RegExp(r'^(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})$');
final _isoDate = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})');

/// "03/10/2026" could be 3 Oct or 10 Mar (PRD §6.4: ask, don't guess).
bool isAmbiguousDate(String text) {
  final m = _slashDate.firstMatch(text.trim());
  if (m == null) return false;
  final a = int.parse(m.group(1)!);
  final b = int.parse(m.group(2)!);
  return a <= 12 && b <= 12 && a != b;
}

/// Parses ISO (2026-10-03) or slash dates in [order]; null if invalid.
DateTime? parseImportDate(String text, DateOrder? order) {
  final t = text.trim();
  DateTime? build(int y, int m, int d) {
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    final date = DateTime(y, m, d);
    return date.month == m ? date : null;
  }

  if (_isoDate.firstMatch(t) case final m?) {
    return build(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    );
  }
  if (_slashDate.firstMatch(t) case final m?) {
    final a = int.parse(m.group(1)!);
    final b = int.parse(m.group(2)!);
    final y = int.parse(m.group(3)!);
    if (a > 12) return build(y, b, a);
    if (b > 12) return build(y, a, b);
    return order == DateOrder.monthFirst ? build(y, a, b) : build(y, b, a);
  }
  return null;
}

enum RowResult {
  ready('Ready'),
  warning('Warning'),
  duplicate('Duplicate'),
  invalid('Invalid');

  const RowResult(this.label);

  final String label;
}

/// One differing value between a file row and the existing employee.
typedef FieldChange = ({String field, String now, String incoming});

/// The validation outcome for one data row (board S48).
@immutable
class ImportRow {
  const ImportRow({
    required this.rowNumber,
    required this.result,
    required this.employee,
    this.messages = const [],
    this.existing,
    this.changes = const [],
  });

  /// Spreadsheet row number (headers are row 1).
  final int rowNumber;
  final RowResult result;

  /// What would be saved (for duplicates: the merged update).
  final Employee employee;
  final List<String> messages;

  /// The employee a duplicate matches.
  final Employee? existing;
  final List<FieldChange> changes;

  String get issue => messages.join(' ');
}

String _fmt(DateTime d) => DateFormat('d MMM y').format(d);

/// Context the row checker needs.
@immutable
class ImportContext {
  const ImportContext({
    required this.organizationId,
    required this.existing,
    required this.branches,
    required this.fields,
    required this.dateOrder,
    required this.sendInvites,
    this.settings = const EmployeeFieldSettings(),
  });

  final String organizationId;
  final List<Employee> existing;
  final List<Branch> branches;
  final List<CustomField> fields;
  final DateOrder? dateOrder;
  final bool sendInvites;
  final EmployeeFieldSettings settings;
}

/// Finds a branch by name or code, then by the longest name the text starts
/// with ("Surat Unit 2" → Surat). The bool is true for a fuzzy match.
(Branch, bool)? matchBranch(String text, List<Branch> branches) {
  final t = text.trim().toLowerCase();
  if (t.isEmpty) return null;
  for (final b in branches) {
    if (b.name.toLowerCase() == t || b.code.toLowerCase() == t) {
      return (b, false);
    }
  }
  final prefixed = branches
      .where((b) => t.startsWith(b.name.toLowerCase().split(' ').first))
      .toList();
  return prefixed.isEmpty ? null : (prefixed.first, true);
}

/// Finds a manager by employee ID, full name, or "J Parmar" / "Bhavna S"
/// style abbreviations. The bool is true when the match is a guess.
(Employee, bool)? matchManager(String text, List<Employee> people) {
  final t = text.trim().toLowerCase();
  if (t.isEmpty) return null;
  for (final p in people) {
    if (p.code.toLowerCase() == t || p.fullName.toLowerCase() == t) {
      return (p, false);
    }
  }
  final parts = t.split(RegExp(r'\s+'));
  if (parts.length == 2) {
    final guesses = people.where((p) {
      final f = p.firstName.toLowerCase();
      final l = p.lastName.toLowerCase();
      return (f.startsWith(parts[0]) && l.startsWith(parts[1])) ||
          (f == parts[0] && l.startsWith(parts[1]));
    }).toList();
    if (guesses.length == 1) return (guesses.single, true);
  }
  return null;
}

EmploymentType? _parseType(String text) {
  final t = _normal(text);
  if (t.isEmpty ||
      ['permanent', 'fulltime', 'probation', 'regular'].contains(t)) {
    return EmploymentType.fullTime;
  }
  if (t == 'parttime') return EmploymentType.partTime;
  if (['contract', 'contractual', 'temporary'].contains(t)) {
    return EmploymentType.contract;
  }
  if (['trainee', 'intern', 'apprentice'].contains(t)) {
    return EmploymentType.trainee;
  }
  return null;
}

Object? _parseCustom(CustomField f, String raw, DateOrder? order) {
  final t = raw.trim();
  if (t.isEmpty) return null;
  return switch (f.type) {
    CustomFieldType.number => num.tryParse(t) ?? t,
    CustomFieldType.date => parseImportDate(t, order) ?? t,
    CustomFieldType.yesNo => switch (t.toLowerCase()) {
      'yes' || 'y' || 'true' || '1' => true,
      'no' || 'n' || 'false' || '0' => false,
      _ => t,
    },
    CustomFieldType.multiSelect =>
      t
          .split(RegExp('[,;]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
    CustomFieldType.singleSelect =>
      f.options.where((o) => o.toLowerCase() == t.toLowerCase()).firstOrNull ??
          t,
    _ => t,
  };
}

/// Required standard fields that no column is mapped to.
List<ImportField> unmappedRequired(
  List<ImportTarget> mapping, [
  EmployeeFieldSettings settings = const EmployeeFieldSettings(),
]) => [
  for (final f in ImportField.values)
    if (f.isRequired(settings) && !mapping.contains(ImportTarget.field(f))) f,
];

/// Columns mapped to the joining date whose values could be read two ways.
bool needsDateOrder(ImportTable table, List<ImportTarget> mapping) {
  for (var c = 0; c < mapping.length; c++) {
    final target = mapping[c];
    final isDate =
        target.field == ImportField.joiningDate || target.customKey != null;
    if (!isDate) continue;
    if (table.rows.any((r) => isAmbiguousDate(r[c]))) return true;
  }
  return false;
}

/// Checks every row; nothing is saved (board S48).
List<ImportRow> classifyRows(
  ImportTable table,
  List<ImportTarget> mapping,
  ImportContext ctx,
) {
  final activeBranches = ctx.branches.where((b) => b.isActive).toList();
  final firstRowOfCode = <String, int>{};
  final firstRowOfEmail = <String, int>{};
  final results = <ImportRow>[];

  for (var i = 0; i < table.rows.length; i++) {
    final cells = table.rows[i];
    final rowNumber = i + 2;
    String value(ImportField f) {
      final c = mapping.indexOf(ImportTarget.field(f));
      return c < 0 ? '' : cells[c].trim();
    }

    if (cells.every((c) => c.trim().isEmpty)) continue;

    final invalid = <String>[];
    final warnings = <String>[];

    final branchText = value(ImportField.branch);
    final branchMatch = matchBranch(branchText, activeBranches);
    final branch = branchMatch?.$1;
    if (branch == null) {
      invalid.add(
        branchText.isEmpty
            ? 'Branch is missing.'
            : 'Branch “$branchText” not found.',
      );
    } else if (branchMatch!.$2) {
      warnings.add(
        'Branch “$branchText” not found. Will be assigned to ${branch.name}.',
      );
    }

    final dateText = value(ImportField.joiningDate);
    final joining = parseImportDate(dateText, ctx.dateOrder);
    if (joining == null) {
      invalid.add(
        dateText.isEmpty
            ? 'Joining date is missing.'
            : '“$dateText” is not a date we can read.',
      );
    } else if (isAmbiguousDate(dateText)) {
      warnings.add(
        'Ambiguous date read as ${_fmt(joining)} '
        '(${(ctx.dateOrder ?? DateOrder.dayFirst).label}).',
      );
    }

    final typeText = value(ImportField.type);
    final type = _parseType(typeText);
    if (type == null) {
      invalid.add('Employment type “$typeText” isn’t recognised.');
    }

    final managerText = value(ImportField.manager);
    final staff = [
      for (final e in ctx.existing)
        if (e.status.isEmployed && (branch == null || e.branchId == branch.id))
          e,
    ];
    Employee? manager;
    if (managerText.isNotEmpty) {
      final match = matchManager(managerText, staff);
      if (match != null) {
        manager = match.$1;
        if (match.$2) {
          warnings.add(
            'Reporting manager “$managerText” matched to ${manager.fullName}. Confirm.',
          );
        }
      }
    }
    if (manager == null && branch != null) {
      manager = staff
          .where((e) => e.role == SystemRole.branchManager)
          .firstOrNull;
      if (manager != null) {
        warnings.add(
          managerText.isEmpty
              ? 'No reporting manager. ${manager.fullName} (branch manager) will be used.'
              : 'Reporting manager “$managerText” not found. '
                    '${manager.fullName} (branch manager) will be used.',
        );
      }
    }

    final shiftText = value(ImportField.shift);
    final shift = branch == null
        ? 'General'
        : (shiftsFor(branch)
                  .where((s) => s.name.toLowerCase() == shiftText.toLowerCase())
                  .firstOrNull
                  ?.name ??
              'General');
    if (shiftText.isNotEmpty &&
        shift.toLowerCase() != shiftText.toLowerCase()) {
      warnings.add('Shift “$shiftText” not found. General will be used.');
    }

    final custom = <String, Object?>{};
    for (var c = 0; c < mapping.length; c++) {
      final key = mapping[c].customKey;
      if (key == null) continue;
      final field = ctx.fields.where((f) => f.key == key).firstOrNull;
      if (field != null) {
        custom[key] = _parseCustom(field, cells[c], ctx.dateOrder);
      }
    }

    final code = value(ImportField.code).toUpperCase();
    final email = value(ImportField.workEmail).toLowerCase();
    final firstName = value(ImportField.firstName);
    final lastName = value(ImportField.lastName);
    final draft = Employee(
      id: 'import-$rowNumber',
      organizationId: ctx.organizationId,
      code: code,
      firstName: firstName,
      lastName: lastName,
      workEmail: email,
      mobile: value(ImportField.mobile),
      designation: value(ImportField.designation),
      department:
          departments
              .where(
                (d) =>
                    d.toLowerCase() ==
                    value(ImportField.department).toLowerCase(),
              )
              .firstOrNull ??
          value(ImportField.department),
      type: type ?? EmploymentType.fullTime,
      joiningDate: joining ?? DateTime(1970),
      branchId: branch?.id ?? '',
      managerId: manager?.id,
      shift: shift,
      status: _normal(typeText) == 'probation'
          ? EmploymentStatus.probation
          : EmploymentStatus.active,
      probationMonths: _normal(typeText) == 'probation' ? 6 : 0,
      customValues: custom,
      accountStatus: ctx.sendInvites
          ? AccountStatus.invited
          : AccountStatus.noAccount,
    );

    // Duplicate employee ID in the system.
    final existing = ctx.existing
        .where((e) => code.isNotEmpty && e.code.toUpperCase() == code)
        .firstOrNull;
    if (existing != null) {
      final changes = diffForImport(existing, draft, mapping, ctx.fields);
      final merged = mergeImport(existing, draft, mapping);
      results.add(
        ImportRow(
          rowNumber: rowNumber,
          result: RowResult.duplicate,
          employee: merged,
          existing: existing,
          changes: changes,
          messages: [
            changes.isEmpty
                ? 'Matches existing employee. Same values — no change would be made.'
                : '$code already belongs to ${existing.fullName}. '
                      'Will be rejected unless you allow updates.',
          ],
        ),
      );
      continue;
    }

    // Repeated within the file.
    if (code.isNotEmpty) {
      if (firstRowOfCode[code] case final first?) {
        invalid.add('$code is also used on row $first of this file.');
      } else {
        firstRowOfCode[code] = rowNumber;
      }
    }
    if (email.isNotEmpty) {
      if (firstRowOfEmail[email] case final first?) {
        invalid.add('$email is also used on row $first of this file.');
      } else {
        firstRowOfEmail[email] = rowNumber;
      }
    }

    if (ctx.sendInvites && email.isEmpty) {
      invalid.add(
        'Email is required for invited accounts. Add an email or turn off '
        '“Send sign-in invitations”.',
      );
    }
    final errors = validateEmployee(
      draft,
      others: ctx.existing,
      fields: ctx.fields,
      branch: branch,
      sendInvite: false,
      settings: ctx.settings,
    );
    for (final entry in errors.entries) {
      if (_notImportable[entry.key] case final label?) {
        warnings.add(
          '$label is required — add it on the profile after import.',
        );
        continue;
      }
      // Already reported above in import wording.
      if (entry.key == 'branchId' || entry.key == 'shift') continue;
      if (entry.key == 'managerId' && branch == null) continue;
      if (entry.key == 'managerId') {
        invalid.add(
          'No reporting manager found at ${branch!.name}. Add a Reports to column.',
        );
        continue;
      }
      invalid.add(entry.value);
    }

    results.add(
      ImportRow(
        rowNumber: rowNumber,
        result: invalid.isNotEmpty
            ? RowResult.invalid
            : (warnings.isNotEmpty ? RowResult.warning : RowResult.ready),
        employee: draft,
        messages: invalid.isNotEmpty ? invalid : warnings,
      ),
    );
  }
  return results;
}

String _display(Object? v) => switch (v) {
  null => '—',
  final DateTime d => _fmt(d),
  final List<Object?> l => l.join(', '),
  _ => '$v',
};

/// Fields the file would change on an existing employee. Only mapped,
/// non-empty columns count.
List<FieldChange> diffForImport(
  Employee existing,
  Employee incoming,
  List<ImportTarget> mapping,
  List<CustomField> fields,
) {
  final changes = <FieldChange>[];
  void check(ImportField f, String label, Object? now, Object? next) {
    if (!mapping.contains(ImportTarget.field(f))) return;
    if (next == null || (next is String && next.isEmpty)) return;
    if (_display(now).toLowerCase() != _display(next).toLowerCase()) {
      changes.add((field: label, now: _display(now), incoming: _display(next)));
    }
  }

  check(
    ImportField.firstName,
    'First name',
    existing.firstName,
    incoming.firstName,
  );
  check(
    ImportField.lastName,
    'Last name',
    existing.lastName,
    incoming.lastName,
  );
  check(ImportField.workEmail, 'Email', existing.workEmail, incoming.workEmail);
  check(ImportField.mobile, 'Mobile', existing.mobile, incoming.mobile);
  check(
    ImportField.designation,
    'Designation',
    existing.designation,
    incoming.designation,
  );
  check(
    ImportField.department,
    'Department',
    existing.department,
    incoming.department,
  );
  for (final key in mapping.map((t) => t.customKey).nonNulls) {
    final next = incoming.customValues[key];
    if (isBlankValue(next)) continue;
    final now = existing.customValues[key];
    if (_display(now) != _display(next)) {
      final label = fields.where((f) => f.key == key).firstOrNull?.label ?? key;
      changes.add((field: label, now: _display(now), incoming: _display(next)));
    }
  }
  return changes;
}

/// The existing employee with the file's non-empty mapped values applied.
/// Branch, manager and joining date are not changed by an import update.
Employee mergeImport(
  Employee existing,
  Employee incoming,
  List<ImportTarget> mapping,
) {
  String pick(ImportField f, String now, String next) =>
      mapping.contains(ImportTarget.field(f)) && next.isNotEmpty ? next : now;
  return existing.copyWith(
    firstName: pick(
      ImportField.firstName,
      existing.firstName,
      incoming.firstName,
    ),
    lastName: pick(ImportField.lastName, existing.lastName, incoming.lastName),
    workEmail: pick(
      ImportField.workEmail,
      existing.workEmail,
      incoming.workEmail,
    ),
    mobile: pick(ImportField.mobile, existing.mobile, incoming.mobile),
    designation: pick(
      ImportField.designation,
      existing.designation,
      incoming.designation,
    ),
    department: pick(
      ImportField.department,
      existing.department,
      incoming.department,
    ),
    customValues: {
      ...existing.customValues,
      for (final e in incoming.customValues.entries)
        if (!isBlankValue(e.value)) e.key: e.value,
    },
  );
}

/// What to do with rows that match existing employees (board S49).
enum DuplicatePolicy {
  reject('Reject duplicates'),
  update('Update existing employees'),
  skipSame('Skip only identical rows');

  const DuplicatePolicy(this.label);

  final String label;
}

enum DuplicateOutcome {
  skipped('Skipped'),
  noChange('No change'),
  willUpdate('Will update');

  const DuplicateOutcome(this.label);

  final String label;
}

DuplicateOutcome duplicateOutcome(ImportRow row, DuplicatePolicy policy) =>
    policy == DuplicatePolicy.update
    ? (row.changes.isEmpty
          ? DuplicateOutcome.noChange
          : DuplicateOutcome.willUpdate)
    : (policy == DuplicatePolicy.skipSame && row.changes.isEmpty
          ? DuplicateOutcome.noChange
          : DuplicateOutcome.skipped);

/// The confirm-step summary (board S50). Counts always add up to [total].
@immutable
class ImportPlan {
  const ImportPlan({
    required this.total,
    required this.ready,
    required this.warnings,
    required this.invalid,
    required this.duplicates,
    required this.toCreate,
    required this.toUpdate,
  });

  factory ImportPlan.from(List<ImportRow> rows, DuplicatePolicy policy) {
    int count(RowResult r) => rows.where((x) => x.result == r).length;
    final updates = rows
        .where(
          (r) =>
              r.result == RowResult.duplicate &&
              duplicateOutcome(r, policy) == DuplicateOutcome.willUpdate,
        )
        .toList();
    return ImportPlan(
      total: rows.length,
      ready: count(RowResult.ready),
      warnings: count(RowResult.warning),
      invalid: count(RowResult.invalid),
      duplicates: count(RowResult.duplicate),
      toCreate: [
        for (final r in rows)
          if (r.result == RowResult.ready || r.result == RowResult.warning) r,
      ],
      toUpdate: updates,
    );
  }

  final int total;
  final int ready;
  final int warnings;
  final int invalid;
  final int duplicates;
  final List<ImportRow> toCreate;
  final List<ImportRow> toUpdate;
}

enum RowOutcome {
  created('Created'),
  updated('Updated'),
  skipped('Skipped'),
  failed('Failed');

  const RowOutcome(this.label);

  final String label;
}

/// A row that was not imported, for the results table and error report.
@immutable
class NotImportedRow {
  const NotImportedRow({
    required this.rowNumber,
    required this.name,
    required this.code,
    required this.outcome,
    required this.reason,
    this.email = '',
  });

  final int rowNumber;
  final String name;
  final String code;
  final String email;
  final RowOutcome outcome;
  final String reason;
}

/// A finished import (boards S46 "Recent imports", S51).
@immutable
class ImportRecord {
  const ImportRecord({
    required this.id,
    required this.fileName,
    required this.finishedAt,
    required this.by,
    required this.created,
    required this.updated,
    required this.skipped,
    required this.failed,
    this.branchIds = const [],
    this.invitationsSent = 0,
    this.notImported = const [],
    this.createdEmployeeIds = const [],
  });

  final String id;
  final String fileName;
  final DateTime finishedAt;
  final String by;
  final int created;
  final int updated;
  final int skipped;
  final int failed;

  /// Branches the created employees joined.
  final List<String> branchIds;
  final int invitationsSent;
  final List<NotImportedRow> notImported;
  final List<String> createdEmployeeIds;

  /// "38 created · 4 failed".
  String get summary => [
    '$created created',
    if (updated > 0) '$updated updated',
    if (failed > 0) '$failed failed',
  ].join(' · ');
}

/// Rows in an error report: only rows with problems, and only the columns
/// needed to fix them (PRD §6.4, no unrelated data).
List<List<String>> errorReportRows(Iterable<ImportRow> rows) => [
  ['Row', 'Employee ID', 'Name', 'Email', 'Result', 'What to fix'],
  for (final r in rows)
    if (r.result != RowResult.ready)
      [
        '${r.rowNumber}',
        r.employee.code,
        r.employee.fullName,
        r.employee.workEmail,
        r.result.label,
        r.issue,
      ],
];

List<List<String>> resultReportRows(ImportRecord record) => [
  ['Row', 'Employee ID', 'Name', 'Email', 'Outcome', 'Reason'],
  for (final r in record.notImported)
    ['${r.rowNumber}', r.code, r.name, r.email, r.outcome.label, r.reason],
];
