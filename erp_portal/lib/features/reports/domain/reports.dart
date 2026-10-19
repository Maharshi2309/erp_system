import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../../core/permissions/permissions.dart';
import '../../../shared/models/app_session.dart';
import '../../attendance/domain/attendance_book.dart';
import '../../audit/domain/audit.dart';
import '../../employees/domain/employee.dart';
import '../../holidays/domain/company_holiday.dart';
import '../../leave/domain/leave.dart';
import '../../leave/domain/leave_book.dart';
import '../../organization/domain/branch.dart';
import '../../settings/domain/settings.dart';

/// A column a report can include (board S73 "Columns").
typedef ReportColumn = ({
  String key,
  String label,
  bool always,

  /// Needs the "Restricted fields" export right (board S84).
  bool restricted,
});

ReportColumn _c(
  String key,
  String label, {
  bool always = false,
  bool restricted = false,
}) => (key: key, label: label, always: always, restricted: restricted);

/// The report catalogue (board S73).
enum ReportKind {
  roster(
    'People',
    'Employee roster',
    'Everyone with branch, department, manager and status.',
    PermissionModule.employees,
    ExportArea.people,
  ),
  changes(
    'People',
    'Employee changes',
    'Joiners, leavers, transfers and edits in a period.',
    PermissionModule.employees,
    ExportArea.people,
  ),
  daily(
    'Attendance',
    'Daily attendance',
    'Punches, worked time and exceptions for one day.',
    PermissionModule.attendance,
    ExportArea.attendance,
  ),
  monthly(
    'Attendance',
    'Monthly attendance summary',
    'Present, late, absent and leave days per employee.',
    PermissionModule.attendance,
    ExportArea.attendance,
  ),
  missing(
    'Attendance',
    'Missing-punch report',
    'Open sessions and who corrected them.',
    PermissionModule.attendance,
    ExportArea.attendance,
  ),
  balances(
    'Leave',
    'Leave balance',
    'Granted, used, pending and available by type.',
    PermissionModule.leave,
    ExportArea.leave,
  ),
  requests(
    'Leave',
    'Leave requests & decisions',
    'Every request with approver and outcome.',
    PermissionModule.leave,
    ExportArea.leave,
  ),
  holidays(
    'Calendar & compliance',
    'Holiday calendar',
    'Organization and branch holidays for a period.',
    PermissionModule.holidays,
    null,
  ),
  audit(
    'Calendar & compliance',
    'Audit log',
    'Who changed what, when and why.',
    PermissionModule.auditLog,
    null,
  );

  const ReportKind(
    this.group,
    this.label,
    this.description,
    this.module,
    this.area,
  );

  final String group;
  final String label;
  final String description;
  final PermissionModule module;

  /// The export right needed (board S84); null = only the module's export.
  final ExportArea? area;

  /// One-day reports use only "from".
  bool get singleDay => this == daily;

  List<ReportColumn> get columns => switch (this) {
    roster => [
      _c('id', 'Employee ID & name', always: true),
      _c('org', 'Branch & department'),
      _c('job', 'Designation & manager'),
      _c('status', 'Status & joining date'),
      _c('work', 'Work email'),
      _c('mobile', 'Mobile', restricted: true),
      _c('personal', 'Personal email', restricted: true),
    ],
    changes => [
      _c('when', 'Date', always: true),
      _c('who', 'Employee', always: true),
      _c('what', 'What changed'),
      _c('by', 'Changed by'),
    ],
    daily => [
      _c('id', 'Employee ID & name', always: true),
      _c('org', 'Branch & department'),
      _c('status', 'Status'),
      _c('times', 'First in / last out'),
      _c('worked', 'Worked time'),
      _c('late', 'Late minutes'),
    ],
    monthly => [
      _c('id', 'Employee ID & name', always: true),
      _c('org', 'Branch & department'),
      _c('days', 'Present / late / absent days'),
      _c('leave', 'Leave days'),
      _c('hours', 'Worked vs expected hours'),
      _c('missing', 'Missing-punch count'),
    ],
    missing => [
      _c('when', 'Date', always: true),
      _c('id', 'Employee ID & name', always: true),
      _c('org', 'Branch'),
      _c('what', 'What is missing'),
      _c('state', 'State'),
    ],
    balances => [
      _c('id', 'Employee ID & name', always: true),
      _c('org', 'Branch & department'),
      _c('available', 'Available by type'),
      _c('used', 'Used by type'),
      _c('pending', 'Pending days'),
    ],
    requests => [
      _c('request', 'Request & employee', always: true),
      _c('type', 'Type & dates'),
      _c('days', 'Days'),
      _c('status', 'Status & decision'),
    ],
    holidays => [
      _c('when', 'Dates', always: true),
      _c('name', 'Holiday', always: true),
      _c('scope', 'Applies to'),
      _c('category', 'Category'),
    ],
    audit => [
      _c('when', 'Time', always: true),
      _c('actor', 'Actor'),
      _c('action', 'Action & entity'),
      _c('summary', 'Summary'),
      _c('changes', 'Changes (masked)'),
    ],
  };
}

