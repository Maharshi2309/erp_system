import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/config/app_config.dart';
import '../../../core/errors/failure.dart';
import '../../../core/utils/file_download.dart';
import '../../attendance/presentation/attendance_providers.dart';
import '../../audit/domain/audit.dart';
import '../../audit/presentation/audit_providers.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../employees/data/spreadsheet.dart';
import '../../employees/domain/employee.dart';
import '../../employees/presentation/providers/employee_providers.dart';
import '../../holidays/presentation/calendar_providers.dart';
import '../../leave/presentation/leave_providers.dart';
import '../../organization/presentation/providers/organization_providers.dart';
import '../../settings/domain/settings.dart';
import '../../settings/presentation/settings_providers.dart';
import '../data/demo_report_repository.dart';
import '../domain/reports.dart';

final reportRepositoryProvider = Provider<ReportRepository>(
  (ref) => DemoReportRepository(
    latency: ref.watch(demoLatencyProvider),
    now: () => ref.read(orgNowProvider)(),
  ),
);

/// Every export the member may see: their own, or within their branches
/// for branch-scoped roles (board S75 "Anyone you can see").
final exportHistoryProvider = FutureProvider<List<ExportRecord>>((ref) async {
  final s = ref.watch(sessionProvider);
  if (s == null) throw const PermissionFailure();
  final all = await ref
      .watch(reportRepositoryProvider)
      .exports(s.organizationId);
  return [
    for (final r in all)
      if (s.branchIds.isEmpty
          ? true
          : (r.requestedById == s.userId ||
                (r.branchId != null && s.branchIds.contains(r.branchId))))
        r,
  ];
});

/// The data reports read, limited to the people the member may see.
final reportSourcesProvider = Provider<ReportSources?>((ref) {
  final s = ref.watch(sessionProvider);
  final visible = ref.watch(visibleEmployeesProvider).value;
  final branches = ref.watch(branchesProvider).value;
  final settings = ref.watch(orgSettingsProvider).value;
  if (s == null || visible == null || branches == null || settings == null) {
    return null;
  }
  return (
    people: [
      for (final e in visible)
        if (e.status != EmploymentStatus.terminated) e,
    ],
    branches: [
      for (final b in branches)
        if (s.coversBranch(b.id)) b,
    ],
    attendance: ref.watch(attendanceBookProvider).value,
    leave: ref.watch(leaveBookProvider).value,
    audit: ref.watch(auditEventsProvider).value ?? const <AuditEvent>[],
    holidays: ref.watch(companyHolidaysProvider).value ?? const [],
    format: settings.data,
  );
});

/// File bytes for a table in the organization's export format.
Uint8List reportBytes(
  ReportTable t,
  String title, {
  required bool csv,
  required DataSettings format,
}) {
  final rows = [t.headers, ...t.rows];
  if (!csv) {
    return buildXlsx(title.length > 30 ? title.substring(0, 30) : title, rows);
  }
  String cell(String v) =>
      v.contains(format.csvSeparator) || v.contains('"') || v.contains('\n')
      ? '"${v.replaceAll('"', '""')}"'
      : v;
  final text = rows
      .map((r) => r.map(cell).join(format.csvSeparator))
      .join('\r\n');
  return Uint8List.fromList(utf8.encode('﻿$text'));
}

final reportServiceProvider = Provider<ReportService>(ReportService.new);

class ReportService {
  ReportService(this.ref);

  final Ref ref;

  /// Builds, saves to the history, downloads and logs an export. Refused
  /// when the role may not export this report (board S84).
  Future<ExportRecord> export(ReportFilter f, {required bool csv}) async {
    final session = ref.read(sessionProvider);
    final sources = ref.read(reportSourcesProvider);
    if (session == null || sources == null) throw const UnexpectedFailure();
    final block = reportBlock(f.kind, session, sources.format, export: true);
    if (block != null) throw PermissionFailure(block);
    final table = buildReport(f, sources, session);
    final bytes = reportBytes(
      table,
      f.kind.label,
      csv: csv,
      format: sources.format,
    );
    final filters = f.describe(sources.branches);
    final saved = await ref
        .read(reportRepositoryProvider)
        .add(
          session.organizationId,
          ExportRecord(
            id: '',
            kind: f.kind,
            filters: filters,
            requestedBy: session.displayName,
            requestedById: session.userId,
            at: ref.read(orgNowProvider)(),
            format: csv ? 'CSV' : 'XLSX',
            bytes: bytes,
            branchId: f.branchId,
          ),
        );
    try {
      await download(saved, log: false);
    } on Object {
      throw const UnexpectedFailure(
        'The export is ready in Export history, but the file couldn’t be saved here. Try Download there.',
      );
    }
    await ref
        .read(auditRecorderProvider)
        .record(
          action: 'report.export',
          entityType: 'Report',
          entityId: saved.id,
          entityLabel: f.kind.label,
          entityRoute: '/reports/exports',
          branchId: f.branchId,
          summary:
              '${f.kind.label} · $filters · ${table.rows.length} rows · ${saved.format}',
        );
    ref.invalidate(exportHistoryProvider);
    return saved;
  }

  /// Saves the file again; every completed download is logged (board
  /// S75). False when cancelled; throws when the file can't be written.
  Future<bool> download(ExportRecord r, {bool log = true}) async {
    final bytes = r.bytes;
    if (bytes == null) return false;
    final name =
        '${r.kind.name}_${r.at.year}${r.at.month.toString().padLeft(2, '0')}${r.at.day.toString().padLeft(2, '0')}.${r.format.toLowerCase()}';
    final saved = await ref
        .read(fileDownloadsProvider)
        .save(
          name,
          bytes,
          mimeType: r.format == 'CSV' ? csvMimeType : xlsxMimeType,
        );
    if (!saved) return false;
    if (log) {
      await ref
          .read(auditRecorderProvider)
          .record(
            action: 'report.download',
            entityType: 'Report',
            entityId: r.id,
            entityLabel: r.kind.label,
            branchId: r.branchId,
            summary: 'Downloaded ${r.kind.label} (${r.filters})',
          );
    }
    return true;
  }
}
