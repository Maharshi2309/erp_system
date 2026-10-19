import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/config/app_config.dart';
import '../../../app/router/route_names.dart';
import '../../../core/errors/failure.dart';
import '../../../core/permissions/permissions.dart';
import '../../../core/permissions/system_roles.dart';
import '../../../core/utils/zoned_time.dart';
import '../../../shared/models/app_session.dart';
import '../../audit/presentation/audit_providers.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../employees/domain/employee.dart';
import '../../employees/presentation/providers/employee_providers.dart';
import '../../holidays/presentation/calendar_providers.dart';
import '../../notifications/domain/notifications.dart';
import '../../notifications/presentation/notification_providers.dart';
import '../../organization/presentation/providers/organization_providers.dart';
import '../data/demo_leave_repository.dart';
import '../domain/leave.dart';
import '../domain/leave_book.dart';
import '../domain/leave_repository.dart';

final leaveRepositoryProvider = Provider<LeaveRepository>(
  (ref) => DemoLeaveRepository(
    latency: ref.watch(demoLatencyProvider),
    // Read at call time to avoid a dependency cycle at build.
    today: () => dateOnly(ref.read(orgNowProvider)()),
    now: () => ref.read(orgNowProvider)(),
  ),
);

/// All leave data of the organization.
final leaveDataProvider = AsyncNotifierProvider<LeaveNotifier, LeaveData>(
  LeaveNotifier.new,
);

class LeaveNotifier extends AsyncNotifier<LeaveData> {
  LeaveRepository get _repo => ref.read(leaveRepositoryProvider);
  AppSession get _session => ref.read(sessionProvider)!;
  String get _org => _session.organizationId;

  @override
  Future<LeaveData> build() async {
    final session = ref.watch(sessionProvider);
    if (session == null) throw const PermissionFailure();
    final repo = ref.watch(leaveRepositoryProvider);
    if (repo is DemoLeaveRepository && !repo.isSeeded(session.organizationId)) {
      repo.ensureSeeded(
        session.organizationId,
        employees: await ref
            .read(employeeRepositoryProvider)
            .employees(session.organizationId),
        branches: await ref
            .read(organizationRepositoryProvider)
            .branches(session.organizationId),
      );
    }
    return repo.load(session.organizationId);
  }

  Future<void> _reload() async => state = AsyncData(await _repo.load(_org));

  /// Built from this notifier's state: reading [leaveBookProvider] here
  /// would make the provider depend on itself.
  LeaveBook _book() => LeaveBook(
    data: state.value!,
    employees: ref.read(employeesProvider).value!,
    branches: ref.read(branchesProvider).value!,
    today: dateOnly(ref.read(orgNowProvider)()),
    calendar: ref.read(workCalendarProvider),
  );

  /// "Casual leave · 27–28 Oct (2 days)".
  String _what(LeaveRequest r) {
    final b = _book();
    final type = b.data.type(r.typeKey)?.name ?? r.typeKey;
    final days = b.daysOf(r);
    return '$type · ${leaveRange(r.from, r.to)} (${formatDays(days)} ${days == 1 ? 'day' : 'days'})';
  }

  Employee? _person(String id) =>
      ref.read(employeesProvider).value?.where((e) => e.id == id).firstOrNull;

  Future<void> _log(
    LeaveRequest r,
    String action,
    String summary, {
    String reason = '',
  }) async {
    final e = _person(r.employeeId);
    await ref
        .read(auditRecorderProvider)
        .record(
          action: action,
          entityType: 'Leave request',
          entityId: r.id,
          entityLabel: 'Leave #${r.id}',
          entityRoute: '${AppRoutes.leave}?request=${r.id}',
          branchId: e?.branchId,
          summary: summary,
          reason: reason,
        );
  }

