import '../../../core/permissions/permissions.dart';
import 'access.dart';

/// Plain-language access (D-79): each area gets one level, plus a few
/// named abilities. It is a view over the same permission grants, so the
/// stored data and the backend contract don't change.
enum AccessLevel {
  none('No access', 'They don’t see this area.'),
  view('Can view', 'They can look, but not change anything.'),
  edit('Can edit', 'They can look and make everyday changes.'),
  full(
    'Full control',
    'Everything in this area, including removing and downloading.',
  );

  const AccessLevel(this.label, this.hint);

  final String label;
  final String hint;
}

/// An area of the app as people think of it.
typedef AccessArea = ({
  String name,
  String about,
  Map<PermissionAction, String> abilities,
});

/// Every module in everyday words. Each ability is one sentence that says
/// what the person can do.
const accessAreas = <PermissionModule, AccessArea>{
  PermissionModule.organization: (
    name: 'Company & branches',
    about: 'Company profile and branch details',
    abilities: {
      PermissionAction.view: 'See the company profile and branches',
      PermissionAction.create: 'Add new branches',
      PermissionAction.edit: 'Change company and branch details',
      PermissionAction.deactivate: 'Close branches',
      PermissionAction.export: 'Download branch lists',
    },
  ),
  PermissionModule.employees: (
    name: 'People',
    about: 'Employee directory and profiles',
    abilities: {
      PermissionAction.view: 'See employees and their profiles',
      PermissionAction.create: 'Add employees and send invitations',
      PermissionAction.edit: 'Change employee details',
      PermissionAction.deactivate: 'Deactivate people or end employment',
      PermissionAction.export: 'Download employee lists',
    },
  ),
  PermissionModule.employeeFields: (
    name: 'Employee form',
    about: 'Which fields the employee form asks for',
    abilities: {
      PermissionAction.view: 'See which fields are required or hidden',
      PermissionAction.edit: 'Change required, optional and hidden fields',
    },
  ),
  PermissionModule.attendance: (
    name: 'Attendance',
    about: 'Punches, records and corrections',
    abilities: {
      PermissionAction.view: 'See punches and attendance records',
      PermissionAction.correct: 'Fix wrong or missing punches',
      PermissionAction.approve: 'Approve corrections and selfie reviews',
      PermissionAction.export: 'Download attendance',
    },
  ),
  PermissionModule.leave: (
    name: 'Leave',
    about: 'Requests, balances and leave rules',
    abilities: {
      PermissionAction.view: 'See leave requests and balances',
      PermissionAction.create: 'Apply for leave on someone’s behalf',
      PermissionAction.edit: 'Change leave types, rules and balances',
      PermissionAction.approve: 'Approve or reject leave',
      PermissionAction.export: 'Download leave reports',
    },
  ),
  PermissionModule.holidays: (
    name: 'Holidays & schedules',
    about: 'Holiday calendars and work schedules',
    abilities: {
      PermissionAction.view: 'See holiday calendars and schedules',
      PermissionAction.create: 'Add holidays and schedules',
      PermissionAction.edit: 'Change holidays and schedules',
      PermissionAction.deactivate: 'Delete holidays',
      PermissionAction.export: 'Download the holiday calendar',
    },
  ),
  PermissionModule.settings: (
    name: 'Company settings',
    about: 'Attendance rules, notifications, branding',
    abilities: {
      PermissionAction.view: 'See company settings',
      PermissionAction.edit:
          'Change attendance, notification and branding settings',
    },
  ),
  PermissionModule.roles: (
    name: 'Roles & access',
    about: 'Who can do what',
    abilities: {
      PermissionAction.view: 'See roles and who has them',
      PermissionAction.create: 'Create roles',
      PermissionAction.edit: 'Change roles and give people access',
      PermissionAction.deactivate: 'Switch roles off',
    },
  ),
  PermissionModule.reports: (
    name: 'Dashboards & reports',
    about: 'Overview dashboards and the report center',
    abilities: {
      PermissionAction.view: 'See dashboards and reports',
      PermissionAction.export: 'Download reports',
    },
  ),
  PermissionModule.importExport: (
    name: 'Bulk import',
    about: 'Adding people or holidays from a file',
    abilities: {
      PermissionAction.view: 'See past imports',
      PermissionAction.create: 'Import people and holidays from files',
      PermissionAction.export: 'Download import error reports',
    },
  ),
  PermissionModule.auditLog: (
    name: 'Activity history',
    about: 'Who changed what, and when',
    abilities: {
      PermissionAction.view: 'See who changed what',
      PermissionAction.export: 'Download the history',
    },
  ),
};

const _editActions = {
  PermissionAction.create,
  PermissionAction.edit,
  PermissionAction.correct,
};

/// Abilities shown as their own switches at "Can view" / "Can edit".
const extraActions = [PermissionAction.approve, PermissionAction.export];

/// Actions a role other than the owner can hold in [m].
Set<PermissionAction> assignable(PermissionModule m) => {
  for (final a in PermissionAction.values)
    if (isApplicable(m, a) && !isOwnerOnly(m, a)) a,
};

