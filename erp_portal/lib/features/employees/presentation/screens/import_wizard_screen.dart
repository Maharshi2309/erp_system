import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/file_download.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_overlays.dart';
import '../../../../core/widgets/selection_controls.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../auth/presentation/widgets/auth_layout.dart';
import '../../../auth/presentation/widgets/auth_widgets.dart';
import '../../../organization/domain/branch.dart';
import '../../../organization/presentation/providers/organization_providers.dart';
import '../../data/employee_files.dart';
import '../../data/spreadsheet.dart';
import '../../domain/custom_field.dart';
import '../../domain/employee_import.dart';
import '../providers/employee_providers.dart';
import '../providers/import_controller.dart';

final _when = DateFormat('d MMM HH:mm');
final _whenYear = DateFormat('d MMM y');

String _recordTime(DateTime at, DateTime now) =>
    at.year == now.year ? _when.format(at) : _whenYear.format(at);

/// Boards S46–S51 — upload, map, validate, duplicates, confirm, results.
class ImportWizardScreen extends ConsumerWidget {
  const ImportWizardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(importControllerProvider);
    final record = state.record;
    final step = record != null ? ImportStep.results : state.step;
    final table = state.table;

    Future<void> close() async {
      final started = table != null && record == null;
      if (started) {
        final leave = await showConfirmDialog(
          context,
          title: 'Leave the import?',
          message:
              'Nothing has been saved. You’ll need to upload the file again.',
          confirmLabel: 'Leave',
          destructive: true,
        );
        if (!leave) return;
      }
      if (context.mounted) context.go(AppRoutes.employees);
    }

    return _WizardFrame(
      step: step,
      subtitle: table == null
          ? null
          : (record == null
                ? '${table.fileName} · ${table.rows.length} rows'
                : '${table.fileName} · finished ${_when.format(record.finishedAt)}'),
      onClose: close,
      child: switch (step) {
        ImportStep.upload => const _UploadStep(),
        ImportStep.mapping => const _MappingStep(),
        ImportStep.validate => const _ValidateStep(),
        ImportStep.duplicates => const _DuplicatesStep(),
        ImportStep.confirm => const _ConfirmStep(),
        ImportStep.results => ImportResultsView(
          record: record!,
          onImportFixed: () =>
              ref.read(importControllerProvider.notifier).reset(),
        ),
      },
    );
  }
}

/// A past import's results (from "Recent imports" → View).
class ImportResultScreen extends ConsumerWidget {
  const ImportResultScreen({super.key, required this.recordId});

  final String recordId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imports = ref.watch(importsProvider);
    final record = imports.value?.where((r) => r.id == recordId).firstOrNull;
    return _WizardFrame(
      step: ImportStep.results,
      subtitle: record == null
          ? null
          : '${record.fileName} · finished ${_recordTime(record.finishedAt, DateTime.now())}',
      onClose: () => context.go(AppRoutes.employees),
      child: imports.isLoading
          ? const LoadingSkeleton(
              label: 'Loading import',
              child: SkeletonList(rows: 4),
            )
          : record == null
          ? ErrorState(
              headline: '404',
              title: 'This import isn’t here',
              message: 'It may belong to another organization.',
              actions: [
                AppButton(
                  label: 'Go to employees',
                  onPressed: () => context.go(AppRoutes.employees),
                ),
              ],
            )
          : ImportResultsView(
              record: record,
              onImportFixed: () => context.go(AppRoutes.employeeImport),
            ),
    );
  }
}

class _WizardFrame extends StatelessWidget {
  const _WizardFrame({
    required this.step,
    required this.onClose,
    required this.child,
    this.subtitle,
  });