/// Why [session] can't run or export [kind]; null when allowed.
String? reportBlock(
  ReportKind kind,
  AppSession session,
  DataSettings data, {
  bool export = false,
}) {
  final p = session.permissions;
  if (!p.canView(kind.module) || !p.canView(PermissionModule.reports)) {
    return kind == ReportKind.audit
        ? 'Owner and HR Admin only'
        : 'Not part of your role';
  }
  if (!export) return null;
  if (!p.can(kind.module, PermissionAction.export) ||
      !p.can(PermissionModule.reports, PermissionAction.export)) {
    return 'Your role can view this report but not export it';
  }
  if (kind.area != null && !data.canExport(session.role, kind.area!)) {
    return 'Exports of ${kind.area!.label.toLowerCase()} are turned off for your role';
  }
  return null;
}

/// May [session] include [c] (restricted columns need the right)?
bool columnAllowed(ReportColumn c, AppSession session, DataSettings data) =>
    !c.restricted ||
    (session.scope == DataScope.organization &&
        data.canExport(session.role, ExportArea.restricted));

/// Filters for a run (board S73 "Configure").
@immutable
class ReportFilter {
  const ReportFilter({
    required this.kind,
    required this.from,
    required this.to,
    this.branchId,
    this.department,
    this.columns = const {},
  });

  final ReportKind kind;
  final DateTime from;
  final DateTime to;
  final String? branchId;
  final String? department;

  /// Optional columns chosen; "always" columns are added regardless.
  final Set<String> columns;

  /// "1–30 Sep 2026 · Surat".
  String describe(List<Branch> branches) {
    final f = DateFormat('d MMM y');
    final period = kind.singleDay || from == to
        ? f.format(from)
        : '${f.format(from)} – ${f.format(to)}';
    final branch = branchId == null
        ? 'All branches'
        : (branches.where((b) => b.id == branchId).firstOrNull?.name ??
              branchId!);
    return [period, branch, ?department].join(' · ');
  }

  Map<String, String> toQuery() => {
    'report': kind.name,
    'from': DateFormat('yyyy-MM-dd').format(from),
    'to': DateFormat('yyyy-MM-dd').format(to),
    'branch': ?branchId,
    'dept': ?department,
    if (columns.isNotEmpty) 'cols': columns.join(','),
  };

  ReportFilter copyWith({
    ReportKind? kind,
    DateTime? from,
    DateTime? to,
    Object? branchId = _keep,
    Object? department = _keep,
    Set<String>? columns,
  }) => ReportFilter(
    kind: kind ?? this.kind,
    from: from ?? this.from,
    to: to ?? this.to,
    branchId: identical(branchId, _keep) ? this.branchId : branchId as String?,
    department: identical(department, _keep)
        ? this.department
        : department as String?,
    columns: columns ?? this.columns,
  );
}

const _keep = Object();

/// A generated report: headers, rows, totals and caveats (board S74).
@immutable
class ReportTable {
  const ReportTable({
    required this.headers,
    required this.rows,
    this.totals = const [],
    this.note = '',
    this.numeric = const {},
  });

  final List<String> headers;
  final List<List<String>> rows;
  final List<(String, String)> totals;
  final String note;

  /// Column indexes that hold numbers (right-aligned, sortable).
  final Set<int> numeric;
}

/// Everything a report reads.
typedef ReportSources = ({
  List<Employee> people,
  List<Branch> branches,
  AttendanceBook? attendance,
  LeaveBook? leave,
  List<AuditEvent> audit,
  List<CompanyHoliday> holidays,
  DataSettings format,
});

