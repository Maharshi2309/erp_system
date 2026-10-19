import 'branch.dart';

/// Branch setup steps in checklist order (board S20).
enum SetupStep {
  basics(
    'Branch details & working hours',
    'Address and weekly opening hours',
    25,
  ),
  attendance(
    'Attendance rules',
    'How people punch in, grace period, early-leave rules',
    20,
  ),
  holidays('Holiday calendar', 'Public and branch-specific holidays', 15),
  leave('Leave policies', 'Leave types, yearly allowance and approvals', 20),
  roles(
    'Roles & permissions',
    'Who manages the branch and what employees can do',
    15,
  ),
  reminders(
    'Reminders & notifications',
    'Punch reminders and manager summaries',
    0,
  ),
  review('Final review', 'Check everything and mark the branch ready', 5);

  const SetupStep(this.title, this.description, this.weight);

  final String title;
  final String description;

  /// Share of the branch's percentage; 0 for the optional step.
  final int weight;

  bool get isOptional => this == reminders;

  /// The five steps the final review requires.
  static const required = [basics, attendance, holidays, leave, roles];
}

/// Branch setup progress, always computed from saved data — never a
/// counter (design guide p. 6).
class SetupProgress {
  SetupProgress(this.branch);

  final Branch branch;

  bool basicsComplete() =>
      branch.name.trim().isNotEmpty &&
      branch.address.trim().isNotEmpty &&
      branch.city.trim().isNotEmpty &&
      RegExp(r'^\d{6}$').hasMatch(branch.pin) &&
      branch.hours.any((d) => d.open) &&
      branch.hours.every((d) => d.isValid);

  bool isComplete(SetupStep step) => switch (step) {
    SetupStep.basics => basicsComplete(),
    SetupStep.attendance => branch.attendance?.isComplete ?? false,
    SetupStep.holidays => branch.holidays?.isComplete ?? false,
    SetupStep.leave => branch.leave?.isComplete ?? false,
    SetupStep.roles => branch.roles?.isComplete ?? false,
    SetupStep.reminders => branch.reminders != null,
    SetupStep.review => branch.reviewed && SetupStep.required.every(isComplete),
  };

  /// Saved before but no longer valid — the percentage went down.
  bool needsAttention(SetupStep step) => switch (step) {
    SetupStep.basics => !basicsComplete(),
    SetupStep.attendance => branch.attendance != null && !isComplete(step),
    SetupStep.holidays => branch.holidays != null && !isComplete(step),
    SetupStep.leave => branch.leave != null && !isComplete(step),
    SetupStep.roles => branch.roles != null && !isComplete(step),
    SetupStep.reminders => false,
    SetupStep.review => branch.reviewed && !isComplete(step),
  };

  int get percent => SetupStep.values
      .where((s) => !s.isOptional && isComplete(s))
      .fold(0, (sum, s) => sum + s.weight);

  bool get isReady => percent == 100;

  List<SetupStep> get attention =>
      SetupStep.values.where(needsAttention).toList();

  /// First incomplete required step, or null when ready.
  SetupStep? get next => [
    ...SetupStep.required,
    SetupStep.review,
  ].where((s) => !isComplete(s)).firstOrNull;

  int get requiredDone =>
      SetupStep.values.where((s) => !s.isOptional && isComplete(s)).length;

  /// Can the final review be done (all five required steps complete)?
  bool get canReview => SetupStep.required.every(isComplete);
}

enum BranchSetupStatus {
  complete('Setup complete'),
  needsAttention('Needs attention'),
  basicsDone('Basics done'),
  inProgress('In progress');

  const BranchSetupStatus(this.label);

  final String label;
}

BranchSetupStatus setupStatusOf(Branch branch) {
  final progress = SetupProgress(branch);
  if (progress.isReady) return BranchSetupStatus.complete;
  if (progress.attention.isNotEmpty) return BranchSetupStatus.needsAttention;
  if (progress.percent == 25) return BranchSetupStatus.basicsDone;
  return BranchSetupStatus.inProgress;
}
