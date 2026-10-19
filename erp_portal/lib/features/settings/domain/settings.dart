import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../core/permissions/system_roles.dart';

/// Who must use two-step sign-in (board S83).
enum TwoStepPolicy {
  optional('Optional', 'People can turn it on themselves.'),
  admins(
    'Required for anyone with admin access',
    'Owner, HR Admin, Branch and Attendance Managers. Recommended.',
  ),
  everyone(
    'Required for everyone',
    'Every employee, including kiosk-only staff.',
  );

  const TwoStepPolicy(this.label, this.hint);

  final String label;
  final String hint;

  bool requires(SystemRole role) => switch (this) {
    optional => false,
    admins => role.requiresTwoStep,
    everyone => true,
  };
}

/// Board S83.
@immutable
class SecuritySettings {
  const SecuritySettings({
    this.twoStep = TwoStepPolicy.optional,
    this.minPasswordLength = 10,
    this.lockAfterAttempts = 5,
    this.lockMinutes = 15,
    this.adminIdleMinutes = 30,
    this.employeeIdleDays = 30,
    this.inviteDays = 7,
    this.resetMinutes = 30,
  });

  final TwoStepPolicy twoStep;
  final int minPasswordLength;
  final int lockAfterAttempts;
  final int lockMinutes;
  final int adminIdleMinutes;
  final int employeeIdleDays;

  /// Invitation links expire after this many days (board S71).
  final int inviteDays;
  final int resetMinutes;

  SecuritySettings copyWith({
    TwoStepPolicy? twoStep,
    int? minPasswordLength,
    int? lockAfterAttempts,
    int? lockMinutes,
    int? adminIdleMinutes,
    int? employeeIdleDays,
    int? inviteDays,
    int? resetMinutes,
  }) => SecuritySettings(
    twoStep: twoStep ?? this.twoStep,
    minPasswordLength: minPasswordLength ?? this.minPasswordLength,
    lockAfterAttempts: lockAfterAttempts ?? this.lockAfterAttempts,
    lockMinutes: lockMinutes ?? this.lockMinutes,
    adminIdleMinutes: adminIdleMinutes ?? this.adminIdleMinutes,
    employeeIdleDays: employeeIdleDays ?? this.employeeIdleDays,
    inviteDays: inviteDays ?? this.inviteDays,
    resetMinutes: resetMinutes ?? this.resetMinutes,
  );
}

/// What an export can contain (board S84 columns).
enum ExportArea {
  people('People'),
  attendance('Attendance'),
  leave('Leave'),
  restricted('Restricted fields');

  const ExportArea(this.label);

  final String label;
}

enum FileDateFormat {
  dmy('DD/MM/YYYY', 'dd/MM/yyyy'),
  iso('YYYY-MM-DD (ISO)', 'yyyy-MM-dd');

  const FileDateFormat(this.label, this.pattern);

  final String label;
  final String pattern;
}

enum DurationStyle {
  hoursMinutes('Hours and minutes (8:04)'),
  decimal('Decimal hours (8.07)');

  const DurationStyle(this.label);

  final String label;

  String format(int minutes) => switch (this) {
    hoursMinutes =>
      '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}',
    decimal => (minutes / 60).toStringAsFixed(2),
  };
}

/// Board S84. The owner can always export everything.
@immutable
class DataSettings {
  const DataSettings({
    this.exportRights = defaultExportRights,
    this.dateFormat = FileDateFormat.dmy,
    this.durations = DurationStyle.hoursMinutes,
    this.csvSeparator = ',',
    this.linkDays = 7,
    this.punchYears = 7,
    this.leaverYears = 3,
    this.exportFileDays = 30,
  });

  static const defaultExportRights = <SystemRole, Set<ExportArea>>{
    SystemRole.hrAdmin: {
      ExportArea.people,
      ExportArea.attendance,
      ExportArea.leave,
      ExportArea.restricted,
    },
    SystemRole.branchManager: {
      ExportArea.people,
      ExportArea.attendance,
      ExportArea.leave,
    },
    SystemRole.attendanceManager: {ExportArea.attendance},
  };