  /// Tells the next approver, or HR when the step is HR's.
  Future<void> _tellApprover(LeaveRequest r) async {
    final e = _person(r.employeeId);
    final step = r.currentStep;
    if (e == null || step == null) return;
    final approver = step.approverId == null ? null : _person(step.approverId!);
    await ref
        .read(notifierServiceProvider)
        .send(
          NotifyEvent.leaveSubmitted,
          category: NotificationCategory.approvals,
          title: step.kind == ApproverKind.hr
              ? '${_book().data.type(r.typeKey)?.name ?? 'Leave'} needs HR approval'
              : 'Leave request to approve',
          short: '${e.fullName} · ${_what(r)}',
          body: '${e.fullName} asked for ${_what(r)}.',
          facts: [('Request', r.id), ('Dates', leaveRange(r.from, r.to))],
          approver: approver,
          includeHr: step.kind == ApproverKind.hr,
          adminRoute: approver?.role == SystemRole.leaveApprover
              ? AppRoutes.teamApprovals
              : '${AppRoutes.leave}?request=${r.id}',
          cta: 'Review request',
        );
  }

  Future<void> _tellEmployee(
    LeaveRequest r,
    NotifyEvent event,
    String title,
    String short,
    NotificationTone tone,
  ) async {
    final e = _person(r.employeeId);
    if (e == null) return;
    await ref
        .read(notifierServiceProvider)
        .send(
          event,
          category: NotificationCategory.approvals,
          title: title,
          short: short,
          employee: e,
          includeHr: false,
          employeeRoute: AppRoutes.myLeaveRequest(r.id),
          adminRoute: '${AppRoutes.leave}?request=${r.id}',
          tone: tone,
        );
  }

  /// Validates, routes and sends a request for the signed-in employee.
  Future<LeaveRequest> submit({
    required String typeKey,
    required DateTime from,
    required DateTime to,
    required HalfDay half,
    required String reason,
  }) async {
    final self =
        ref.read(selfEmployeeProvider) ??
        (throw const PermissionFailure('You don’t have an employee record.'));
    final book = _book();
    final errors = book.validate(
      e: self,
      typeKey: typeKey,
      from: from,
      to: to,
      half: half,
    );
    if (errors.isNotEmpty) {
      throw ValidationFailure(errors.values.first, fieldErrors: errors);
    }
    final type = book.data.type(typeKey)!;
    final days = book
        .countDays(self, type, from, to, half)
        .fold(0.0, (s, d) => s + d.counted);
    final steps = book.route(self, type, days);
    final now = ref.read(orgNowProvider)();
    final saved = await _repo.submit(
      _org,
      LeaveRequest(
        id: '',
        employeeId: self.id,
        typeKey: typeKey,
        from: from,
        to: to,
        half: half,
        reason: reason.trim(),
        createdAt: now,
        steps: steps,
        history: [
          (at: now, text: 'Submitted', by: self.fullName),
          for (final s in steps.where((s) => s.note.isNotEmpty))
            (at: now, text: s.note, by: 'System'),
        ],
      ),
    );
    await _reload();
    await _log(saved, 'leave.request', 'Requested ${_what(saved)}');
    await _tellApprover(saved);
    return saved;
  }

  Future<LeaveRequest> amend(
    LeaveRequest original, {
    required String typeKey,
    required DateTime from,
    required DateTime to,
    required HalfDay half,
    required String reason,
  }) async {
    final self = ref.read(selfEmployeeProvider)!;
    final book = _book();
    final errors = book.validate(
      e: self,
      typeKey: typeKey,
      from: from,
      to: to,
      half: half,
      amending: original.id,
    );
    if (errors.isNotEmpty) {
      throw ValidationFailure(errors.values.first, fieldErrors: errors);
    }
    final type = book.data.type(typeKey)!;
    final days = book
        .countDays(self, type, from, to, half)
        .fold(0.0, (s, d) => s + d.counted);
    final saved = await _repo.amend(
      _org,
      original.copyWith(
        typeKey: typeKey,
        from: from,
        to: to,
        half: half,
        reason: reason.trim(),
        steps: book.route(self, type, days),
      ),
      by: self.fullName,
    );
    await _reload();
    await _log(
      saved,
      'leave.amend',
      'Dates changed to ${_what(saved)} · sent for approval again',
    );
    await _tellApprover(saved);
    return saved;
  }

