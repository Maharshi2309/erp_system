import '../domain/branch.dart';
import '../domain/setup_progress.dart';

String punchMethodLabel(PunchMethod method) => switch (method) {
  PunchMethod.app => 'Mobile app',
  PunchMethod.kiosk => 'Shared kiosk',
  PunchMethod.both => 'App + kiosk',
};

String holidaySourceLabel(HolidaySource source) => switch (source) {
  HolidaySource.gujarat => 'Gujarat calendar',
  HolidaySource.national => 'National holidays',
  HolidaySource.none => 'Custom list',
};

String leaveApprovalLabel(LeaveApproval approval) => switch (approval) {
  LeaveApproval.manager => 'manager approves',
  LeaveApproval.managerThenHr => 'manager then HR',
  LeaveApproval.owner => 'you approve',
};

/// One-line summary of a saved step, as on the checklist (board S21–S22).
String stepNote(Branch branch, SetupStep step) {
  final progress = SetupProgress(branch);
  switch (step) {
    case SetupStep.basics:
      return hoursSummary(branch.hours);
    case SetupStep.attendance:
      final a = branch.attendance;
      if (a == null) return step.description;
      return '${punchMethodLabel(a.method)} · ${a.graceMinutes} min grace';
    case SetupStep.holidays:
      final h = branch.holidays;
      if (h == null) return step.description;
      final n = h.observedCount;
      return '$n ${n == 1 ? 'holiday' : 'holidays'} · ${holidaySourceLabel(h.source)}';
    case SetupStep.leave:
      final l = branch.leave;
      if (l == null) return step.description;
      if (l.enabledCount == 0) return 'No leave types switched on';
      return '${l.enabledCount} leave types · ${leaveApprovalLabel(l.approval)}';
    case SetupStep.roles:
      final r = branch.roles;
      if (r == null) return step.description;
      if (r.manager == BranchManagerChoice.owner) {
        return 'You manage this branch';
      }
      return r.isComplete
          ? 'Manager invited · ${r.managerEmail.trim()}'
          : 'Manager email missing';
    case SetupStep.reminders:
      final r = branch.reminders;
      if (r == null) return step.description;
      return '${r.onCount} of 3 switched on';
    case SetupStep.review:
      if (progress.isComplete(step)) return 'Marked ready';
      if (branch.reviewed) return 'Something changed since review';
      return 'Unlocks when the steps above are done';
  }
}

/// "10 min grace · early departure after 30 min · half day if 120 min late".
String attendanceSummary(AttendanceRules a) =>
    '${punchMethodLabel(a.method)} · ${a.graceMinutes} min grace · early '
    'departure after ${a.earlyLeaveMinutes} min · half day if '
    '${a.halfDayLateMinutes} min late';