  final Map<SystemRole, Set<ExportArea>> exportRights;
  final FileDateFormat dateFormat;
  final DurationStyle durations;
  final String csvSeparator;
  final int linkDays;
  final int punchYears;
  final int leaverYears;
  final int exportFileDays;

  /// Audit entries are kept at least this long; it can't be shortened.
  static const auditYears = 7;

  bool canExport(SystemRole role, ExportArea area) =>
      role == SystemRole.owner || (exportRights[role]?.contains(area) ?? false);

  DataSettings copyWith({
    Map<SystemRole, Set<ExportArea>>? exportRights,
    FileDateFormat? dateFormat,
    DurationStyle? durations,
    String? csvSeparator,
    int? linkDays,
    int? punchYears,
    int? leaverYears,
    int? exportFileDays,
  }) => DataSettings(
    exportRights: exportRights ?? this.exportRights,
    dateFormat: dateFormat ?? this.dateFormat,
    durations: durations ?? this.durations,
    csvSeparator: csvSeparator ?? this.csvSeparator,
    linkDays: linkDays ?? this.linkDays,
    punchYears: punchYears ?? this.punchYears,
    leaverYears: leaverYears ?? this.leaverYears,
    exportFileDays: exportFileDays ?? this.exportFileDays,
  );
}

/// Board S85.
@immutable
class BrandingSettings {
  const BrandingSettings({
    this.color = 0xFF2B4ACB,
    this.language = 'English (India)',
    this.longDates = true,
    this.clock24 = true,
    this.indianNumbers = true,
    this.weekStartsMonday = true,
  });

  static const swatches = [
    (0xFF2B4ACB, 'Indigo (default)'),
    (0xFF0E1A2B, 'Navy'),
    (0xFF0B7A62, 'Teal'),
    (0xFF8A3A12, 'Rust'),
  ];

  static const languages = [
    'English (India)',
    'ગુજરાતી (Gujarati)',
    'हिन्दी (Hindi)',
  ];

  final int color;
  final String language;
  final bool longDates;
  final bool clock24;
  final bool indianNumbers;
  final bool weekStartsMonday;

  BrandingSettings copyWith({
    int? color,
    String? language,
    bool? longDates,
    bool? clock24,
    bool? indianNumbers,
    bool? weekStartsMonday,
  }) => BrandingSettings(
    color: color ?? this.color,
    language: language ?? this.language,
    longDates: longDates ?? this.longDates,
    clock24: clock24 ?? this.clock24,
    indianNumbers: indianNumbers ?? this.indianNumbers,
    weekStartsMonday: weekStartsMonday ?? this.weekStartsMonday,
  );
}

/// WCAG contrast ratio of white text on [argb] (board S85 warning).
double contrastWithWhite(int argb) {
  double channel(int v) {
    final c = v / 255;
    return c <= 0.03928
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  final l =
      0.2126 * channel((argb >> 16) & 0xFF) +
      0.7152 * channel((argb >> 8) & 0xFF) +
      0.0722 * channel(argb & 0xFF);
  return 1.05 / (l + 0.05);
}

/// Organization settings not owned by another feature.
@immutable
class OrgSettings {
  const OrgSettings({
    this.security = const SecuritySettings(),
    this.data = const DataSettings(),
    this.branding = const BrandingSettings(),
  });

  final SecuritySettings security;
  final DataSettings data;
  final BrandingSettings branding;

  OrgSettings copyWith({
    SecuritySettings? security,
    DataSettings? data,
    BrandingSettings? branding,
  }) => OrgSettings(
    security: security ?? this.security,
    data: data ?? this.data,
    branding: branding ?? this.branding,
  );
}

/// Field errors for security settings; empty when they can be saved.
Map<String, String> validateSecurity(SecuritySettings s) => {
  if (s.minPasswordLength < 8 || s.minPasswordLength > 64)
    'minLength': 'Use 8 to 64 characters.',
  if (s.inviteDays < 1 || s.inviteDays > 30) 'inviteDays': 'Use 1 to 30 days.',
};

abstract interface class SettingsRepository {
  Future<OrgSettings> load(String organizationId);
  Future<OrgSettings> save(String organizationId, OrgSettings settings);
}
