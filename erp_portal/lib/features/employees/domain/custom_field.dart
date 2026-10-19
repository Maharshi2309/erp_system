import 'package:flutter/foundation.dart';

import '../../../core/permissions/system_roles.dart';
import '../../../core/utils/validators.dart';
import 'employee.dart';

enum CustomFieldType {
  shortText('Short text'),
  longText('Long text'),
  number('Number'),
  date('Date'),
  singleSelect('Single-select'),
  multiSelect('Multi-select'),
  yesNo('Yes / no'),
  url('URL');

  const CustomFieldType(this.label);

  final String label;

  bool get hasOptions => this == singleSelect || this == multiSelect;
}

/// Roles in the "Who can see and edit" matrix (board S45). The owner can
/// always see and edit every field.
enum FieldAudience {
  hrAdmin('HR Admin'),
  branchManager('Branch Manager'),
  attendanceManager('Attendance Manager'),
  self('Employee (self)');

  const FieldAudience(this.label);

  final String label;
}

@immutable
class FieldAccess {
  const FieldAccess({this.view = false, this.edit = false});

  final bool view;

  /// Editing implies viewing.
  final bool edit;
}

/// An organization-defined employee field (PRD §6.2, board S45).
@immutable
class CustomField {
  const CustomField({
    required this.id,
    required this.key,
    required this.label,
    required this.type,
    this.description = '',
    this.options = const [],
    this.required = false,
    this.sensitive = false,
    this.archived = false,
    this.departments = const [],
    this.branchIds = const [],
    this.access = defaultAccess,
    this.createdAt,
  });

  static const defaultAccess = {
    FieldAudience.hrAdmin: FieldAccess(view: true, edit: true),
    FieldAudience.branchManager: FieldAccess(view: true, edit: true),
    FieldAudience.attendanceManager: FieldAccess(),
    FieldAudience.self: FieldAccess(view: true),
  };

  final String id;

  /// Used in imports and exports. Never changes after creation.
  final String key;
  final String label;
  final CustomFieldType type;
  final String description;
  final List<String> options;
  final bool required;

  /// Hidden from exports unless the exporter may see sensitive data.
  final bool sensitive;
  final bool archived;

  /// Empty = every department / every branch.
  final List<String> departments;
  final List<String> branchIds;
  final Map<FieldAudience, FieldAccess> access;
  final DateTime? createdAt;

  bool appliesTo({required String department, required String branchId}) =>
      !archived &&
      (departments.isEmpty || departments.contains(department)) &&
      (branchIds.isEmpty || branchIds.contains(branchId));

  bool appliesToEmployee(Employee e) =>
      appliesTo(department: e.department, branchId: e.branchId);

  /// [self] = the viewer is looking at their own record.
  bool canView(SystemRole role, {bool self = false}) {
    if (role == SystemRole.owner && !self) return true;
    final audience = _audience(role, self: self);
    return audience != null && (access[audience]?.view ?? false);
  }

  bool canEdit(SystemRole role, {bool self = false}) {
    if (role == SystemRole.owner && !self) return true;
    final audience = _audience(role, self: self);
    return audience != null && (access[audience]?.edit ?? false);
  }

  static FieldAudience? _audience(SystemRole role, {required bool self}) =>
      switch (role) {
        _ when self => FieldAudience.self,
        SystemRole.hrAdmin => FieldAudience.hrAdmin,
        SystemRole.branchManager => FieldAudience.branchManager,
        SystemRole.attendanceManager => FieldAudience.attendanceManager,
        _ => null,
      };

  CustomField copyWith({
    String? label,
    CustomFieldType? type,
    String? description,
    List<String>? options,
    bool? required,
    bool? sensitive,
    bool? archived,
    List<String>? departments,
    List<String>? branchIds,
    Map<FieldAudience, FieldAccess>? access,
  }) => CustomField(
    id: id,
    key: key,
    label: label ?? this.label,
    type: type ?? this.type,
    description: description ?? this.description,
    options: options ?? this.options,
    required: required ?? this.required,
    sensitive: sensitive ?? this.sensitive,
    archived: archived ?? this.archived,
    departments: departments ?? this.departments,
    branchIds: branchIds ?? this.branchIds,
    access: access ?? this.access,
    createdAt: createdAt,
  );
}

