import 'package:flutter/foundation.dart';

import '../../../core/permissions/system_roles.dart';

/// Departments offered on forms and filters. Configurable departments
/// arrive with Settings (Phase 7).
const departments = [
  'Production',
  'Quality',
  'Logistics',
  'Stores',
  'Dispatch',
  'Finance',
  'People Ops',
  'Facilities',
  'Admin',
];

enum EmploymentType {
  fullTime('Full-time'),
  partTime('Part-time'),
  contract('Contract'),
  trainee('Trainee');

  const EmploymentType(this.label);

  final String label;
}

/// Employment lifecycle (PRD §6.3, board S39 "Employment").
enum EmploymentStatus {
  active('Active'),
  probation('Probation'),
  noticePeriod('Notice period'),
  inactive('Inactive'),
  terminated('Terminated');

  const EmploymentStatus(this.label);

  final String label;

  /// Still works here (can punch in, appears in headcount).
  bool get isEmployed =>
      this == active || this == probation || this == noticePeriod;
}

/// Sign-in account state (board S39 "Account").
enum AccountStatus {
  signedIn('Signed in'),
  invited('Invited'),
  inviteExpired('Invite expired'),
  noAccount('No account');

  const AccountStatus(this.label);

  final String label;
}

enum ActivityKind { created, updated, moved, status, account }

/// One line in an employee's activity history (board S42 "Activity").
@immutable
class EmployeeActivity {
  const EmployeeActivity({
    required this.text,
    required this.by,
    required this.at,
    this.kind = ActivityKind.updated,
  });

  final String text;
  final ActivityKind kind;

  /// Who did it, plus context, e.g. "Hetal Shah · import surat_staff.xlsx".
  final String by;
  final DateTime at;
}

/// Marker for "leave this nullable field as it is" in [Employee.copyWith].
const _keep = Object();

@immutable
class Employee {
  const Employee({
    required this.id,
    required this.organizationId,
    required this.code,
    required this.firstName,
    required this.lastName,
    required this.workEmail,
    required this.designation,
    required this.department,
    required this.type,
    required this.joiningDate,
    required this.branchId,
    required this.shift,
    this.displayName = '',
    this.mobile = '',
    this.personalEmail = '',
    this.dateOfBirth,
    this.emergencyContact = '',
    this.probationMonths = 0,
    this.status = EmploymentStatus.active,
    this.statusReason = '',
    this.lastWorkingDay,
    this.workLocation = '',
    this.managerId,
    this.weeklyOff,
    this.accountStatus = AccountStatus.noAccount,
    this.role = SystemRole.employee,
    this.invitedAt,
    this.lastSignInAt,
    this.customValues = const {},
    this.hasAttendance = false,
    this.activity = const [],
  });

  /// Internal record id.
  final String id;
  final String organizationId;

  /// Employee ID shown everywhere, e.g. "EMP-0229". Unique per organization.
  final String code;
  final String firstName;
  final String lastName;
  final String displayName;
  final String workEmail;
  final String mobile;

  /// Only HR admins and the owner can see it (board S43).
  final String personalEmail;
  final DateTime? dateOfBirth;
  final String emergencyContact;

  final String designation;
  final String department;
  final EmploymentType type;
  final DateTime joiningDate;

  /// 0 = no probation.
  final int probationMonths;
  final EmploymentStatus status;

  /// Why the status changed (deactivation or termination reason).
  final String statusReason;
  final DateTime? lastWorkingDay;

  final String branchId;
  final String workLocation;

  /// Another employee's [id]; leave requests route here first.
  final String? managerId;

  /// Name of a shift offered by the branch, e.g. "General".
  final String shift;

  /// 0 = Monday … 6 = Sunday; null = the branch's closed days.
  final int? weeklyOff;

  final AccountStatus accountStatus;
  final SystemRole role;
  final DateTime? invitedAt;
  final DateTime? lastSignInAt;

  /// Custom field key → value (`String`, `num`, `DateTime`, `bool` or `List<String>`).
  final Map<String, Object?> customValues;

  /// Attendance has been recorded; the employee ID can no longer change.
  final bool hasAttendance;