/// The levels that mean something for [m].
List<AccessLevel> levelsFor(PermissionModule m) {
  final all = assignable(m);
  final edits = all.intersection(_editActions);
  final full = {PermissionAction.view, ...edits};
  return [
    AccessLevel.none,
    if (all.contains(PermissionAction.view)) AccessLevel.view,
    if (edits.isNotEmpty) AccessLevel.edit,
    // "Full" only when it adds something beyond view/edit.
    if (all.difference(full).isNotEmpty) AccessLevel.full,
  ];
}

Set<PermissionAction> _held(PermissionSet grants, PermissionModule m) => {
  for (final a in assignable(m))
    if (grants.can(m, a)) a,
};

/// The level that best describes what [grants] allow in [m].
AccessLevel levelOf(PermissionSet grants, PermissionModule m) {
  final held = _held(grants, m);
  if (!held.contains(PermissionAction.view)) return AccessLevel.none;
  final levels = levelsFor(m);
  if (levels.contains(AccessLevel.full) && held.containsAll(assignable(m))) {
    return AccessLevel.full;
  }
  if (held.intersection(_editActions).isNotEmpty) return AccessLevel.edit;
  return AccessLevel.view;
}

/// The exact actions a level (plus the chosen extras) stands for.
Set<PermissionAction> actionsFor(
  PermissionModule m,
  AccessLevel level, {
  Set<PermissionAction> extras = const {},
}) {
  final all = assignable(m);
  return switch (level) {
    AccessLevel.none => {},
    AccessLevel.full => all,
    AccessLevel.view => {
      PermissionAction.view,
      ...extras.intersection(all).intersection(extraActions.toSet()),
    },
    AccessLevel.edit => {
      PermissionAction.view,
      ...all.intersection(_editActions),
      ...extras.intersection(all).intersection(extraActions.toSet()),
    },
  };
}

/// True when [grants] in [m] are exactly a level and its switches — false
/// for a hand-picked mix (shown as "Custom mix" with the details).
bool isPlainLevel(PermissionSet grants, PermissionModule m) {
  final held = _held(grants, m);
  final level = levelOf(grants, m);
  return held.length == actionsFor(m, level, extras: held).length &&
      held.containsAll(actionsFor(m, level, extras: held));
}

/// [grants] with [m] set to [level], keeping its switches where they apply.
PermissionSet withLevel(
  PermissionSet grants,
  PermissionModule m,
  AccessLevel level,
) {
  final keep = _held(grants, m).intersection(extraActions.toSet());
  return PermissionSet({
    for (final p in grants.grants)
      if (p.module != m) p,
    for (final a in actionsFor(m, level, extras: keep)) Permission(m, a),
  });
}

/// [grants] with one ability switched; switching anything on also gives
/// view, and switching view off clears the area.
PermissionSet withAbility(
  PermissionSet grants,
  PermissionModule m,
  PermissionAction a,
  bool on,
) {
  final next = {...grants.grants};
  if (on) {
    next
      ..add(Permission(m, a))
      ..add(Permission(m, PermissionAction.view));
  } else if (a == PermissionAction.view) {
    next.removeWhere((p) => p.module == m);
  } else {
    next.remove(Permission(m, a));
  }
  return PermissionSet(next);
}

/// "Whose information can they see?" in everyday words.
String scopeQuestionLabel(DataScope s) => switch (s) {
  DataScope.organization => 'Everyone',
  DataScope.assignedBranches => 'Chosen branches',
  DataScope.ownTeam => 'Their team',
  DataScope.ownRecords => 'Only themselves',
};

String scopeQuestionHint(DataScope s) => switch (s) {
  DataScope.organization => 'All branches and all employees.',
  DataScope.assignedBranches =>
    'You pick the branches when you give someone this role.',
  DataScope.ownTeam => 'Only the people who report to them.',
  DataScope.ownRecords => 'Their own attendance, leave and profile.',
};

/// The sentence for one permission, e.g. "Approve or reject leave".
String abilitySentence(Permission p) =>
    accessAreas[p.module]?.abilities[p.action] ?? permissionLabel(p);

/// What a role allows, in plain words: what they see, what they can do,
/// and the areas they can't open.
({String sees, List<String> can, List<String> cannot}) plainSummary(
  RoleDefinition role,
) {
  final can = <String>[];
  final cannot = <String>[];
  for (final m in PermissionModule.values) {
    final area = accessAreas[m]!;
    final held = [
      for (final a in PermissionAction.values)
        if (role.grants.can(m, a) && area.abilities[a] != null) a,
    ];
    if (held.isEmpty) {
      cannot.add(area.name);
      continue;
    }
    for (final a in held) {
      can.add(area.abilities[a]!);
    }
  }
  return (
    sees: switch (role.scope) {
      DataScope.organization => 'They see everyone in the organization.',
      DataScope.assignedBranches =>
        'They see people in the branches chosen for them.',
      DataScope.ownTeam => 'They see the people who report to them.',
      DataScope.ownRecords => 'They see only their own records.',
    },
    can: can,
    cannot: cannot,
  );
}
