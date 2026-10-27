import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/config/app_config.dart';
import '../../../../app/router/route_names.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../../core/utils/clock.dart';
import '../../../../core/utils/zoned_time.dart';
import '../../../../shared/models/app_session.dart';
import '../../../audit/domain/audit.dart';
import '../../../audit/presentation/audit_providers.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../notifications/domain/notifications.dart';
import '../../../notifications/presentation/notification_providers.dart';
import '../../../organization/domain/organization.dart';
import '../../../organization/presentation/providers/organization_providers.dart';
import '../../data/demo_employee_repository.dart';
import '../../domain/custom_field.dart';
import '../../domain/employee.dart';
import '../../domain/employee_import.dart';
import '../../domain/employee_query.dart';
import '../../domain/employee_repository.dart';
import '../../domain/employee_rules.dart';
import '../../domain/field_settings.dart';

final employeeRepositoryProvider = Provider<EmployeeRepository>(
  (ref) => DemoEmployeeRepository(
    latency: ref.watch(demoLatencyProvider),
    // Read at call time: the organization provider depends on this one.
    clock: () => wallTime(
      ref.read(clockProvider)(),
      ref.read(organizationProvider).value?.timeZone ?? defaultTimeZone,
    ),
  ),
);

AppSession _session(Ref ref) =>
    ref.watch(sessionProvider) ?? (throw const PermissionFailure());

/// Every employee of the organization (unfiltered; use
/// [visibleEmployeesProvider] for screens).
final employeesProvider =
    AsyncNotifierProvider<EmployeesNotifier, List<Employee>>(
      EmployeesNotifier.new,
    );

class EmployeesNotifier extends AsyncNotifier<List<Employee>> {
  EmployeeRepository get _repo => ref.read(employeeRepositoryProvider);
  String get _org => ref.read(sessionProvider)!.organizationId;
  String get _by => ref.read(sessionProvider)!.displayName;

  @override
  Future<List<Employee>> build() => ref
      .read(employeeRepositoryProvider)
      .employees(_session(ref).organizationId);

  Future<void> _refresh() async {
    state = AsyncData(await _repo.employees(_org));
    // Branch head counts come from employee records.
    ref.invalidate(branchesProvider);
  }

  Employee? _byId(String id) =>
      state.value?.where((e) => e.id == id).firstOrNull;

  Future<void> _log(
    Employee e,
    String action,
    String summary, {
    String reason = '',
    List<AuditChange> changes = const [],
  }) => ref
      .read(auditRecorderProvider)
      .record(
        action: action,
        entityType: 'Employee',
        entityId: e.id,
        entityLabel: e.fullName,
        entityRoute: AppRoutes.employee(e.id),
        branchId: e.branchId,
        summary: summary,
        reason: reason,
        changes: changes,
      );

  Future<Employee> create(Employee employee, {required bool sendInvite}) async {
    final created = await _repo.create(
      _org,
      employee,
      sendInvite: sendInvite,
      by: _by,
    );
    await _refresh();
    await _log(
      created,
      'employee.create',
      'Created ${created.code}${sendInvite ? ' and sent an invitation' : ''}',
    );
    return created;
  }

  Future<Employee> save(
    Employee employee, {
    required List<String> notes,
  }) async {
    final before = _byId(employee.id);
    final saved = await _repo.update(_org, employee, by: _by, notes: notes);
    await _refresh();
    final changes = before == null
        ? const <AuditChange>[]
        : employeeDiff(before, saved);
    await _log(
      saved,
      'employee.update',
      notes.isNotEmpty
          ? notes.join('; ')
          : (changes.isEmpty
                ? 'Record saved'
                : '${changes.map((c) => c.field).join(', ')} updated'),
      changes: changes,
    );
    // Tell the person when someone else changed their record.
    final session = ref.read(sessionProvider);
    if (changes.isNotEmpty && session?.employeeId != saved.code) {
      await ref
          .read(notifierServiceProvider)
          .send(
            NotifyEvent.profileChanged,
            category: NotificationCategory.people,
            title: 'Profile updated',
            short:
                '${session?.displayName ?? 'HR'} changed your ${changes.map((c) => c.field.toLowerCase()).join(', ')}.',
            employee: saved,
            includeHr: false,
            employeeRoute: AppRoutes.myProfile,
            tone: NotificationTone.user,
          );
    }
    return saved;
  }

