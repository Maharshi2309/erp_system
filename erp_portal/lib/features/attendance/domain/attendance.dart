import 'package:flutter/foundation.dart';

enum PunchKind {
  punchIn('Punch in'),
  punchOut('Punch out'),
  breakStart('Break started'),
  breakEnd('Break ended');

  const PunchKind(this.label);

  final String label;
}

enum PunchSource {
  app('Mobile app'),
  kiosk('Gate kiosk'),
  web('Web'),
  correction('Manual · correction');

  const PunchSource(this.label);

  final String label;
}

/// One recorded event. Never edited or deleted: corrections add events
/// that replace it, so the original stays in the history (PRD §7.4).
@immutable
class Punch {
  const Punch({
    required this.id,
    required this.employeeId,
    required this.at,
    required this.kind,
    required this.source,
    this.correctionId,
    this.replaces,
  });

  final String id;
  final String employeeId;

  /// UTC instant.
  final DateTime at;
  final PunchKind kind;
  final PunchSource source;

  /// Set on events added by a correction.
  final String? correctionId;

  /// The original event this one replaces (a moved time).
  final String? replaces;
}

enum CorrectionStatus {
  pending('Waiting for approval'),
  approved('Approved'),
  rejected('Rejected');

  const CorrectionStatus(this.label);

  final String label;
}

/// A change to one punch: add a missing one, or move one ([replaces]).
@immutable
class CorrectionChange {
  const CorrectionChange({required this.kind, required this.at, this.replaces});

  final PunchKind kind;

  /// UTC instant.
  final DateTime at;
  final String? replaces;
}

/// An authorised correction (board S55). It counts only once approved; the
/// record keeps its exception until then.
@immutable
class Correction {
  const Correction({
    required this.id,
    required this.employeeId,
    required this.workDate,
    required this.changes,
    required this.reason,
    required this.by,
    required this.createdAt,
    this.byEmployeeId,
    this.status = CorrectionStatus.approved,
    this.approverNote = '',
    this.decidedBy,
    this.decidedAt,
    this.requestId,
  });

  final String id;
  final String employeeId;

  /// Floating date of the work day.
  final DateTime workDate;
  final List<CorrectionChange> changes;
  final String reason;

  /// Name of the person who made the correction.
  final String by;
  final String? byEmployeeId;
  final DateTime createdAt;
  final CorrectionStatus status;

  /// Who must approve, e.g. "Hetal Shah (HR Admin)".
  final String approverNote;
  final String? decidedBy;
  final DateTime? decidedAt;

  /// The employee request this answers, if any.
  final String? requestId;

  Correction decide({
    required bool approve,
    required String by,
    required DateTime at,
  }) => Correction(
    id: id,
    employeeId: employeeId,
    workDate: workDate,
    changes: changes,
    reason: reason,
    by: this.by,
    byEmployeeId: byEmployeeId,
    createdAt: createdAt,
    status: approve ? CorrectionStatus.approved : CorrectionStatus.rejected,
    approverNote: approverNote,
    decidedBy: by,
    decidedAt: at,
    requestId: requestId,
  );
}

enum RequestStatus { open, resolved, rejected }

/// An employee's own correction request (Q-12 option b: proposed time and
/// reason). Answered by a correction or rejected with a reason.
@immutable
class CorrectionRequest {
  const CorrectionRequest({
    required this.id,
    required this.employeeId,
    required this.workDate,
    required this.kind,
    required this.proposedAt,
    required this.message,
    required this.createdAt,
    this.status = RequestStatus.open,
    this.rejectReason = '',
  });

  final String id;
  final String employeeId;
  final DateTime workDate;

  /// The punch the employee says is missing or wrong.
  final PunchKind kind;

  /// UTC instant they propose.
  final DateTime proposedAt;
  final String message;

  /// Floating local time it was sent.
  final DateTime createdAt;
  final RequestStatus status;
  final String rejectReason;

  CorrectionRequest close(RequestStatus status, {String reason = ''}) =>
      CorrectionRequest(
        id: id,
        employeeId: employeeId,
        workDate: workDate,
        kind: kind,
        proposedAt: proposedAt,
        message: message,
        createdAt: createdAt,
        status: status,
        rejectReason: reason,
      );
}

/// A reminder sent to an employee about one open day (board S54).
typedef PunchReminder = ({String employeeId, DateTime workDate, DateTime at});

/// Everything recorded for an organization.
@immutable
class AttendanceData {
  const AttendanceData({
    this.punches = const [],
    this.corrections = const [],
    this.requests = const [],
    this.reminders = const [],
  });

  final List<Punch> punches;
  final List<Correction> corrections;
  final List<CorrectionRequest> requests;
  final List<PunchReminder> reminders;
}