  final ImportStep step;
  final String? subtitle;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final phone = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Close import',
                        onPressed: onClose,
                        icon: const Icon(Icons.close),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Import employees',
                              style: AppTypography.cardTitle,
                            ),
                            if (subtitle != null)
                              Text(
                                subtitle!,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.helper,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _Stepper(current: step, compact: phone),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(phone ? AppSpacing.lg : AppSpacing.xl),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: child,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.current, required this.compact});

  final ImportStep current;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Text(
        'Step ${current.index + 1} of ${ImportStep.values.length} · ${current.label}',
        style: AppTypography.small.copyWith(color: AppColors.textPrimary),
      );
    }
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: [
        for (final s in ImportStep.values)
          Semantics(
            label:
                '${s.label}, step ${s.index + 1} of ${ImportStep.values.length}'
                '${s == current ? ', current' : (s.index < current.index ? ', done' : '')}',
            excludeSemantics: true,
            child: Container(
              padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
              decoration: BoxDecoration(
                color: s == current
                    ? AppColors.primarySoft
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: s == current
                          ? AppColors.primary
                          : (s.index < current.index
                                ? AppColors.successSoft
                                : AppColors.neutralSoft),
                    ),
                    child: Text(
                      s.index < current.index ? '✓' : '${s.index + 1}',
                      style: AppTypography.helper.copyWith(
                        fontSize: 11,
                        color: s == current
                            ? AppColors.surface
                            : (s.index < current.index
                                  ? AppColors.success
                                  : AppColors.textSecondary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    s.label,
                    style: AppTypography.small.copyWith(
                      color: s == current
                          ? AppColors.primaryHover
                          : AppColors.textSecondary,
                      fontWeight: s == current
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _StepHeading extends StatelessWidget {
  const _StepHeading(this.title, this.lead);

  final String title;
  final String lead;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(
        header: true,
        child: Text(title, style: AppTypography.pageTitle),
      ),
      const SizedBox(height: 4),
      Text(lead, style: AppTypography.bodySecondary),
      const SizedBox(height: AppSpacing.lg),
    ],
  );
}

class _Footer extends StatelessWidget {
  const _Footer({required this.children, this.note});

  final List<Widget> children;
  final String? note;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.xl),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: [
        children.first,
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (note != null) Text(note!, style: AppTypography.helper),
            ...children.skip(1),
          ],
        ),
      ],
    ),
  );
}

// ---------------- Step 1: upload ----------------

class _UploadStep extends ConsumerWidget {
  const _UploadStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(importControllerProvider);
    final controller = ref.read(importControllerProvider.notifier);
    final table = state.table;
    final problem = state.problem;

    void template() {
      final fields =
          ref.read(customFieldsProvider).value ?? const <CustomField>[];
      ref
          .read(fileDownloadsProvider)
          .save(
            'staffline_employee_template.xlsx',
            buildXlsx('Employees', templateRows(fields)),
            mimeType: xlsxMimeType,
          );
      showAppToast(context, 'Template downloaded');
    }

