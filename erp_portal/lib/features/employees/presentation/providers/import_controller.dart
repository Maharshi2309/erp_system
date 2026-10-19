import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/permissions/permissions.dart';
import '../../../../core/utils/image_picking.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../organization/presentation/providers/organization_providers.dart';
import '../../data/spreadsheet.dart';
import '../../domain/employee_import.dart';
import 'employee_providers.dart';

enum ImportStep {
  upload('Upload'),
  mapping('Map columns'),
  validate('Validate'),
  duplicates('Duplicates'),
  confirm('Confirm'),
  results('Results');

  const ImportStep(this.label);

  final String label;
}

/// Everything the six-step import wizard knows (boards S46–S51). Nothing is
/// saved until [ImportController.commit].
@immutable
class ImportState {
  const ImportState({
    this.step = ImportStep.upload,
    this.reading = false,
    this.table,
    this.problem,
    this.mapping = const [],
    this.chosenByYou = const {},
    this.dateOrder,
    this.rows = const [],
    this.shown = const {
      RowResult.warning,
      RowResult.duplicate,
      RowResult.invalid,
    },
    this.policy = DuplicatePolicy.reject,
    this.acknowledged = false,
    this.sendInvites = true,
    this.committing = false,
    this.record,
    this.error,
  });

  final ImportStep step;
  final bool reading;
  final ImportTable? table;
  final ImportFileProblem? problem;
  final List<ImportTarget> mapping;

  /// Columns whose target the person picked themselves.
  final Set<int> chosenByYou;
  final DateOrder? dateOrder;
  final List<ImportRow> rows;

  /// Result filters on the validation table.
  final Set<RowResult> shown;
  final DuplicatePolicy policy;
  final bool acknowledged;
  final bool sendInvites;
  final bool committing;
  final ImportRecord? record;
  final String? error;

  ImportPlan get plan => ImportPlan.from(rows, policy);

  List<ImportRow> get duplicates =>
      rows.where((r) => r.result == RowResult.duplicate).toList();

  /// Rows that won't be saved, as listed on the results page.
  List<NotImportedRow> get skippedRows => [
    for (final r in rows)
      if (r.result == RowResult.invalid)
        NotImportedRow(
          rowNumber: r.rowNumber,
          name: r.employee.fullName,
          code: r.employee.code,
          email: r.employee.workEmail,
          outcome: RowOutcome.skipped,
          reason: 'Invalid — ${r.issue}',
        )
      else if (r.result == RowResult.duplicate &&
          duplicateOutcome(r, policy) != DuplicateOutcome.willUpdate)
        NotImportedRow(
          rowNumber: r.rowNumber,
          name: r.employee.fullName,
          code: r.employee.code,
          email: r.employee.workEmail,
          outcome: RowOutcome.skipped,
          reason: duplicateOutcome(r, policy) == DuplicateOutcome.noChange
              ? 'Duplicate — identical to the existing record.'
              : 'Duplicate — rejected by policy.',
        ),
  ];

  /// Two columns mapped to the same field.
  List<ImportTarget> get doubleMapped {
    final seen = <ImportTarget>{};
    return [
      for (final t in mapping)
        if (!t.isIgnored && !seen.add(t)) t,
    ];
  }

  bool get canValidate =>
      table != null &&
      unmappedRequired(mapping).isEmpty &&
      doubleMapped.isEmpty &&
      (dateOrder != null || !needsDateOrder(table!, mapping));

  bool get needsAcknowledgement =>
      policy == DuplicatePolicy.update &&
      duplicates.any(
        (r) => duplicateOutcome(r, policy) == DuplicateOutcome.willUpdate,
      );

  ImportState copyWith({
    ImportStep? step,
    bool? reading,
    Object? table = _keep,
    Object? problem = _keep,
    List<ImportTarget>? mapping,
    Set<int>? chosenByYou,
    Object? dateOrder = _keep,
    List<ImportRow>? rows,
    Set<RowResult>? shown,
    DuplicatePolicy? policy,
    bool? acknowledged,
    bool? sendInvites,
    bool? committing,
    Object? record = _keep,
    Object? error = _keep,
  }) => ImportState(
    step: step ?? this.step,
    reading: reading ?? this.reading,
    table: identical(table, _keep) ? this.table : table as ImportTable?,
    problem: identical(problem, _keep)
        ? this.problem
        : problem as ImportFileProblem?,
    mapping: mapping ?? this.mapping,
    chosenByYou: chosenByYou ?? this.chosenByYou,
    dateOrder: identical(dateOrder, _keep)
        ? this.dateOrder
        : dateOrder as DateOrder?,
    rows: rows ?? this.rows,
    shown: shown ?? this.shown,
    policy: policy ?? this.policy,
    acknowledged: acknowledged ?? this.acknowledged,
    sendInvites: sendInvites ?? this.sendInvites,
    committing: committing ?? this.committing,
    record: identical(record, _keep) ? this.record : record as ImportRecord?,
    error: identical(error, _keep) ? this.error : error as String?,
  );
}

