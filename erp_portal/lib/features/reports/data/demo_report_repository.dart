import 'dart:convert';
import 'dart:typed_data';

import '../domain/reports.dart';

/// DEMO ONLY — export history in memory, seeded with a few earlier runs
/// (board S75) relative to "now".
class DemoReportRepository implements ReportRepository {
  DemoReportRepository({
    this.latency = const Duration(milliseconds: 300),
    required this.now,
  });

  final Duration latency;
  final DateTime Function() now;
  final _orgs = <String, List<ExportRecord>>{};
  int _next = 1;

  Future<void> _delay() =>
      latency == Duration.zero ? Future.value() : Future.delayed(latency);

  List<ExportRecord> _org(String id) => _orgs.putIfAbsent(id, () {
    final t = now();
    ExportRecord r(
      ReportKind k,
      String filters,
      String by,
      String byId,
      int daysAgo, {
      bool failed = false,
      String format = 'XLSX',
      String? branchId,
    }) => ExportRecord(
      id: 'exp-${_next++}',
      kind: k,
      filters: filters,
      requestedBy: by,
      requestedById: byId,
      at: DateTime(t.year, t.month, t.day - daysAgo, 10, 12),
      format: format,
      failed: failed,
      branchId: branchId,
      bytes: failed
          ? null
          : Uint8List.fromList(utf8.encode('Demo export: ${k.label}\n')),
    );
    return [
      r(
        ReportKind.monthly,
        'Last month · All branches',
        'Hetal Shah',
        'u-hetal',
        12,
      ),
      r(
        ReportKind.missing,
        'This month · Surat',
        'Mitesh Rana',
        'u-mitesh',
        1,
        format: 'CSV',
        branchId: 'b-sur',
      ),
      r(
        ReportKind.roster,
        'Active · All branches',
        'Ankit Patel',
        'u-ankit',
        14,
        failed: true,
      ),
      r(
        ReportKind.requests,
        'Last quarter · All branches',
        'Hetal Shah',
        'u-hetal',
        30,
      ),
    ];
  });

  @override
  Future<List<ExportRecord>> exports(String organizationId) async {
    await _delay();
    final list = [..._org(organizationId)]
      ..sort((a, b) => b.at.compareTo(a.at));
    return List.unmodifiable(list);
  }

  @override
  Future<ExportRecord> add(String organizationId, ExportRecord record) async {
    await _delay();
    final saved = ExportRecord(
      id: 'exp-${_next++}',
      kind: record.kind,
      filters: record.filters,
      requestedBy: record.requestedBy,
      requestedById: record.requestedById,
      at: record.at,
      format: record.format,
      failed: record.failed,
      bytes: record.bytes,
      branchId: record.branchId,
    );
    _org(organizationId).add(saved);
    return saved;
  }
}