    final Widget zone;
    if (state.reading) {
      zone = const Column(
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          SizedBox(height: AppSpacing.md),
          Text('Reading file…', style: AppTypography.body),
        ],
      );
    } else if (problem != null) {
      zone = Column(
        children: [
          const Icon(Icons.error_outline, size: 32, color: AppColors.danger),
          const SizedBox(height: AppSpacing.sm),
          Text(
            problem.title,
            textAlign: TextAlign.center,
            style: AppTypography.cardTitle,
          ),
          const SizedBox(height: 4),
          Text(
            problem.detail,
            textAlign: TextAlign.center,
            style: AppTypography.small,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: 'Choose a different file',
            onPressed: controller.pickFile,
          ),
        ],
      );
    } else if (table != null) {
      final kb = (table.sizeBytes / 1024).ceil();
      zone = Column(
        children: [
          const Icon(
            Icons.description_outlined,
            size: 32,
            color: AppColors.success,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            table.fileName,
            style: AppTypography.cardTitle,
            textAlign: TextAlign.center,
          ),
          Text(
            [
              if (table.sheetName.isNotEmpty) 'Sheet “${table.sheetName}”',
              '${table.rows.length} rows',
              '${table.headers.length} columns',
              '$kb KB',
            ].join(' · '),
            textAlign: TextAlign.center,
            style: AppTypography.small,
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            alignment: WrapAlignment.center,
            children: [
              AppButton(
                label: 'Choose another',
                variant: AppButtonVariant.secondary,
                onPressed: controller.pickFile,
              ),
              AppButton(
                label: 'Continue to mapping',
                onPressed: () => controller.goTo(ImportStep.mapping),
              ),
            ],
          ),
        ],
      );
    } else {
      zone = Column(
        children: [
          const Icon(
            Icons.upload_file_outlined,
            size: 32,
            color: AppColors.primary,
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text('Choose a spreadsheet', style: AppTypography.cardTitle),
          const SizedBox(height: 4),
          const Text(
            '.xlsx or .csv · up to 5 MB · up to 2,000 rows · first row must be headers',
            textAlign: TextAlign.center,
            style: AppTypography.small,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(label: 'Choose file', onPressed: controller.pickFile),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          children: [
            const _StepHeading(
              'Upload a spreadsheet',
              'Nothing is saved until you confirm on the last step.',
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: TextLink('Download template', onTap: template),
            ),
          ],
        ),
        Semantics(
          liveRegion: true,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.xxl,
            ),
            decoration: BoxDecoration(
              color: problem != null ? AppColors.dangerSoft : AppColors.surface,
              border: Border.all(
                color: problem != null
                    ? AppColors.dangerBorder
                    : AppColors.borderStrong,
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: zone,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        const _RecentImports(),
      ],
    );
  }
}

class _RecentImports extends ConsumerWidget {
  const _RecentImports();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imports = ref.watch(importsProvider).value ?? const <ImportRecord>[];
    final now = DateTime.now();
    return AppCard(
      header: const CardHeader(title: 'Recent imports'),
      padding: EdgeInsets.zero,
      child: imports.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Text('No imports yet.', style: AppTypography.small),
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('FILE')),
                  DataColumn(label: Text('BY')),
                  DataColumn(label: Text('RESULT')),
                  DataColumn(label: Text('REPORT')),
                ],
                rows: [
                  for (final r in imports.take(5))
                    DataRow(
                      cells: [
                        DataCell(
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.fileName, style: AppTypography.bodyStrong),
                              Text(
                                _recordTime(r.finishedAt, now),
                                style: AppTypography.helper,
                              ),
                            ],
                          ),
                        ),
                        DataCell(Text(r.by)),
                        DataCell(
                          Text(
                            r.summary,
                            style: AppTypography.small.copyWith(
                              color: r.failed > 0
                                  ? AppColors.warningText
                                  : AppColors.successText,
                            ),
                          ),
                        ),
                        DataCell(
                          TextLink(
                            'View',
                            onTap: () =>
                                context.go(AppRoutes.importResult(r.id)),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
    );
  }
}

// ---------------- Step 2: mapping ----------------

class _MappingStep extends ConsumerWidget {
  const _MappingStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(importControllerProvider);
    final controller = ref.read(importControllerProvider.notifier);
    final table = state.table!;
    final fields =
        (ref.watch(customFieldsProvider).value ?? const <CustomField>[])
            .where((f) => !f.archived)
            .toList();
    final matched = state.mapping.where((t) => !t.isIgnored).length;
    final missing = unmappedRequired(state.mapping);
    final needsOrder = needsDateOrder(table, state.mapping);
    final doubled = state.doubleMapped;

    String label(ImportTarget t) =>
        t.field?.label ??
        (t.customKey != null
            ? '${fields.where((f) => f.key == t.customKey).firstOrNull?.label ?? t.customKey} (custom)'
            : 'Don’t import');

    final targets = <ImportTarget>[
      for (final f in ImportField.values) ImportTarget.field(f),
      for (final f in fields) ImportTarget.custom(f.key),
      const ImportTarget.ignore(),
    ];

    (String, String, Color) check(int c) {
      final t = state.mapping[c];
      if (t.isIgnored) return ('–', 'Won’t import', AppColors.textMuted);
      if (doubled.contains(t)) return ('!', 'Used twice', AppColors.danger);
      final isDate = t.field == ImportField.joiningDate;
      if (isDate &&
          table.rows.any((r) => isAmbiguousDate(r[c])) &&
          state.dateOrder == null) {
        return ('!', 'Check format', const Color(0xFF8A4F00));
      }
      if (state.chosenByYou.contains(c)) {
        return ('✓', 'Chosen by you', AppColors.primary);
      }
      if (t.customKey != null) return ('✓', 'Custom field', AppColors.primary);
      return ('✓', 'Matched', AppColors.success);
    }

    final mappingTable = AppCard(
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 680),
          child: DataTable(
            columns: const [
              DataColumn(label: Text('YOUR COLUMN')),
              DataColumn(label: Text('SAMPLE VALUES')),
              DataColumn(label: Text('IMPORT INTO')),
              DataColumn(label: Text('CHECK')),
            ],
            rows: [
              for (var c = 0; c < table.headers.length; c++)
                DataRow(
                  color: WidgetStatePropertyAll(
                    check(c).$2 == 'Check format'
                        ? const Color(0xFFFFFBF2)
                        : null,
                  ),
                  cells: [
                    DataCell(
                      Text(table.headers[c], style: AppTypography.bodyStrong),
                    ),
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: Text(
                          table.samples(c),
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.small,
                        ),
                      ),
                    ),
                    DataCell(
                      SizedBox(
                        width: 240,
                        child: Semantics(
                          label: 'Target for ${table.headers[c]}',
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<ImportTarget>(
                              value: state.mapping[c],
                              isExpanded: true,
                              style: AppTypography.small.copyWith(
                                color: AppColors.textPrimary,
                              ),
                              items: [
                                for (final t in targets)
                                  DropdownMenuItem(
                                    value: t,
                                    child: Text(
                                      label(t),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: (t) {
                                if (t != null) controller.setTarget(c, t);
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        '${check(c).$1} ${check(c).$2}',
                        style: AppTypography.small.copyWith(
                          color: check(c).$3,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );

    final side = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          header: const CardHeader(title: 'Required fields'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final f in ImportField.values.where((f) => f.required))
                () {
                  final c = state.mapping.indexOf(ImportTarget.field(f));
                  final ok = c >= 0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Icon(
                          ok ? Icons.check_circle_outline : Icons.error_outline,
                          size: 16,
                          color: ok ? AppColors.success : AppColors.danger,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            f.label,
                            style: AppTypography.small.copyWith(
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          ok ? table.headers[c] : 'Not mapped',
                          style: AppTypography.helper,
                        ),
                      ],
                    ),
                  );
                }(),
            ],
          ),
        ),
        if (needsOrder) ...[
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            header: const CardHeader(title: 'Date format'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${table.headers[state.mapping.indexOf(const ImportTarget.field(ImportField.joiningDate)).clamp(0, table.headers.length - 1)]} '
                  'has values like ${_firstAmbiguous(table, state.mapping) ?? '03/10/2026'} that could be read two ways. '
                  'Which is it?',
                  style: AppTypography.small,
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final order in DateOrder.values)
                  OptionCard(
                    title: order.label,
                    description: _example(
                      _firstAmbiguous(table, state.mapping) ?? '03/10/2026',
                      order,
                    ),
                    selected: state.dateOrder == order,
                    onTap: () => controller.setDateOrder(order),
                  ),
              ],
            ),
          ),
        ],
      ],
    );

    final blockers = [
      for (final f in missing) '${f.label} isn’t mapped.',
      for (final t in doubled) '${label(t)} is chosen for two columns.',
      if (needsOrder && state.dateOrder == null) 'Choose the date format.',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StepHeading(
          'Match your columns',
          'We matched $matched of ${table.headers.length} columns by name. Check them, then choose what to do with the rest.',
        ),
        LayoutBuilder(
          builder: (context, c) => c.maxWidth < 900
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    mappingTable,
                    const SizedBox(height: AppSpacing.lg),
                    side,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: mappingTable),
                    const SizedBox(width: AppSpacing.lg),
                    SizedBox(width: 340, child: side),
                  ],
                ),
        ),
        _Footer(
          note: blockers.isEmpty ? null : blockers.first,
          children: [
            AppButton(
              label: 'Back',
              variant: AppButtonVariant.secondary,
              onPressed: () => controller.goTo(ImportStep.upload),
            ),
            AppButton(
              label: 'Validate ${table.rows.length} rows',
              onPressed: state.canValidate ? controller.validate : null,
            ),
          ],
        ),
      ],
    );
  }

  static String? _firstAmbiguous(
    ImportTable table,
    List<ImportTarget> mapping,
  ) {
    final c = mapping.indexOf(
      const ImportTarget.field(ImportField.joiningDate),
    );
    if (c < 0) return null;
    return table.rows.map((r) => r[c]).where(isAmbiguousDate).firstOrNull;
  }

  static String _example(String text, DateOrder order) {
    final d = parseImportDate(text, order);
    return d == null ? '' : '$text → ${DateFormat('d MMM y').format(d)}';
  }
}

