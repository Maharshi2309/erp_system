import 'package:flutter/foundation.dart';

import '../../employees/domain/custom_field.dart';
import '../../employees/domain/employee.dart';
import '../../employees/domain/employee_import.dart';
import '../../holidays/domain/work_calendar.dart';
import '../../organization/domain/branch.dart';

/// Dashboard period (board S30 "Date range").
enum DashboardPeriod {
  last14('Last 14 days'),
  thisMonth('This month'),
  last30('Last 30 days');

  const DashboardPeriod(this.label);

  final String label;

  DateTime startFor(DateTime now) => switch (this) {
    last14 => DateTime(now.year, now.month, now.day - 13),
    thisMonth => DateTime(now.year, now.month),
    last30 => DateTime(now.year, now.month, now.day - 29),
  };

  /// "this month" / "in the last 14 days".
  String get phrase => switch (this) {
    last14 => 'in the last 14 days',
    thisMonth => 'this month',
    last30 => 'in the last 30 days',
  };
}

enum AttentionKind {
  missingPunch('Missing punch'),
  import('Import'),
  invite('Invite'),
  incomplete('Incomplete'),
  change('Change');

  const AttentionKind(this.label);

  final String label;
}

/// One "Needs attention" line (board S30).
@immutable
class AttentionItem {
  const AttentionItem({
    required this.kind,
    required this.title,
    required this.subtitle,
    this.importId,
    this.employeeId,
  });

  final AttentionKind kind;
  final String title;
  final String subtitle;
  final String? importId;
  final String? employeeId;
}

typedef UpcomingHoliday = ({String name, DateTime date, List<String> branches});

/// Every figure on the admin dashboard, derived from records — never
/// typed in (PRD §12, R-DASH-01).
@immutable
class DashboardMetrics {
  const DashboardMetrics({
    required this.total,
    required this.joined,
    required this.active,
    required this.headcount,
    required this.upcomingHolidays,
    required this.attention,
  });