  Future<LeaveRequest> decide(
    LeaveRequest r, {
    required bool approve,
    String note = '',
  }) async {
    final self = ref.read(selfEmployeeProvider);
    if (!_session.permissions.can(
          PermissionModule.leave,
          PermissionAction.approve,
        ) ||
        !_book().canDecide(
          r,
          role: _session.role,
          self: self,
          branchIds: _session.branchIds,
        )) {
      throw const PermissionFailure('You can’t decide this request.');
    }
    final saved = await _repo.decide(
      _org,
      r.id,
      approve: approve,
      by: _session.displayName,
      byEmployeeId: self?.id ?? _session.userId,
      note: note,
    );
    await _reload();
    final who = _person(r.employeeId)?.fullName ?? '';
    await _log(
      saved,
      approve ? 'leave.approve' : 'leave.reject',
      approve
          ? 'Approved ${_what(saved)} for $who'
          : 'Rejected — “${note.trim()}”',
      reason: note.trim(),
    );
    if (saved.status == LeaveStatus.pending) {
      await _tellApprover(saved);
    } else {
      await _tellEmployee(
        saved,
        NotifyEvent.leaveDecided,
        approve ? 'Leave approved' : 'Leave not approved',
        approve
            ? '${_what(saved)} approved by ${_session.displayName}.'
            : '${_what(saved)}: “${note.trim()}”',
        approve ? NotificationTone.ok : NotificationTone.no,
      );
    }
    return saved;
  }

  Future<LeaveRequest> requestChanges(LeaveRequest r, String note) async {
    if (!_session.permissions.can(
          PermissionModule.leave,
          PermissionAction.approve,
        ) ||
        !_book().canDecide(
          r,
          role: _session.role,
          self: ref.read(selfEmployeeProvider),
          branchIds: _session.branchIds,
        )) {
      throw const PermissionFailure('You can’t decide this request.');
    }
    final saved = await _repo.requestChanges(
      _org,
      r.id,
      by: _session.displayName,
      note: note,
    );
    await _reload();
    await _log(
      saved,
      'leave.changes',
      'Changes requested — “${note.trim()}”',
      reason: note.trim(),
    );
    await _tellEmployee(
      saved,
      NotifyEvent.leaveDecided,
      'Changes requested on your leave',
      '${_what(saved)}: “${note.trim()}”',
      NotificationTone.user,
    );
    return saved;
  }

  Future<void> withdraw(LeaveRequest r) async {
    await _repo.withdraw(_org, r.id, by: _session.displayName);
    await _reload();
    await _log(r, 'leave.withdraw', 'Withdrew ${_what(r)}');
    await _tellManager(r, 'withdrew');
  }

  Future<void> cancel(LeaveRequest r) async {
    await _repo.cancel(_org, r.id, by: _session.displayName);
    await _reload();
    await _log(r, 'leave.cancel', 'Cancelled approved ${_what(r)}');
    await _tellManager(r, 'cancelled');
  }

  Future<void> _tellManager(LeaveRequest r, String verb) async {
    final e = _person(r.employeeId);
    if (e == null) return;
    await ref
        .read(notifierServiceProvider)
        .send(
          NotifyEvent.leaveWithdrawn,
          category: NotificationCategory.approvals,
          title: 'Leave $verb',
          short: '${e.fullName} $verb ${_what(r)}.',
          employee: e,
          includeHr: false,
          adminRoute: '${AppRoutes.leave}?request=${r.id}',
        );
  }