/// "Uniform size" → "uniform_size".
String fieldKeyFor(String label) => label
    .trim()
    .toLowerCase()
    .replaceAll(RegExp('[^a-z0-9]+'), '_')
    .replaceAll(RegExp(r'^_+|_+$'), '');

/// Types a field may switch to once employees have values for it
/// (board S45: "Locked because values exist").
Set<CustomFieldType> allowedTypeChanges(
  CustomFieldType type, {
  required bool hasValues,
}) {
  if (!hasValues) return CustomFieldType.values.toSet();
  return switch (type) {
    CustomFieldType.singleSelect => {type, CustomFieldType.multiSelect},
    CustomFieldType.shortText => {type, CustomFieldType.longText},
    _ => {type},
  };
}

bool isBlankValue(Object? value) => switch (value) {
  null => true,
  final String s => s.trim().isEmpty,
  final List<Object?> l => l.isEmpty,
  _ => false,
};

/// Checks one value; null when it is acceptable. Used by the employee form,
/// edit and import alike (PRD §18).
String? validateCustomValue(CustomField field, Object? value) {
  if (isBlankValue(value)) {
    return field.required ? '${field.label} is required.' : null;
  }
  switch (field.type) {
    case CustomFieldType.number:
      if (value is! num && num.tryParse('$value') == null) {
        return '${field.label} must be a number.';
      }
    case CustomFieldType.date:
      if (value is! DateTime) return '${field.label} must be a date.';
    case CustomFieldType.singleSelect:
      if (!field.options.contains(value)) {
        return '“$value” isn’t an option for ${field.label}.';
      }
    case CustomFieldType.multiSelect:
      final values = value is List ? value.cast<Object?>() : [value];
      final unknown = values.where((v) => !field.options.contains(v));
      if (unknown.isNotEmpty) {
        return '“${unknown.first}” isn’t an option for ${field.label}.';
      }
    case CustomFieldType.yesNo:
      if (value is! bool) return '${field.label} must be yes or no.';
    case CustomFieldType.url:
      final uri = Uri.tryParse('$value');
      if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
        return '${field.label} must be a web address starting with https://.';
      }
    case CustomFieldType.shortText:
      if ('$value'.length > 120) {
        return '${field.label} can be at most 120 characters.';
      }
    case CustomFieldType.longText:
      break;
  }
  return null;
}

/// How many [employees] use [option] of [field].
int optionUsage(
  CustomField field,
  String option,
  Iterable<Employee> employees,
) => employees.where((e) {
  final v = e.customValues[field.key];
  return v == option || (v is List && v.contains(option));
}).length;

/// Employees the field applies to that have no value — flagged incomplete
/// when the field becomes required (board S45).
int missingValues(CustomField field, Iterable<Employee> employees) => employees
    .where(
      (e) =>
          e.status.isEmployed &&
          field.appliesToEmployee(e) &&
          isBlankValue(e.customValues[field.key]),
    )
    .length;

/// Validates the field definition itself (board S45 editor).
Map<String, String> validateFieldDefinition(
  CustomField field, {
  required Iterable<CustomField> others,
}) {
  final errors = <String, String>{};
  if (field.label.trim().isEmpty) errors['label'] = 'Enter a label.';
  if (others.any(
    (o) =>
        o.id != field.id &&
        (o.key == field.key ||
            o.label.trim().toLowerCase() == field.label.trim().toLowerCase()),
  )) {
    errors['label'] = 'Another field already uses this name.';
  }
  if (field.type.hasOptions) {
    final cleaned = field.options.map((o) => o.trim()).toList();
    if (cleaned.where((o) => o.isNotEmpty).isEmpty) {
      errors['options'] = 'Add at least one option.';
    } else if (cleaned.any((o) => o.isEmpty)) {
      errors['options'] = 'Options can’t be empty.';
    } else if (cleaned.toSet().length != cleaned.length) {
      errors['options'] = 'Each option must be different.';
    }
  }
  return errors;
}

/// Shared check: is [text] a usable work email?
bool isWorkEmail(String text) => Validators.isEmail(text);