  /// [branchId] null = every branch the viewer can see.
  factory DashboardMetrics.compute({
    required List<Employee> employees,
    required List<Branch> branches,
    required List<ImportRecord> imports,
    required List<CustomField> fields,
    required DashboardPeriod period,
    required DateTime now,
    WorkCalendar calendar = const WorkCalendar([]),
    String? branchId,
  }) {
    final inScope = [
      for (final e in employees)
        if (e.status != EmploymentStatus.terminated &&
            (branchId == null || e.branchId == branchId))
          e,
    ];
    final start = period.startFor(now);
    final today = DateTime(now.year, now.month, now.day);
    final shownBranches = [
      for (final b in branches)
        if (b.isActive && (branchId == null || b.id == branchId)) b,
    ];

    // Upcoming observed holidays in the next 30 days, merged across branches.
    final holidays = <String, UpcomingHoliday>{};
    for (final b in shownBranches) {
      for (final h in calendar.holidaysBetween(
        b,
        today,
        today.add(const Duration(days: 30)),
      )) {
        final d = DateTime(h.date.year, h.date.month, h.date.day);
        final key = '${h.name}|${d.toIso8601String()}';
        final existing = holidays[key];
        holidays[key] = (
          name: h.name,
          date: d,
          branches: [...?existing?.branches, b.name],
        );
      }
    }
    final upcoming = holidays.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final attention = <AttentionItem>[];
    for (final r in imports) {
      if (r.failed > 0 && now.difference(r.finishedAt).inDays <= 30) {
        attention.add(
          AttentionItem(
            kind: AttentionKind.import,
            title:
                'Employee import failed for ${r.failed} ${r.failed == 1 ? 'row' : 'rows'}',
            subtitle:
                '${r.fileName} · ${r.finishedAt.day} ${_month(r.finishedAt.month)}',
            importId: r.id,
          ),
        );
      }
    }
    final expired = inScope
        .where((e) => e.accountStatus == AccountStatus.inviteExpired)
        .toList();
    if (expired.isNotEmpty) {
      attention.add(
        AttentionItem(
          kind: AttentionKind.invite,
          title:
              '${expired.length} ${expired.length == 1 ? 'invitation has' : 'invitations have'} expired',
          subtitle: expired.take(3).map((e) => e.fullName).join(', '),
          employeeId: expired.length == 1 ? expired.single.id : null,
        ),
      );
    }
    final required = fields.where((f) => f.required && !f.archived);
    final incomplete = {
      for (final f in required)
        for (final e in inScope)
          if (e.status.isEmployed &&
              f.appliesToEmployee(e) &&
              isBlankValue(e.customValues[f.key]))
            e.id,
    };
    if (incomplete.isNotEmpty) {
      attention.add(
        AttentionItem(
          kind: AttentionKind.incomplete,
          title:
              '${incomplete.length} ${incomplete.length == 1 ? 'person is' : 'people are'} missing required fields',
          subtitle: required.map((f) => f.label).join(', '),
        ),
      );
    }
    for (final e in inScope) {
      for (final a in e.activity) {
        if (a.kind == ActivityKind.moved &&
            now.difference(a.at).inDays <= 7 &&
            !a.at.isAfter(now)) {
          attention.add(
            AttentionItem(
              kind: AttentionKind.change,
              title:
                  '${e.fullName} ${a.text[0].toLowerCase()}${a.text.substring(1).split(' · ').first}',
              subtitle:
                  'by ${a.by}${a.text.contains(' · ') ? ' · ${a.text.split(' · ').last}' : ''}',
              employeeId: e.id,
            ),
          );
        }
      }
    }

    return DashboardMetrics(
      total: inScope.length,
      joined: inScope
          .where(
            (e) =>
                !e.joiningDate.isBefore(start) && !e.joiningDate.isAfter(now),
          )
          .length,
      active: inScope
          .where(
            (e) =>
                e.status.isEmployed &&
                e.accountStatus != AccountStatus.invited &&
                e.accountStatus != AccountStatus.inviteExpired,
          )
          .length,
      headcount: [
        for (final b in shownBranches)
          (branch: b, count: inScope.where((e) => e.branchId == b.id).length),
      ]..sort((a, b) => b.count.compareTo(a.count)),
      upcomingHolidays: upcoming,
      attention: attention,
    );
  }

  final int total;

  /// Joined during the selected period.
  final int joined;

  /// Employed and signed up (not inactive, not waiting on an invitation).
  final int active;
  final List<({Branch branch, int count})> headcount;
  final List<UpcomingHoliday> upcomingHolidays;
  final List<AttentionItem> attention;

  int get inactiveOrInvited => total - active;
}

String _month(int m) => const [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
][m - 1];

/// One row of the branch manager's "Today by department" table (board S33).
typedef DepartmentToday = ({String department, int people, int scheduled});

/// People per department and how many are scheduled today: employed, the
/// branch is open today, and today isn't their weekly off.
List<DepartmentToday> departmentsToday(
  List<Employee> employees,
  Branch branch,
  DateTime now,
) {
  final weekday = now.weekday - 1;
  final rows = <String, (int, int)>{};
  for (final e in employees) {
    if (e.branchId != branch.id || !e.status.isEmployed) continue;
    final off = e.weeklyOff != null
        ? e.weeklyOff == weekday
        : !branch.hours[weekday].open;
    final (people, scheduled) = rows[e.department] ?? (0, 0);
    rows[e.department] = (people + 1, scheduled + (off ? 0 : 1));
  }
  final list = [
    for (final MapEntry(key: d, value: (p, s)) in rows.entries)
      (department: d, people: p, scheduled: s),
  ]..sort((a, b) => b.people.compareTo(a.people));
  return list;
}

/// "Good morning" / "Good afternoon" / "Good evening".
String greetingFor(DateTime now) => now.hour < 12
    ? 'Good morning'
    : (now.hour < 17 ? 'Good afternoon' : 'Good evening');