  Future<LeaveAdjustment> adjust({
    required Employee e,
    required String typeKey,
    required double days,
    required DateTime effective,
    required String reason,
  }) async {
    final saved = await _repo.adjust(
      _org,
      LeaveAdjustment(
        id: '',
        employeeId: e.id,
        typeKey: typeKey,
        days: days,
        effective: effective,
        reason: reason,
        by: _session.displayName,
      ),
    );
    await _reload();
    final type = state.value?.type(typeKey)?.name ?? typeKey;
    await ref
        .read(auditRecorderProvider)
        .record(
          action: 'leave.adjust',
          entityType: 'Leave balance',
          entityId: e.id,
          entityLabel: '${e.fullName} · $type',
          entityRoute: AppRoutes.employee(e.id),
          branchId: e.branchId,
          summary:
              '${days > 0 ? '+' : ''}${formatDays(days)} days $type (${saved.id})',
          reason: reason,
        );
    return saved;
  }

  /// Saves a type; a new one ([LeaveType.key] empty) gets a key from its name.
  Future<LeaveType> saveType(LeaveType type) async {
    var t = type;
    if (t.key.isEmpty) {
      final taken = {
        for (final x in state.value?.types ?? <LeaveType>[]) x.key,
      };
      final base = t.name
          .toLowerCase()
          .replaceAll(RegExp('[^a-z0-9]+'), '_')
          .replaceAll(RegExp(r'^_+|_+$'), '');
      var key = base.isEmpty ? 'type' : base;
      for (var i = 2; taken.contains(key); i++) {
        key = '${base}_$i';
      }
      t = t.copyWith(key: key);
    }
    final before = state.value?.type(t.key);
    final saved = await _repo.saveType(_org, t);
    await _reload();
    await ref
        .read(auditRecorderProvider)
        .record(
          action: before == null ? 'leave_type.create' : 'leave_type.update',
          entityType: 'Leave type',
          entityId: saved.key,
          entityLabel: saved.name,
          entityRoute: AppRoutes.leaveTypes,
          summary: before == null
              ? 'Created ${saved.name} (${saved.summary})'
              : '${saved.name}: ${saved.summary}',
          changes: [
            if (before != null && before.summary != saved.summary)
              (
                field: 'Allowance',
                before: before.summary,
                after: saved.summary,
              ),
            if (before != null && before.active != saved.active)
              (
                field: 'Status',
                before: before.active ? 'Active' : 'Inactive',
                after: saved.active ? 'Active' : 'Inactive',
              ),
          ],
        );
    return saved;
  }

  Future<LeavePolicy> savePolicy(LeavePolicy policy) async {
    final saved = await _repo.savePolicy(
      _org,
      policy.copyWith(updatedBy: _session.displayName),
    );
    await _reload();
    await ref
        .read(auditRecorderProvider)
        .record(
          action: 'policy.update',
          entityType: 'Leave policy',
          entityLabel: 'Leave policy',
          entityRoute: AppRoutes.leavePolicy,
          summary:
              '${saved.routes.length} approval routes · ${saved.blackouts.length} blackout periods · backdated sick ${saved.backdatedSickDays} days',
        );
    return saved;
  }
}

/// Leave computed for today.
final leaveBookProvider = Provider<AsyncValue<LeaveBook>>((ref) {
  final data = ref.watch(leaveDataProvider);
  final employees = ref.watch(employeesProvider);
  final branches = ref.watch(branchesProvider);
  final calendar = ref.watch(workCalendarProvider);
  final today = dateOnly(ref.watch(orgNowProvider)());
  for (final v in [data, employees, branches]) {
    if (v.hasError) return AsyncError(v.error!, v.stackTrace!);
  }
  if (!data.hasValue || !employees.hasValue || !branches.hasValue) {
    return const AsyncLoading();
  }
  return AsyncData(
    LeaveBook(
      data: data.value!,
      employees: employees.value!,
      branches: branches.value!,
      today: today,
      calendar: calendar,
    ),
  );
});