  /// Self-service (board S94): the signed-in employee updates only their
  /// own mobile, emergency contact and preferred language.
  Future<Employee> saveOwnContact({
    required String mobile,
    required String emergencyContact,
    required String language,
  }) async {
    // From this notifier's state: selfEmployeeProvider depends on it.
    final code = ref.read(sessionProvider)?.employeeId;
    final self = state.value?.where((e) => e.code == code).firstOrNull;
    if (code == null || self == null) throw const PermissionFailure();
    final updated = self.copyWith(
      mobile: mobile.trim(),
      emergencyContact: emergencyContact.trim(),
      customValues: {...self.customValues, 'preferred_language': language},
    );
    // The same rules as the HR form (D-78), for the fields shown here.
    final errors = {
      for (final MapEntry(:key, :value) in validateEmployee(
        updated,
        others: [
          for (final e in state.value ?? const <Employee>[])
            if (e.id != self.id) e,
        ],
        fields: const [],
        branch: null,
        sendInvite: false,
      ).entries)
        if (key == 'mobile' || key == 'emergencyContact') key: value,
    };
    if (errors.isNotEmpty) {
      throw ValidationFailure('Check your details.', fieldErrors: errors);
    }
    return save(updated, notes: ['Contact details updated by the employee']);
  }

  Future<Employee> setStatus(
    String employeeId,
    EmploymentStatus status, {
    String reason = '',
    DateTime? lastWorkingDay,
  }) async {
    final saved = await _repo.setStatus(
      _org,
      employeeId,
      status,
      by: _by,
      reason: reason,
      lastWorkingDay: lastWorkingDay,
    );
    await _refresh();
    await _log(
      saved,
      status == EmploymentStatus.terminated
          ? 'employee.terminate'
          : (status.isEmployed ? 'employee.reactivate' : 'employee.deactivate'),
      'Status set to ${status.label}',
      reason: reason,
    );
    return saved;
  }

  Future<int> resendInvites(List<String> ids) async {
    final sent = await _repo.resendInvites(_org, ids, by: _by);
    await _refresh();
    if (sent > 0) {
      await ref
          .read(auditRecorderProvider)
          .record(
            action: 'invite.send',
            entityType: 'Invitation',
            entityLabel: ids.length == 1
                ? (_byId(ids.single)?.fullName ?? ids.single)
                : '$sent people',
            branchId: ids.length == 1 ? _byId(ids.single)?.branchId : null,
            summary: '$sent ${sent == 1 ? 'invitation' : 'invitations'} sent',
          );
    }
    return sent;
  }

  Future<int> changeBranch(
    List<String> ids, {
    required String branchId,
    required String? managerId,
    required DateTime effectiveFrom,
  }) async {
    final moved = await _repo.changeBranch(
      _org,
      ids,
      branchId: branchId,
      managerId: managerId,
      effectiveFrom: effectiveFrom,
      by: _by,
    );
    await _refresh();
    return moved;
  }

  /// Deactivates each person; returns those refused (e.g. still managing
  /// people) with the reason.
  Future<Map<String, String>> deactivateAll(
    List<String> ids,
    String reason,
  ) async {
    final refused = <String, String>{};
    for (final id in ids) {
      try {
        await _repo.setStatus(
          _org,
          id,
          EmploymentStatus.inactive,
          by: _by,
          reason: reason,
        );
      } on Failure catch (f) {
        refused[id] = f.message;
      }
    }
    await _refresh();
    return refused;
  }

  Future<void> sendPasswordReset(String employeeId) =>
      _repo.sendPasswordReset(_org, employeeId);

  Future<ImportRecord> commitImport({
    required String fileName,
    required ImportPlan plan,
    required List<NotImportedRow> skipped,
    required bool sendInvites,
  }) async {
    final record = await _repo.commitImport(
      _org,
      fileName: fileName,
      plan: plan,
      skipped: skipped,
      sendInvites: sendInvites,
      by: _by,
    );
    await _refresh();
    ref.invalidate(importsProvider);
    await ref
        .read(auditRecorderProvider)
        .record(
          action: 'import.commit',
          entityType: 'Import',
          entityLabel: fileName,
          entityRoute: AppRoutes.importResult(record.id),
          source: AuditSource.import,
          summary:
              '${record.created} created · ${record.updated} updated · ${record.failed} failed',
        );
    return record;
  }
}

/// Can [session] see [e]? Data scope from the role (PRD §3.1): the whole
/// organization, assigned branches, own team, or own record.
bool canSeeEmployee(AppSession session, Employee e, {Employee? self}) =>
    switch (session.scope) {
      DataScope.organization => true,
      DataScope.assignedBranches => session.coversBranch(e.branchId),
      DataScope.ownTeam =>
        self != null && (e.id == self.id || e.managerId == self.id),
      DataScope.ownRecords => self != null && e.id == self.id,
    };

/// The signed-in member's own employee record, if they have one.
final selfEmployeeProvider = Provider<Employee?>((ref) {
  final code = ref.watch(sessionProvider)?.employeeId;
  final all = ref.watch(employeesProvider).value;
  if (code == null || all == null) return null;
  return all.where((e) => e.code == code).firstOrNull;
});

/// Employees the signed-in member may see.
final visibleEmployeesProvider = Provider<AsyncValue<List<Employee>>>((ref) {
  final session = ref.watch(sessionProvider);
  final self = ref.watch(selfEmployeeProvider);
  return ref
      .watch(employeesProvider)
      .whenData(
        (all) => session == null
            ? const []
            : [
                for (final e in all)
                  if (canSeeEmployee(session, e, self: self)) e,
              ],
      );
});

