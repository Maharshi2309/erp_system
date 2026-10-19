import 'permissions.dart';

/// Built-in roles (board S67). Custom roles arrive in Phase 7.
enum SystemRole {
  owner('Owner', DataScope.organization),
  hrAdmin('HR Admin', DataScope.organization),
  branchManager('Branch Manager', DataScope.assignedBranches),
  attendanceManager('Attendance Manager', DataScope.assignedBranches),
  leaveApprover('Leave Approver', DataScope.ownTeam),
  employee('Employee', DataScope.ownRecords);

  const SystemRole(this.label, this.scope);

  final String label;
  final DataScope scope;

  /// Two-step sign-in is required for admin access by default (board S83).
  bool get requiresTwoStep =>
      this == owner ||
      this == hrAdmin ||
      this == branchManager ||
      this == attendanceManager;

  PermissionSet get permissions => switch (this) {
    owner => PermissionSet.all(),
    // HR sees every branch (answer 20 Oct 2026); only the owner edits them.
    hrAdmin => PermissionSet.of(const {
      PermissionModule.organization: [PermissionAction.view],
      PermissionModule.employees: PermissionAction.values,
      PermissionModule.attendance: PermissionAction.values,
      PermissionModule.leave: PermissionAction.values,
      PermissionModule.holidays: PermissionAction.values,
      PermissionModule.settings: [PermissionAction.view, PermissionAction.edit],
      PermissionModule.reports: [
        PermissionAction.view,
        PermissionAction.export,
      ],
      PermissionModule.importExport: PermissionAction.values,
      PermissionModule.auditLog: [
        PermissionAction.view,
        PermissionAction.export,
      ],
    }),
    // Matrix on board S68 (after the pending changes shown there).
    branchManager => PermissionSet.of(const {
      PermissionModule.organization: [PermissionAction.view],
      PermissionModule.employees: [
        PermissionAction.view,
        PermissionAction.create,
        PermissionAction.edit,
        PermissionAction.export,
      ],
      PermissionModule.attendance: [
        PermissionAction.view,
        PermissionAction.approve,
        PermissionAction.correct,
        PermissionAction.export,
      ],
      PermissionModule.leave: [
        PermissionAction.view,
        PermissionAction.create,
        PermissionAction.approve,
        PermissionAction.export,
      ],
      PermissionModule.holidays: [PermissionAction.view],
      PermissionModule.reports: [
        PermissionAction.view,
        PermissionAction.export,
      ],
    }),
    attendanceManager => PermissionSet.of(const {
      PermissionModule.attendance: [
        PermissionAction.view,
        PermissionAction.approve,
        PermissionAction.correct,
        PermissionAction.export,
      ],
    }),
    leaveApprover => PermissionSet.of(const {
      PermissionModule.leave: [PermissionAction.view, PermissionAction.approve],
    }),
    employee => const PermissionSet.none(),
  };
}
