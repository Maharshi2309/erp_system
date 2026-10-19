import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/config/app_config.dart';
import '../../../app/router/route_names.dart';
import '../../../core/errors/failure.dart';
import '../../../core/utils/zoned_time.dart';
import '../../audit/domain/audit.dart';
import '../../audit/presentation/audit_providers.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../employees/domain/employee.dart';
import '../../employees/presentation/providers/employee_providers.dart';
import '../../notifications/domain/notifications.dart';
import '../../notifications/presentation/notification_providers.dart';
import '../../organization/presentation/providers/organization_providers.dart';
import '../data/demo_calendar_repository.dart';
import '../domain/calendar_repository.dart';
import '../domain/company_holiday.dart';
import '../domain/work_calendar.dart';

final calendarRepositoryProvider = Provider<CalendarRepository>(
  (ref) => DemoCalendarRepository(
    latency: ref.watch(demoLatencyProvider),
    // Read at call time to avoid a dependency cycle at build.
    today: () => dateOnly(ref.read(orgNowProvider)()),
  ),
);

/// Seeds the demo calendar for the signed-in organization once.
Future<CalendarRepository> _seeded(Ref ref, String organizationId) async {
  final repo = ref.read(calendarRepositoryProvider);
  if (repo is DemoCalendarRepository && !repo.isSeeded(organizationId)) {
    repo.ensureSeeded(
      organizationId,
      await ref.read(employeeRepositoryProvider).employees(organizationId),
    );
  }
  return repo;
}

/// The organization holiday calendar (boards S62–S65).
final companyHolidaysProvider =
    AsyncNotifierProvider<CompanyHolidaysNotifier, List<CompanyHoliday>>(
      CompanyHolidaysNotifier.new,
    );

class CompanyHolidaysNotifier extends AsyncNotifier<List<CompanyHoliday>> {
  String get _org => ref.read(sessionProvider)!.organizationId;
  CalendarRepository get _repo => ref.read(calendarRepositoryProvider);

  @override
  Future<List<CompanyHoliday>> build() async {
    final session = ref.watch(sessionProvider);
    if (session == null) throw const PermissionFailure();
    ref.watch(calendarRepositoryProvider);
    return (await _seeded(
      ref,
      session.organizationId,
    )).holidays(session.organizationId);
  }

  Future<void> _reload() async => state = AsyncData(await _repo.holidays(_org));

  Future<CompanyHoliday> save(CompanyHoliday h) async {
    final saved = await _repo.saveHoliday(
      _org,
      h.id.isEmpty
          ? h.copyWith(createdBy: ref.read(sessionProvider)!.displayName)
          : h,
    );
    await _reload();
    await _log(
      saved,
      h.id.isEmpty ? 'holiday.create' : 'holiday.update',
      '${saved.name} · ${_dates(saved)}${saved.optional ? ' · optional' : ''}',
    );
    if (h.id.isEmpty) {
      final people = [
        for (final e in ref.read(employeesProvider).value ?? const <Employee>[])
          if (e.status.isEmployed && saved.appliesTo(e.branchId)) e,
      ];
      await ref
          .read(notifierServiceProvider)
          .send(
            NotifyEvent.holidayAdded,
            category: NotificationCategory.system,
            title: 'New holiday added',
            short: '${saved.name} on ${_dates(saved)}.',
            employees: people,
            employeeRoute: AppRoutes.myHolidays,
            adminRoute: AppRoutes.holidayList,
          );
    }
    return saved;
  }

  static String _dates(CompanyHoliday h) {
    final f = DateFormat('EEE d MMM');
    return h.isRange
        ? '${f.format(h.date)} – ${f.format(h.endDate)}'
        : f.format(h.date);
  }

  Future<void> _log(CompanyHoliday h, String action, String summary) => ref
      .read(auditRecorderProvider)
      .record(
        action: action,
        entityType: 'Holiday',
        entityId: h.id,
        entityLabel: h.name,
        entityRoute: AppRoutes.holidayEdit(h.id),
        branchId: h.branchIds.length == 1 ? h.branchIds.single : null,
        scopeLabel: h.orgWide ? 'All branches' : '',
        summary: summary,
      );

  Future<void> delete(String id) async {
    final h = state.value?.where((x) => x.id == id).firstOrNull;
    await _repo.deleteHoliday(_org, id);
    await _reload();
    if (h != null) await _log(h, 'holiday.delete', 'Deleted ${h.name}');
  }

  Future<List<CompanyHoliday>> import(List<CompanyHoliday> rows) async {
    final by = ref.read(sessionProvider)!.displayName;
    final saved = await _repo.importHolidays(_org, [
      for (final r in rows) r.copyWith(createdBy: by),
    ]);
    await _reload();
    await ref
        .read(auditRecorderProvider)
        .record(
          action: 'holiday.import',
          entityType: 'Holiday',
          entityLabel: '${saved.length} holidays',
          source: AuditSource.import,
          summary: 'Imported ${saved.map((h) => h.name).join(', ')}',
        );
    return saved;
  }
}

/// Dated schedule assignments (board S66).
final scheduleAssignmentsProvider =
    AsyncNotifierProvider<
      ScheduleAssignmentsNotifier,
      List<ScheduleAssignment>
    >(ScheduleAssignmentsNotifier.new);

class ScheduleAssignmentsNotifier
    extends AsyncNotifier<List<ScheduleAssignment>> {
  @override
  Future<List<ScheduleAssignment>> build() async {
    final session = ref.watch(sessionProvider);
    if (session == null) throw const PermissionFailure();
    ref.watch(calendarRepositoryProvider);
    return (await _seeded(
      ref,
      session.organizationId,
    )).assignments(session.organizationId);
  }

  Future<ScheduleAssignment> add(ScheduleAssignment a) async {
    final org = ref.read(sessionProvider)!.organizationId;
    final saved = await ref
        .read(calendarRepositoryProvider)
        .addAssignment(org, a);
    state = AsyncData(
      await ref.read(calendarRepositoryProvider).assignments(org),
    );
    await ref
        .read(auditRecorderProvider)
        .record(
          action: 'schedule.assign',
          entityType: 'Schedule',
          entityId: saved.id,
          entityLabel: saved.name,
          entityRoute: AppRoutes.schedules,
          branchId: saved.branchId,
          summary:
              '${saved.level.label}: ${saved.shift ?? 'same shift'}${saved.weeklyOff == null ? '' : ' · weekly off changed'} from ${DateFormat('d MMM y').format(saved.effectiveFrom)}',
        );
    return saved;
  }
}

/// Schedules and holidays; empty while they load.
final workCalendarProvider = Provider<WorkCalendar>(
  (ref) => WorkCalendar(
    ref.watch(scheduleAssignmentsProvider).value ?? const [],
    holidays: ref.watch(companyHolidaysProvider).value ?? const [],
  ),
);