/// Builds [f] from [s]. [s.people] must already be limited to what the
/// member may see; branch and department filters are applied here.
ReportTable buildReport(ReportFilter f, ReportSources s, AppSession session) {
  final allowed = {
    for (final c in f.kind.columns)
      if ((c.always || f.columns.contains(c.key)) &&
          columnAllowed(c, session, s.format))
        c.key,
  };
  bool has(String key) => allowed.contains(key);
  final date = DateFormat(s.format.dateFormat.pattern);
  String branchName(String? id) =>
      s.branches.where((b) => b.id == id).firstOrNull?.name ?? (id ?? '');
  final people = [
    for (final e in s.people)
      if ((f.branchId == null || e.branchId == f.branchId) &&
          (f.department == null || e.department == f.department))
        e,
  ]..sort((a, b) => a.fullName.compareTo(b.fullName));
  final ids = {for (final e in people) e.id};
  String hours(int m) => s.format.durations.format(m);

  switch (f.kind) {
    case ReportKind.roster:
      String? manager(Employee e) => e.managerId == null
          ? null
          : s.people.where((x) => x.id == e.managerId).firstOrNull?.fullName;
      return ReportTable(
        headers: [
          'Employee ID',
          'Name',
          if (has('org')) ...['Branch', 'Department'],
          if (has('job')) ...['Designation', 'Manager'],
          if (has('status')) ...['Status', 'Joined'],
          if (has('work')) 'Work email',
          if (has('mobile')) 'Mobile',
          if (has('personal')) 'Personal email',
        ],
        rows: [
          for (final e in people)
            [
              e.code,
              e.fullName,
              if (has('org')) ...[branchName(e.branchId), e.department],
              if (has('job')) ...[e.designation, manager(e) ?? '—'],
              if (has('status')) ...[
                e.status.label,
                date.format(e.joiningDate),
              ],
              if (has('work')) e.workEmail,
              if (has('mobile')) e.mobile,
              if (has('personal')) e.personalEmail,
            ],
        ],
        totals: [
          ('People', '${people.length}'),
          (
            'Active',
            '${people.where((e) => e.status == EmploymentStatus.active).length}',
          ),
        ],
      );
    case ReportKind.changes:
      final events = [
        for (final e in s.audit)
          if (e.area == 'employee' &&
              (e.entityId == null || ids.contains(e.entityId)) &&
              !e.at.isBefore(f.from) &&
              e.at.isBefore(f.to.add(const Duration(days: 1))))
            e,
      ];
      return ReportTable(
        headers: [
          'Date',
          'Employee',
          if (has('what')) 'What changed',
          if (has('by')) 'Changed by',
        ],
        rows: [
          for (final e in events)
            [
              date.format(e.at),
              e.entityLabel,
              if (has('what')) e.summary,
              if (has('by')) e.actorName,
            ],
        ],
        totals: [('Changes', '${events.length}')],
      );
    case ReportKind.daily:
      final book = s.attendance;
      final records = book == null
          ? const <DayRecord>[]
          : book.daysOn(f.from, people);
      final counts = AttendanceBook.count(records);
      final headers = [
        'Employee ID',
        'Name',
        if (has('org')) ...['Branch', 'Department'],
        if (has('status')) 'Status',
        if (has('times')) ...['First in', 'Last out'],
        if (has('worked')) 'Worked',
        if (has('late')) 'Late (min)',
      ];
      return ReportTable(
        headers: headers,
        rows: [
          for (final r in records)
            [
              r.employee.code,
              r.employee.fullName,
              if (has('org')) ...[
                branchName(r.employee.branchId),
                r.employee.department,
              ],
              if (has('status')) r.status.label,
              if (has('times')) ...[
                r.sessions.isEmpty || r.sessions.first.inPunch == null
                    ? '—'
                    : clockTime(r.sessions.first.inPunch!.at, r.zone),
                r.sessions.isEmpty || r.sessions.last.outPunch == null
                    ? '—'
                    : clockTime(r.sessions.last.outPunch!.at, r.zone),
              ],
              if (has('worked')) hours(r.workedMinutes),
              if (has('late')) '${r.lateMinutes}',
            ],
        ],
        numeric: {if (has('late')) headers.length - 1},
        totals: [
          ('Scheduled', '${counts.scheduled}'),
          ('Present', '${counts.present}'),
          ('Late', '${counts.late}'),
          ('Absent', '${counts.absent}'),
          ('On leave', '${counts.onLeave}'),
        ],
      );
    case ReportKind.monthly:
      final book = s.attendance;
      var missingDays = 0;
      var tp = 0, tl = 0, ta = 0, tv = 0, worked = 0, expected = 0;
      final rows = <List<String>>[];
      for (final e in people) {
        if (book == null) break;
        final days = book
            .range(e, f.from, f.to)
            .where((d) => d.status != DayStatus.upcoming)
            .toList();
        final c = AttendanceBook.count(days);
        final missing = days
            .where((d) => d.status == DayStatus.missingPunch)
            .length;
        missingDays += missing;
        tp += c.present;
        tl += c.late;
        ta += c.absent;
        tv += c.onLeave;
        worked += c.workedMinutes;
        expected += c.expectedMinutes;
        rows.add([
          e.code,
          e.fullName,
          if (has('org')) ...[branchName(e.branchId), e.department],
          if (has('days')) ...['${c.present}', '${c.late}', '${c.absent}'],
          if (has('leave')) '${c.onLeave}',
          if (has('hours')) ...[
            hours(c.workedMinutes),
            hours(c.expectedMinutes),
          ],
          if (has('missing')) '$missing',
          '${c.rate}%',
        ]);
      }
      final headers = [
        'Employee ID',
        'Name',
        if (has('org')) ...['Branch', 'Department'],
        if (has('days')) ...['Present', 'Late', 'Absent'],
        if (has('leave')) 'Leave',
        if (has('hours')) ...['Worked', 'Expected'],
        if (has('missing')) 'Missing punches',
        'Rate',
      ];
      final scheduled = tp + ta;
      return ReportTable(
        headers: headers,
        rows: rows,
        numeric: {
          for (var i = 0; i < headers.length; i++)
            if (const {
              'Present',
              'Late',
              'Absent',
              'Leave',
              'Missing punches',
            }.contains(headers[i]))
              i,
        },
        totals: [
          ('Present days', '$tp'),
          ('Late arrivals', '$tl'),
          ('Absent days', '$ta'),
          ('Leave days', '$tv'),
          (
            'Attendance rate',
            scheduled == 0
                ? '—'
                : '${(tp / scheduled * 100).toStringAsFixed(1)}%',
          ),
          if (expected > 0)
            (
              'Worked hours',
              '${worked ~/ 60}h · ${(worked / expected * 100).toStringAsFixed(1)}% of expected',
            ),
        ],
        note: missingDays == 0
            ? ''
            : 'Figures exclude $missingDays days still marked missing punch.',
      );
    case ReportKind.missing:
      final book = s.attendance;
      final open = book == null
          ? const <DayRecord>[]
          : book
                .missingPunches(people, days: 60)
                .where((r) => !r.date.isBefore(f.from) && !r.date.isAfter(f.to))
                .toList();
      return ReportTable(
        headers: [
          'Date',
          'Employee ID',
          'Name',
          if (has('org')) 'Branch',
          if (has('what')) 'Missing',
          if (has('state')) 'State',
        ],
        rows: [
          for (final r in open)
            [
              date.format(r.date),
              r.employee.code,
              r.employee.fullName,
              if (has('org')) branchName(r.employee.branchId),
              if (has('what')) r.missingWhat,
              if (has('state'))
                r.pendingCorrection != null
                    ? 'Correction waiting for approval'
                    : 'Open',
            ],
        ],
        totals: [('Open sessions', '${open.length}')],
      );
    case ReportKind.balances:
      final book = s.leave;
      final types = book == null
          ? const <LeaveType>[]
          : [
              for (final t in book.data.types)
                if (t.tracksBalance && t.active && !t.optionalHolidaysOnly) t,
            ];
      String n(double v) => formatDays(v);
      return ReportTable(
        headers: [
          'Employee ID',
          'Name',
          if (has('org')) ...['Branch', 'Department'],
          if (has('available'))
            for (final t in types) '${t.name} available',
          if (has('used'))
            for (final t in types) '${t.name} used',
          if (has('pending')) 'Pending days',
        ],
        rows: [
          if (book != null)
            for (final e in people)
              [
                e.code,
                e.fullName,
                if (has('org')) ...[branchName(e.branchId), e.department],
                if (has('available'))
                  for (final t in types)
                    n(book.balance(e, t.key, f.to.year).available),
                if (has('used'))
                  for (final t in types)
                    n(book.balance(e, t.key, f.to.year).used),
                if (has('pending'))
                  n(
                    types.fold(
                      0.0,
                      (v, t) => v + book.balance(e, t.key, f.to.year).pending,
                    ),
                  ),
              ],
        ],
        totals: [('People', '${people.length}')],
      );
    case ReportKind.requests:
      final book = s.leave;
      final list = book == null
          ? const <LeaveRequest>[]
          : [
              for (final r in book.data.requests)
                if (ids.contains(r.employeeId) &&
                    !r.to.isBefore(f.from) &&
                    !r.from.isAfter(f.to))
                  r,
            ];
      return ReportTable(
        headers: [
          'Request',
          'Employee',
          if (has('type')) ...['Type', 'From', 'To'],
          if (has('days')) 'Days',
          if (has('status')) ...['Status', 'Decided by', 'Note'],
        ],
        rows: [
          for (final r in list)
            [
              r.id,
              book!.person(r.employeeId)?.fullName ?? r.employeeId,
              if (has('type')) ...[
                book.data.type(r.typeKey)?.name ?? r.typeKey,
                date.format(r.from),
                date.format(r.to),
              ],
              if (has('days')) formatDays(book.daysOf(r)),
              if (has('status')) ...[
                r.status.label,
                r.steps.where((x) => x.isDone).lastOrNull?.decidedBy ?? '—',
                r.decisionNote,
              ],
            ],
        ],
        totals: [
          ('Requests', '${list.length}'),
          (
            'Approved',
            '${list.where((r) => r.status == LeaveStatus.approved).length}',
          ),
          (
            'Rejected',
            '${list.where((r) => r.status == LeaveStatus.rejected).length}',
          ),
        ],
      );
    case ReportKind.holidays:
      final list = [
        for (final h in s.holidays)
          if (!h.endDate.isBefore(f.from) &&
              !h.date.isAfter(f.to) &&
              (f.branchId == null || h.appliesTo(f.branchId)))
            h,
      ];
      return ReportTable(
        headers: [
          'From',
          'To',
          'Holiday',
          if (has('scope')) 'Applies to',
          if (has('category')) 'Category',
        ],
        rows: [
          for (final h in list)
            [
              date.format(h.date),
              date.format(h.endDate),
              h.name,
              if (has('scope'))
                h.optional
                    ? 'Optional'
                    : (h.orgWide
                          ? 'All branches'
                          : h.branchIds.map(branchName).join(', ')),
              if (has('category')) h.category.label,
            ],
        ],
        totals: [('Holidays', '${list.length}')],
      );
    case ReportKind.audit:
      final list = [
        for (final e in s.audit)
          if (!e.at.isBefore(f.from) &&
              e.at.isBefore(f.to.add(const Duration(days: 1))) &&
              (f.branchId == null || e.branchId == f.branchId))
            e,
      ];
      return ReportTable(
        headers: [
          'Time',
          'Event',
          if (has('actor')) 'Actor',
          if (has('action')) ...['Action', 'Entity'],
          if (has('summary')) 'Summary',
          if (has('changes')) 'Changes (masked)',
        ],
        rows: [
          for (final e in list)
            [
              DateFormat('${s.format.dateFormat.pattern} HH:mm').format(e.at),
              e.id,
              if (has('actor')) '${e.actorName} (${e.actorRole})',
              if (has('action')) ...[e.action, e.entityLabel],
              if (has('summary')) e.summary,
              if (has('changes'))
                e.changes
                    .map(
                      (c) =>
                          '${c.field}: ${shownValue(c.field, c.before)} → ${shownValue(c.field, c.after)}',
                    )
                    .join('; '),
            ],
        ],
        totals: [('Events', '${list.length}')],
      );
  }
}

/// A file the member generated (boards S73, S75).
@immutable
class ExportRecord {
  const ExportRecord({
    required this.id,
    required this.kind,
    required this.filters,
    required this.requestedBy,
    required this.requestedById,
    required this.at,
    required this.format,
    this.failed = false,
    this.bytes,
    this.branchId,
  });

  final String id;
  final ReportKind kind;
  final String filters;
  final String requestedBy;

  /// Session user id, for "Only me".
  final String requestedById;
  final DateTime at;

  /// "XLSX" or "CSV".
  final String format;
  final bool failed;
  final Uint8List? bytes;

  /// For branch-scoped viewers of the history.
  final String? branchId;

  int get size => bytes?.length ?? 0;

  bool expired(DateTime now, int linkDays) =>
      now.difference(at).inDays >= linkDays;
}

abstract interface class ReportRepository {
  Future<List<ExportRecord>> exports(String organizationId);
  Future<ExportRecord> add(String organizationId, ExportRecord record);
}