const _keep = Object();

final importControllerProvider =
    NotifierProvider.autoDispose<ImportController, ImportState>(
      ImportController.new,
    );

class ImportController extends Notifier<ImportState> {
  @override
  ImportState build() => const ImportState();

  void reset() => state = const ImportState();

  Future<void> pickFile() async {
    final picked = await ref.read(spreadsheetPickingProvider).pickSpreadsheet();
    if (picked == null) return;
    await loadFile(picked.name, picked.bytes);
  }

  /// Reads and checks a file (public so tests can skip the picker).
  Future<void> loadFile(String name, Uint8List bytes) async {
    state = const ImportState(reading: true);
    // Let the "Reading file…" state paint before parsing.
    await Future<void>.delayed(Duration.zero);
    try {
      final table = readSpreadsheet(name, bytes);
      final fields = await ref.read(customFieldsProvider.future);
      state = state.copyWith(
        reading: false,
        table: table,
        problem: null,
        mapping: autoMatchColumns(table.headers, fields),
      );
    } on ImportFileProblem catch (p) {
      state = state.copyWith(reading: false, problem: p, table: null);
    }
  }

  void goTo(ImportStep step) => state = state.copyWith(step: step, error: null);

  void setTarget(int column, ImportTarget target) {
    final mapping = [...state.mapping]..[column] = target;
    state = state.copyWith(
      mapping: mapping,
      chosenByYou: {...state.chosenByYou, column},
      dateOrder: needsDateOrder(state.table!, mapping) ? state.dateOrder : null,
    );
  }

  void setDateOrder(DateOrder order) =>
      state = state.copyWith(dateOrder: order);

  /// Checks every row against current data (board S48).
  Future<void> validate() async {
    final session = ref.read(sessionProvider)!;
    final employees = await ref.read(employeesProvider.future);
    final branches = await ref.read(branchesProvider.future);
    final fields = await ref.read(customFieldsProvider.future);
    final rows = classifyRows(
      state.table!,
      state.mapping,
      ImportContext(
        organizationId: session.organizationId,
        existing: employees,
        branches: [
          for (final b in branches)
            if (session.coversBranch(b.id)) b,
        ],
        fields: fields,
        dateOrder: state.dateOrder,
        sendInvites: state.sendInvites,
      ),
    );
    state = state.copyWith(
      rows: rows,
      step: ImportStep.validate,
      policy: DuplicatePolicy.reject,
      acknowledged: false,
    );
  }

  void toggleShown(RowResult r) {
    final shown = {...state.shown};
    shown.contains(r) ? shown.remove(r) : shown.add(r);
    state = state.copyWith(shown: shown);
  }

  /// "Update existing employees" needs permission to edit employees.
  bool get canUpdateExisting =>
      ref
          .read(sessionProvider)
          ?.permissions
          .can(PermissionModule.employees, PermissionAction.edit) ??
      false;

  void setPolicy(DuplicatePolicy p) {
    if (p == DuplicatePolicy.update && !canUpdateExisting) return;
    state = state.copyWith(policy: p, acknowledged: false);
  }

  void setAcknowledged(bool v) => state = state.copyWith(acknowledged: v);

  void setSendInvites(bool v) => state = state.copyWith(sendInvites: v);

  Future<void> commit() async {
    if (state.committing) return;
    if (state.needsAcknowledgement && !state.acknowledged) return;
    state = state.copyWith(committing: true, error: null);
    try {
      final record = await ref
          .read(employeesProvider.notifier)
          .commitImport(
            fileName: state.table!.fileName,
            plan: state.plan,
            skipped: state.skippedRows,
            sendInvites: state.sendInvites,
          );
      state = state.copyWith(committing: false, record: record);
    } on Object catch (e) {
      state = state.copyWith(
        committing: false,
        error: 'The import didn’t finish. Nothing was saved — try again.',
      );
      if (e is! Exception) rethrow;
    }
  }
}