  /// Newest first.
  final List<EmployeeActivity> activity;

  String get fullName => '$firstName $lastName'.trim();

  /// The name to show in lists.
  String get name => displayName.trim().isEmpty ? fullName : displayName.trim();

  DateTime? get probationEndsOn => probationMonths == 0
      ? null
      : DateTime(
          joiningDate.year,
          joiningDate.month + probationMonths,
          joiningDate.day,
        );

  Employee copyWith({
    String? code,
    String? firstName,
    String? lastName,
    String? displayName,
    String? workEmail,
    String? mobile,
    String? personalEmail,
    Object? dateOfBirth = _keep,
    String? emergencyContact,
    String? designation,
    String? department,
    EmploymentType? type,
    DateTime? joiningDate,
    int? probationMonths,
    EmploymentStatus? status,
    String? statusReason,
    Object? lastWorkingDay = _keep,
    String? branchId,
    String? workLocation,
    Object? managerId = _keep,
    String? shift,
    Object? weeklyOff = _keep,
    AccountStatus? accountStatus,
    SystemRole? role,
    Object? invitedAt = _keep,
    Object? lastSignInAt = _keep,
    Map<String, Object?>? customValues,
    bool? hasAttendance,
    List<EmployeeActivity>? activity,
  }) => Employee(
    id: id,
    organizationId: organizationId,
    code: code ?? this.code,
    firstName: firstName ?? this.firstName,
    lastName: lastName ?? this.lastName,
    displayName: displayName ?? this.displayName,
    workEmail: workEmail ?? this.workEmail,
    mobile: mobile ?? this.mobile,
    personalEmail: personalEmail ?? this.personalEmail,
    dateOfBirth: identical(dateOfBirth, _keep)
        ? this.dateOfBirth
        : dateOfBirth as DateTime?,
    emergencyContact: emergencyContact ?? this.emergencyContact,
    designation: designation ?? this.designation,
    department: department ?? this.department,
    type: type ?? this.type,
    joiningDate: joiningDate ?? this.joiningDate,
    probationMonths: probationMonths ?? this.probationMonths,
    status: status ?? this.status,
    statusReason: statusReason ?? this.statusReason,
    lastWorkingDay: identical(lastWorkingDay, _keep)
        ? this.lastWorkingDay
        : lastWorkingDay as DateTime?,
    branchId: branchId ?? this.branchId,
    workLocation: workLocation ?? this.workLocation,
    managerId: identical(managerId, _keep)
        ? this.managerId
        : managerId as String?,
    shift: shift ?? this.shift,
    weeklyOff: identical(weeklyOff, _keep) ? this.weeklyOff : weeklyOff as int?,
    accountStatus: accountStatus ?? this.accountStatus,
    role: role ?? this.role,
    invitedAt: identical(invitedAt, _keep)
        ? this.invitedAt
        : invitedAt as DateTime?,
    lastSignInAt: identical(lastSignInAt, _keep)
        ? this.lastSignInAt
        : lastSignInAt as DateTime?,
    customValues: customValues ?? this.customValues,
    hasAttendance: hasAttendance ?? this.hasAttendance,
    activity: activity ?? this.activity,
  );
}

/// "+91 98•• ••4417": first two and last four digits stay visible.
String maskPhone(String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 6) return phone.isEmpty ? '' : '••••';
  final local = digits.length > 10
      ? digits.substring(digits.length - 10)
      : digits;
  final prefix = digits.length > 10
      ? '+${digits.substring(0, digits.length - 10)} '
      : '';
  return '$prefix${local.substring(0, 2)}•• ••${local.substring(local.length - 4)}';
}

/// "EMP-0244" after the highest numeric employee ID in [codes].
String nextEmployeeCode(Iterable<String> codes) {
  var highest = 0;
  for (final code in codes) {
    final match = RegExp(r'(\d+)$').firstMatch(code);
    if (match != null) {
      final n = int.parse(match.group(1)!);
      if (n > highest) highest = n;
    }
  }
  return 'EMP-${(highest + 1).toString().padLeft(4, '0')}';
}