final employeeProvider = Provider.family<AsyncValue<Employee?>, String>(
  (ref, id) => ref
      .watch(visibleEmployeesProvider)
      .whenData((list) => list.where((e) => e.id == id).firstOrNull),
);

final customFieldsProvider =
    AsyncNotifierProvider<CustomFieldsNotifier, List<CustomField>>(
      CustomFieldsNotifier.new,
    );

class CustomFieldsNotifier extends AsyncNotifier<List<CustomField>> {
  EmployeeRepository get _repo => ref.read(employeeRepositoryProvider);
  String get _org => ref.read(sessionProvider)!.organizationId;

  @override
  Future<List<CustomField>> build() => ref
      .read(employeeRepositoryProvider)
      .customFields(_session(ref).organizationId);

  Future<CustomField> save(
    CustomField field, {
    Map<String, String> renamedOptions = const {},
  }) async {
    final saved = await _repo.saveCustomField(
      _org,
      field,
      renamedOptions: renamedOptions,
    );
    state = AsyncData(await _repo.customFields(_org));
    if (renamedOptions.isNotEmpty) ref.invalidate(employeesProvider);
    return saved;
  }

  Future<void> reorder(List<String> ids) async {
    // Show the new order straight away.
    final current = state.value ?? const [];
    state = AsyncData([
      for (final id in ids) current.firstWhere((f) => f.id == id),
    ]);
    await _repo.reorderCustomFields(_org, ids);
  }
}

/// Which built-in fields the forms and imports ask for (D-73).
final fieldSettingsProvider =
    AsyncNotifierProvider<FieldSettingsNotifier, EmployeeFieldSettings>(
      FieldSettingsNotifier.new,
    );

class FieldSettingsNotifier extends AsyncNotifier<EmployeeFieldSettings> {
  @override
  Future<EmployeeFieldSettings> build() => ref
      .read(employeeRepositoryProvider)
      .fieldSettings(_session(ref).organizationId);

  Future<void> save(EmployeeFieldSettings settings) async {
    final session = _session(ref);
    final before = state.value ?? const EmployeeFieldSettings();
    final saved = await ref
        .read(employeeRepositoryProvider)
        .saveFieldSettings(
          session.organizationId,
          settings,
          by: session.displayName,
        );
    state = AsyncData(saved);
    await ref
        .read(auditRecorderProvider)
        .record(
          action: 'settings.employeeFields',
          entityType: 'Employee fields',
          entityLabel: 'Employee fields',
          entityRoute: AppRoutes.employeeFields,
          summary: 'Built-in employee fields updated',
          changes: [
            for (final f in StandardField.values)
              if (before.ruleOf(f) != saved.ruleOf(f))
                (
                  field: f.label,
                  before: before.ruleOf(f).label,
                  after: saved.ruleOf(f).label,
                ),
          ],
        );
  }
}

final importsProvider = FutureProvider<List<ImportRecord>>(
  (ref) => ref
      .watch(employeeRepositoryProvider)
      .imports(_session(ref).organizationId),
);

/// The directory's search, filters and paging; kept while the session lasts
/// so coming back from a profile keeps your place.
final directoryQueryProvider =
    NotifierProvider<DirectoryQueryNotifier, EmployeeQuery>(
      DirectoryQueryNotifier.new,
    );

class DirectoryQueryNotifier extends Notifier<EmployeeQuery> {
  @override
  EmployeeQuery build() {
    final session = ref.watch(sessionProvider);
    // Branch-scoped roles with one branch start filtered to it.
    final only =
        session != null &&
            session.role.scope == DataScope.assignedBranches &&
            session.branchIds.length == 1
        ? session.branchIds.single
        : null;
    return EmployeeQuery(branchId: only);
  }

  void set(EmployeeQuery query) => state = query;
}

/// Field-level changes between two versions of a record, for the audit
/// trail. Sensitive values are stored and masked when shown.
List<AuditChange> employeeDiff(Employee a, Employee b) => [
  for (final (field, x, y) in [
    ('Name', a.fullName, b.fullName),
    ('Work email', a.workEmail, b.workEmail),
    ('Personal email', a.personalEmail, b.personalEmail),
    ('Mobile', a.mobile, b.mobile),
    ('Emergency contact', a.emergencyContact, b.emergencyContact),
    ('Designation', a.designation, b.designation),
    ('Department', a.department, b.department),
    ('Branch', a.branchId, b.branchId),
    ('Manager', a.managerId ?? '—', b.managerId ?? '—'),
    ('Shift', a.shift, b.shift),
    ('Role', a.role.label, b.role.label),
    ('Status', a.status.label, b.status.label),
  ])
    if (x != y)
      (field: field, before: x.isEmpty ? '—' : x, after: y.isEmpty ? '—' : y),
];