// ---------------- Step 3: validate ----------------

(Color, Color, String) _resultStyle(RowResult r) => switch (r) {
  RowResult.ready => (AppColors.successSoft, AppColors.success, '✓'),
  RowResult.warning => (AppColors.warningSoft, AppColors.warning, '!'),
  RowResult.duplicate => (AppColors.primarySoft, AppColors.primary, '='),
  RowResult.invalid => (AppColors.dangerSoft, AppColors.danger, '×'),
};

class _ValidateStep extends ConsumerWidget {
  const _ValidateStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(importControllerProvider);
    final controller = ref.read(importControllerProvider.notifier);
    final rows = state.rows;
    final branches = ref.watch(branchesProvider).value ?? const <Branch>[];
    int count(RowResult r) => rows.where((x) => x.result == r).length;
    final problems = rows.where((r) => r.result != RowResult.ready).toList();
    final shown = problems
        .where((r) => state.shown.contains(r.result))
        .toList();
    final dupes = count(RowResult.duplicate);

    void report() {
      ref
          .read(fileDownloadsProvider)
          .save(
            'import_errors_${state.table!.fileName.split('.').first}.xlsx',
            buildXlsx('Rows with problems', errorReportRows(rows)),
            mimeType: xlsxMimeType,
          );
      showAppToast(context, 'Error report downloaded');
    }

    Widget counter(String label, int value, RowResult? result) {
      final (bg, fg, icon) = result == null
          ? (AppColors.neutralSoft, AppColors.textSecondary, '#')
          : _resultStyle(result);
      final on = result != null && state.shown.contains(result);
      final toggle = result != null && result != RowResult.ready;
      return Semantics(
        button: toggle,
        toggled: toggle ? on : null,
        label: '$label $value',
        excludeSemantics: true,
        child: InkWell(
          onTap: toggle ? () => controller.toggleShown(result) : null,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Container(
            width: 168,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(
                color: on ? AppColors.primary : AppColors.border,
                width: on ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                  child: Text(
                    icon,
                    style: AppTypography.label.copyWith(color: fg),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: AppTypography.helper),
                      Text('$value', style: AppTypography.metric),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StepHeading(
          'Review rows before importing',
          'Nothing has been saved yet. Fix the file and re-upload, or continue — invalid rows will be skipped and listed in the error report.',
        ),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            counter('Total rows', rows.length, null),
            counter('Ready to create', count(RowResult.ready), RowResult.ready),
            counter('Warnings', count(RowResult.warning), RowResult.warning),
            counter('Duplicates', dupes, RowResult.duplicate),
            counter('Invalid', count(RowResult.invalid), RowResult.invalid),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        AppCard(
          header: CardHeader(
            title: 'Rows with problems · ${problems.length}',
            trailing: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                AppButton(
                  label: 'Download error report',
                  size: AppButtonSize.small,
                  variant: AppButtonVariant.secondary,
                  onPressed: problems.isEmpty ? null : report,
                ),
                AppButton(
                  label: 'Re-upload file',
                  size: AppButtonSize.small,
                  variant: AppButtonVariant.secondary,
                  onPressed: () {
                    controller.reset();
                    controller.pickFile();
                  },
                ),
              ],
            ),
          ),
          padding: EdgeInsets.zero,
          child: problems.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Text(
                    'Every row passed. Nothing to fix.',
                    style: AppTypography.small,
                  ),
                )
              : shown.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Text(
                    'Turn on a filter above to see rows.',
                    style: AppTypography.small,
                  ),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    dataRowMaxHeight: double.infinity,
                    columns: const [
                      DataColumn(label: Text('ROW'), numeric: true),
                      DataColumn(label: Text('EMPLOYEE ID')),
                      DataColumn(label: Text('NAME')),
                      DataColumn(label: Text('EMAIL')),
                      DataColumn(label: Text('BRANCH')),
                      DataColumn(label: Text('JOINING DATE')),
                      DataColumn(label: Text('RESULT')),
                      DataColumn(label: Text('WHAT TO FIX')),
                    ],
                    rows: [
                      for (final r in shown)
                        DataRow(
                          cells: [
                            DataCell(
                              Text('${r.rowNumber}', style: AppTypography.code),
                            ),
                            DataCell(
                              Text(
                                r.employee.code.isEmpty ? '—' : r.employee.code,
                                style: AppTypography.code,
                              ),
                            ),
                            DataCell(
                              Text(
                                r.employee.fullName.isEmpty
                                    ? '—'
                                    : r.employee.fullName,
                              ),
                            ),
                            DataCell(
                              Text(
                                r.employee.workEmail.isEmpty
                                    ? '—'
                                    : r.employee.workEmail,
                              ),
                            ),
                            DataCell(
                              Text(
                                branches
                                        .where(
                                          (b) => b.id == r.employee.branchId,
                                        )
                                        .firstOrNull
                                        ?.name ??
                                    '—',
                              ),
                            ),
                            DataCell(
                              Text(
                                r.employee.joiningDate.year == 1970
                                    ? '—'
                                    : DateFormat(
                                        'd MMM y',
                                      ).format(r.employee.joiningDate),
                                style: AppTypography.code,
                              ),
                            ),
                            DataCell(
                              StatusBadge(
                                label: r.result.label,
                                tone: switch (r.result) {
                                  RowResult.invalid => StatusTone.danger,
                                  RowResult.duplicate => StatusTone.info,
                                  RowResult.warning => StatusTone.warning,
                                  RowResult.ready => StatusTone.success,
                                },
                              ),
                            ),
                            DataCell(
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 360,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  child: Text(
                                    r.issue,
                                    style: AppTypography.small,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
        ),
        _Footer(
          note: dupes > 0
              ? 'Duplicates are rejected unless you choose otherwise.'
              : null,
          children: [
            AppButton(
              label: 'Back to mapping',
              variant: AppButtonVariant.secondary,
              onPressed: () => controller.goTo(ImportStep.mapping),
            ),
            AppButton(
              label: dupes > 0
                  ? 'Resolve $dupes ${dupes == 1 ? 'duplicate' : 'duplicates'}'
                  : 'Continue to summary',
              onPressed: () => controller.goTo(
                dupes > 0 ? ImportStep.duplicates : ImportStep.confirm,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------- Step 4: duplicates ----------------

class _DuplicatesStep extends ConsumerWidget {
  const _DuplicatesStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(importControllerProvider);
    final controller = ref.read(importControllerProvider.notifier);
    final dupes = state.duplicates;
    final org =
        ref.watch(sessionProvider)?.organizationName ?? 'your organization';
    final canUpdate = controller.canUpdateExisting;
    final differing = dupes.where((r) => r.changes.isNotEmpty).length;
    final updates = dupes
        .where(
          (r) =>
              duplicateOutcome(r, state.policy) == DuplicateOutcome.willUpdate,
        )
        .toList();

    String describe(DuplicatePolicy p) => switch (p) {
      DuplicatePolicy.reject =>
        'Skip these rows. Existing employees stay exactly as they are.',
      DuplicatePolicy.update =>
        canUpdate
            ? 'Overwrite changed fields with values from your file. Needs “Edit employees” permission.'
            : 'Needs “Edit employees” permission, which your role doesn’t have.',
      DuplicatePolicy.skipSame =>
        differing == 0
            ? 'Skip rows that match exactly. All ${dupes.length} rows here are identical.'
            : 'Same as reject here — $differing ${differing == 1 ? 'row has' : 'rows have'} differences.',
    };

    final ack = state.needsAcknowledgement;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StepHeading(
          '${dupes.length} ${dupes.length == 1 ? 'row matches an existing employee' : 'rows match existing employees'}',
          'They have the same employee ID as someone already in $org. Choose what happens to them.',
        ),
        const Text('Duplicate policy', style: AppTypography.label),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final p in DuplicatePolicy.values)
              SizedBox(
                width: 340,
                child: Opacity(
                  opacity: p == DuplicatePolicy.update && !canUpdate ? 0.6 : 1,
                  child: OptionCard(
                    title: p == DuplicatePolicy.reject
                        ? '${p.label} (default)'
                        : p.label,
                    description: describe(p),
                    selected: state.policy == p,
                    onTap: () => controller.setPolicy(p),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        AppCard(
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              dataRowMaxHeight: double.infinity,
              columns: const [
                DataColumn(label: Text('ROW · ID')),
                DataColumn(label: Text('FIELD')),
                DataColumn(label: Text('IN SYSTEM NOW')),
                DataColumn(label: Text('IN YOUR FILE')),
                DataColumn(label: Text('WILL HAPPEN')),
              ],
              rows: [
                for (final r in dupes)
                  DataRow(
                    cells: [
                      DataCell(
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.existing!.fullName,
                              style: AppTypography.bodyStrong,
                            ),
                            Text(
                              'row ${r.rowNumber} · ${r.existing!.code}',
                              style: AppTypography.helper,
                            ),
                          ],
                        ),
                      ),
                      DataCell(
                        Text(
                          r.changes.isEmpty
                              ? 'All fields'
                              : r.changes.map((c) => c.field).join('\n'),
                        ),
                      ),
                      DataCell(
                        Text(
                          r.changes.isEmpty
                              ? 'Same'
                              : r.changes.map((c) => c.now).join('\n'),
                        ),
                      ),
                      DataCell(
                        Text(
                          r.changes.isEmpty
                              ? 'Same'
                              : r.changes.map((c) => c.incoming).join('\n'),
                          style: r.changes.isEmpty
                              ? null
                              : AppTypography.body.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF8A4F00),
                                ),
                        ),
                      ),
                      DataCell(
                        StatusBadge(
                          label: duplicateOutcome(r, state.policy).label,
                          tone:
                              duplicateOutcome(r, state.policy) ==
                                  DuplicateOutcome.willUpdate
                              ? StatusTone.warning
                              : StatusTone.neutral,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        if (ack) ...[
          const SizedBox(height: AppSpacing.lg),
          LabeledCheckbox(
            value: state.acknowledged,
            onChanged: controller.setAcknowledged,
            label: Text(
              'I understand ${updates.length} existing employee ${updates.length == 1 ? 'record' : 'records'} '
              'will be overwritten (${updates.map((r) => '${r.existing!.fullName}’s ${r.changes.map((c) => c.field.toLowerCase()).join(', ')}').join('; ')}). '
              'The previous values are kept in the history.',
              style: AppTypography.small.copyWith(color: AppColors.textPrimary),
            ),
          ),
        ],
        _Footer(
          note: ack && !state.acknowledged
              ? 'Tick the confirmation to continue'
              : null,
          children: [
            AppButton(
              label: 'Back to validation',
              variant: AppButtonVariant.secondary,
              onPressed: () => controller.goTo(ImportStep.validate),
            ),
            AppButton(
              label: 'Continue to summary',
              onPressed: ack && !state.acknowledged
                  ? null
                  : () => controller.goTo(ImportStep.confirm),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------- Step 5: confirm ----------------

class _ConfirmStep extends ConsumerWidget {
  const _ConfirmStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(importControllerProvider);
    final controller = ref.read(importControllerProvider.notifier);
    final plan = state.plan;
    final creates = plan.toCreate.length;
    final updates = plan.toUpdate.length;
    final invites = plan.toCreate
        .where((r) => r.employee.workEmail.isNotEmpty)
        .length;
    final total = creates + updates;
    final hadDuplicates = plan.duplicates > 0;

    Widget line(
      String k,
      String sub,
      int v, {
      Color? color,
      bool strong = false,
    }) => Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: strong ? AppColors.primarySelected : AppColors.surface,
        border: const Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  k,
                  style: strong ? AppTypography.bodyStrong : AppTypography.body,
                ),
                Text(sub, style: AppTypography.helper),
              ],
            ),
          ),
          Text(
            '$v',
            style: AppTypography.code.copyWith(
              fontSize: strong ? 22 : 16,
              color: color ?? AppColors.textPrimary,
              fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StepHeading(
          'Ready to import',
          'Review what will happen. Employees are only created after you confirm.',
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    line(
                      'Total rows in file',
                      state.table!.fileName,
                      plan.total,
                    ),
                    line(
                      'Valid rows',
                      'Passed every check',
                      plan.ready,
                      color: AppColors.success,
                    ),
                    line(
                      'Rows with warnings',
                      'Accepted — branch, manager or date assumptions',
                      plan.warnings,
                      color: AppColors.warning,
                    ),
                    line(
                      'Invalid rows',
                      'Skipped — listed in the error report',
                      plan.invalid,
                      color: AppColors.danger,
                    ),
                    line(
                      'Duplicates',
                      state.policy == DuplicatePolicy.update
                          ? '$updates will update existing employees'
                          : 'Rejected by policy',
                      plan.duplicates,
                      color: AppColors.textSecondary,
                    ),
                    line(
                      'Employees to create',
                      '$updates will be updated',
                      creates,
                      strong: true,
                    ),
                  ],
                ),
              ),
              if (hadDuplicates) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Duplicate policy · ${state.policy.label}',
                  style: AppTypography.small,
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              SwitchRow(
                label: 'Send sign-in invitations',
                value: state.sendInvites,
                description: state.sendInvites
                    ? '$invites ${invites == 1 ? 'email goes' : 'emails go'} out once the import finishes. Invitations expire in 7 days.'
                    : 'Accounts are created without access. You can invite people later from the directory.',
                onChanged: state.committing || state.record != null
                    ? null
                    : controller.setSendInvites,
              ),
              const SizedBox(height: AppSpacing.lg),
              if (state.committing)
                Semantics(
                  liveRegion: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Importing $total employees… keep this tab open',
                        style: AppTypography.bodyStrong,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      const LinearProgressIndicator(minHeight: 6),
                      const SizedBox(height: AppSpacing.sm),
                      const Text(
                        'Rows are saved one at a time. If anything fails, that row is listed on the next screen — nothing is half-written.',
                        style: AppTypography.helper,
                      ),
                    ],
                  ),
                ),
              if (state.error case final error?) ...[
                Text(
                  error,
                  style: AppTypography.small.copyWith(color: AppColors.danger),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
            ],
          ),
        ),
        _Footer(
          children: [
            AppButton(
              label: 'Back',
              variant: AppButtonVariant.secondary,
              onPressed: state.committing
                  ? null
                  : () => controller.goTo(
                      hadDuplicates
                          ? ImportStep.duplicates
                          : ImportStep.validate,
                    ),
            ),
            AppButton(
              label: total == 0
                  ? 'Nothing to import'
                  : 'Import $total ${total == 1 ? 'employee' : 'employees'}',
              busy: state.committing,
              busyLabel: 'Importing…',
              onPressed: total == 0 ? null : controller.commit,
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------- Step 6: results ----------------

/// Board S51. Counts come from the saved record, so they always match what
/// was actually saved.
class ImportResultsView extends ConsumerWidget {
  const ImportResultsView({
    super.key,
    required this.record,
    required this.onImportFixed,
  });

  final ImportRecord record;
  final VoidCallback onImportFixed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branches = ref.watch(branchesProvider).value ?? const <Branch>[];
    final names = [
      for (final id in record.branchIds)
        branches.where((b) => b.id == id).firstOrNull?.name ?? id,
    ];
    final where = names.isEmpty ? '' : ' to ${names.join(', ')}';
    final title = record.created == 0 && record.updated > 0
        ? '${record.updated} ${record.updated == 1 ? 'employee' : 'employees'} updated'
        : '${record.created} ${record.created == 1 ? 'employee' : 'employees'} added$where';
    final parts = [
      if (record.failed > 0)
        '${record.failed} ${record.failed == 1 ? 'row' : 'rows'} failed when saving',
      if (record.skipped > 0)
        '${record.skipped} ${record.skipped == 1 ? 'was' : 'were'} skipped',
      if (record.updated > 0 && record.created > 0) '${record.updated} updated',
    ];
    final lead = [
      if (parts.isNotEmpty) '${parts.join(' and ')}.',
      if (record.invitationsSent > 0)
        '${record.invitationsSent} ${record.invitationsSent == 1 ? 'invitation is' : 'invitations are'} being sent.',
      if (parts.isEmpty && record.invitationsSent == 0)
        'Every row was imported.',
    ].join(' ');

    void report() {
      ref
          .read(fileDownloadsProvider)
          .save(
            'import_report_${record.fileName.split('.').first}.xlsx',
            buildXlsx('Not imported', resultReportRows(record)),
            mimeType: xlsxMimeType,
          );
      showAppToast(context, 'Error report downloaded');
    }

    Widget stat(String label, int v, String icon, Color color) => Container(
      width: 150,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$icon $label',
            style: AppTypography.small.copyWith(color: color),
          ),
          Text('$v', style: AppTypography.metric),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StepHeading(title, lead),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            stat('Created', record.created, '✓', AppColors.success),
            stat('Updated', record.updated, '↻', AppColors.textSecondary),
            stat('Skipped', record.skipped, '–', AppColors.textSecondary),
            stat('Failed', record.failed, '×', AppColors.danger),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        if (record.notImported.isNotEmpty)
          AppCard(
            header: CardHeader(
              title:
                  'Not imported · ${record.notImported.length} ${record.notImported.length == 1 ? 'row' : 'rows'}',
              trailing: AppButton(
                label: 'Download error report (.xlsx)',
                size: AppButtonSize.small,
                variant: AppButtonVariant.secondary,
                onPressed: report,
              ),
            ),
            padding: EdgeInsets.zero,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                dataRowMaxHeight: double.infinity,
                columns: const [
                  DataColumn(label: Text('ROW'), numeric: true),
                  DataColumn(label: Text('EMPLOYEE')),
                  DataColumn(label: Text('OUTCOME')),
                  DataColumn(label: Text('REASON')),
                ],
                rows: [
                  for (final r in record.notImported)
                    DataRow(
                      cells: [
                        DataCell(
                          Text('${r.rowNumber}', style: AppTypography.code),
                        ),
                        DataCell(
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r.name.isEmpty ? '—' : r.name,
                                style: AppTypography.bodyStrong,
                              ),
                              Text(r.code, style: AppTypography.code),
                            ],
                          ),
                        ),
                        DataCell(
                          StatusBadge(
                            label: r.outcome.label,
                            tone: r.outcome == RowOutcome.failed
                                ? StatusTone.danger
                                : StatusTone.neutral,
                          ),
                        ),
                        DataCell(
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Text(r.reason, style: AppTypography.small),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          )
        else
          const AppCard(
            child: Text(
              'Every row in the file was imported.',
              style: AppTypography.small,
            ),
          ),
        _Footer(
          children: [
            AppButton(
              label: 'Import fixed rows',
              variant: AppButtonVariant.secondary,
              onPressed: onImportFixed,
            ),
            AppButton(
              label: 'View new employees',
              onPressed: () => context.go(AppRoutes.employees),
            ),
          ],
        ),
      ],
    );
  }
}
