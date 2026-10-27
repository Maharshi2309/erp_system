import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router/route_names.dart';
import '../../../core/errors/failure.dart';
import '../../../core/permissions/permissions.dart';
import '../../../core/permissions/system_roles.dart';
import '../../../core/responsive/responsive_page.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/file_download.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_data_table.dart';
import '../../../core/widgets/app_overlays.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../dashboard/presentation/dashboard_widgets.dart';
import '../../employees/data/spreadsheet.dart';
import '../../leave/presentation/leave_widgets.dart';
import '../../organization/domain/branch.dart';
import '../../organization/presentation/providers/organization_providers.dart';
import '../domain/audit.dart';
import 'audit_providers.dart';

final _stamp = DateFormat('d MMM HH:mm');
final _full = DateFormat('EEE d MMM y, HH:mm:ss');

(Color, Color) actionColors(String action) => switch (action.split('.').last) {
  'approve' ||
  'create' ||
  'commit' ||
  'import' => (AppColors.successSoft, AppColors.successText),
  'reject' ||
  'delete' ||
  'revoke' ||
  'terminate' ||
  'deactivate' => (AppColors.dangerSoft, AppColors.dangerText),
  'correct' ||
  'adjust' ||
  'amend' => (AppColors.warningSoft, AppColors.warningText),
  'signin_failed' ||
  'reauth' ||
  'reveal' => (AppColors.neutralSoft, AppColors.textSecondary),
  _ => (AppColors.primarySoft, AppColors.primaryHover),
};

class ActionChip2 extends StatelessWidget {
  const ActionChip2(this.action, {super.key});

  final String action;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = actionColors(action);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        action,
        style: AppTypography.code.copyWith(fontSize: 12, color: fg),
      ),
    );
  }
}

/// Values the owner revealed this session, by "eventId|field".
final revealedProvider = NotifierProvider<_Revealed, Set<String>>(
  _Revealed.new,
);

class _Revealed extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    ref.watch(sessionProvider);
    return const {};
  }

  void add(String key) => state = {...state, key};
}

/// Before/after table with masking (boards S77, S78).
class ChangesTable extends ConsumerWidget {
  const ChangesTable({super.key, required this.event});

  final AuditEvent event;

  Future<void> _reveal(
    BuildContext context,
    WidgetRef ref,
    String field,
  ) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _RevealDialog(),
    );
    if (reason == null) return;
    await ref
        .read(auditRecorderProvider)
        .record(
          action: 'audit.reveal',
          entityType: 'Audit entry',
          entityId: event.id,
          entityLabel: event.id,
          entityRoute: AppRoutes.auditEvent(event.id),
          summary: 'Revealed $field on ${event.id}',
          reason: reason,
        );
    ref.read(revealedProvider.notifier).add('${event.id}|$field');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOwner = ref.watch(sessionProvider)?.role == SystemRole.owner;
    final revealed = ref.watch(revealedProvider);
    final rows = [
      ...event.changes,
      if (event.ip.isNotEmpty)
        (field: 'IP address', before: '', after: event.ip),
    ];
    if (rows.isEmpty) {
      return const Text('No field-level changes.', style: AppTypography.small);
    }
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1.2),
        1: FlexColumnWidth(1.4),
        2: FlexColumnWidth(1.4),
      },
      border: const TableBorder(
        horizontalInside: BorderSide(color: AppColors.divider),
      ),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        const TableRow(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('Field', style: AppTypography.tableHeader),
            ),
            Text('Before', style: AppTypography.tableHeader),
            Text('After', style: AppTypography.tableHeader),
          ],
        ),
        for (final c in rows)
          () {
            final sensitive = sensitiveFields.contains(c.field);
            final open = revealed.contains('${event.id}|${c.field}');
            String show(String v) =>
                sensitive && !open ? maskValue(c.field, v) : v;
            return TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(c.field, style: AppTypography.small),
                      if (sensitive && isOwner && !open)
                        TextButton(
                          onPressed: () => _reveal(context, ref, c.field),
                          child: Text(
                            'Reveal',
                            semanticsLabel: 'Reveal ${c.field}',
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  c.before.isEmpty ? '—' : show(c.before),
                  style: AppTypography.code.copyWith(
                    color: AppColors.textSecondary,
                    decoration: c.after.isNotEmpty && c.before.isNotEmpty
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                Text(
                  show(c.after),
                  style: AppTypography.code.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            );
          }(),
      ],
    );
  }
}

class _RevealDialog extends StatefulWidget {
  const _RevealDialog();

  @override
  State<_RevealDialog> createState() => _RevealDialogState();
}

class _RevealDialogState extends State<_RevealDialog> {
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Reveal a masked value?'),
    content: SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'The full value is shown to you only, and your reason is logged.',
            style: AppTypography.small,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            label: 'Reason',
            isRequired: true,
            controller: _reason,
            errorText: _error,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_reason.text.trim().length < 5) {
            setState(() => _error = 'Give a reason (at least 5 characters).');
            return;
          }
          Navigator.of(context).pop(_reason.text.trim());
        },
        child: const Text('Reveal'),
      ),
    ],
  );
}

Widget _loading(WidgetRef ref, AsyncValue<Object?> v) => v.hasError
    ? ErrorState(
        message: userMessageFor(v.error!),
        onRetry: () => ref.invalidate(auditEventsProvider),
      )
    : const ResponsivePage(
        child: LoadingSkeleton(
          label: 'Loading audit log',
          child: SkeletonList(rows: 8),
        ),
      );

/// Board S77 — the append-only audit log.
class AuditLogScreen extends ConsumerStatefulWidget {
  const AuditLogScreen({super.key});

  @override
  ConsumerState<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends ConsumerState<AuditLogScreen> {
  AuditQuery _q = const AuditQuery();
  String? _selected;
  int _page = 0;
  static const _perPage = 25;

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(auditEventsProvider);
    final session = ref.watch(sessionProvider);
    if (!events.hasValue || session == null) return _loading(ref, events);
    final now = ref.watch(orgNowProvider)();
    final branches = ref.watch(branchesProvider).value ?? const <Branch>[];
    final all = events.value!;
    final shown = [
      for (final e in all)
        if (_q.matches(e, now)) e,
    ];
    final pages = (shown.length / _perPage).ceil();
    final page = _page.clamp(0, pages == 0 ? 0 : pages - 1);
    final slice = shown.skip(page * _perPage).take(_perPage).toList();
    final selected =
        slice.where((e) => e.id == _selected).firstOrNull ?? slice.firstOrNull;
    final canExport = session.permissions.can(
      PermissionModule.auditLog,
      PermissionAction.export,
    );
    String branchName(String? id) => id == null
        ? 'Organization'
        : (branches.where((b) => b.id == id).firstOrNull?.name ?? id);

    void export() {
      startDownload(
        context,
        ref,
        'audit_log_${DateFormat('yyyy-MM-dd').format(now)}.xlsx',
        buildXlsx('Audit log', [
          [
            'Event',
            'Time',
            'Actor',
            'Role',
            'Action',
            'Entity',
            'Scope',
            'Summary',
            'Reason',
            'Changes (masked)',
            'IP (masked)',
            'Checksum',
          ],
          for (final e in shown)
            [
              e.id,
              DateFormat('yyyy-MM-dd HH:mm:ss').format(e.at),
              e.actorName,
              e.actorRole,
              e.action,
              e.entityLabel,
              e.scopeLabel.isEmpty ? branchName(e.branchId) : e.scopeLabel,
              e.summary,
              e.reason,
              e.changes
                  .map(
                    (c) =>
                        '${c.field}: ${shownValue(c.field, c.before)} → ${shownValue(c.field, c.after)}',
                  )
                  .join('; '),
              e.ip.isEmpty ? '' : maskValue('IP address', e.ip),
              e.hash,
            ],
        ]),
        mimeType: xlsxMimeType,
      );
      ref
          .read(auditRecorderProvider)
          .record(
            action: 'audit.export',
            entityType: 'Audit log',
            entityLabel: 'Audit log',
            summary: 'Exported ${shown.length} events',
          );
      showAppToast(context, '${shown.length} events exported');
    }

    final actors = {for (final e in all) e.actorName}.toList()..sort();
    final areas = {for (final e in all) e.area}.toList()..sort();
    final entities = {for (final e in all) e.entityType}.toList()..sort();
    final filtered =
        _q.actor != null ||
        _q.areas.isNotEmpty ||
        _q.entityType != null ||
        _q.branchId != null ||
        _q.search.isNotEmpty ||
        _q.days != 7;

    final table = slice.isEmpty
        ? AppCard(
            child: EmptyState(
              icon: Icons.manage_search,
              title: 'No events',
              message: 'Nothing matches these filters.',
              actions: [
                if (filtered)
                  AppButton(
                    label: 'Clear filters',
                    variant: AppButtonVariant.secondary,
                    onPressed: () => setState(() => _q = const AuditQuery()),
                  ),
              ],
            ),
          )
        : AppDataTable(
            minWidth: 900,
            showCheckboxColumn: false,
            columns: const [
              DataColumn(label: Text('Time')),
              DataColumn(label: Text('Actor')),
              DataColumn(label: Text('Action')),
              DataColumn(label: Text('Entity')),
              DataColumn(label: Text('Summary')),
            ],
            rows: [
              for (final e in slice)
                DataRow(
                  selected: e.id == selected?.id,
                  onSelectChanged: (_) => setState(() => _selected = e.id),
                  cells: [
                    DataCell(
                      Text(_stamp.format(e.at), style: AppTypography.code),
                    ),
                    DataCell(
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.actorName, style: AppTypography.small),
                          Text(e.actorRole, style: AppTypography.helper),
                        ],
                      ),
                    ),
                    DataCell(ActionChip2(e.action)),
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 200),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.entityLabel,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.small.copyWith(
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              e.scopeLabel.isEmpty
                                  ? branchName(e.branchId)
                                  : e.scopeLabel,
                              style: AppTypography.helper,
                            ),
                          ],
                        ),
                      ),
                    ),
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: Text(
                          e.summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.small.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      onTap: () => context.go(AppRoutes.auditEvent(e.id)),
                    ),
                  ],
                ),
            ],
            footer: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${page * _perPage + 1}–${page * _perPage + slice.length} of ${shown.length} events',
                      style: AppTypography.helper,
                    ),
                  ),
                  TextButton(
                    onPressed: page == 0
                        ? null
                        : () => setState(() => _page = page - 1),
                    child: const Text('Newer'),
                  ),
                  TextButton(
                    onPressed: page >= pages - 1
                        ? null
                        : () => setState(() => _page = page + 1),
                    child: const Text('Older'),
                  ),
                ],
              ),
            ),
          );

    final side = selected == null
        ? null
        : AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${selected.id} · ${_full.format(selected.at)}',
                  style: AppTypography.code.copyWith(fontSize: 12),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(selected.summary, style: AppTypography.cardTitle),
                const SizedBox(height: AppSpacing.md),
                InfoRow(
                  'Actor',
                  '${selected.actorName} · ${selected.actorRole}',
                ),
                InfoRow(
                  'Scope',
                  selected.scopeLabel.isEmpty
                      ? branchName(selected.branchId)
                      : selected.scopeLabel,
                ),
                InfoRow('Record', selected.entityLabel),
                InfoRow(
                  'Source',
                  selected.ip.isEmpty
                      ? selected.source.label
                      : '${selected.source.label} · ${maskValue('IP address', selected.ip)}',
                ),
                if (selected.reason.isNotEmpty)
                  InfoRow('Reason', selected.reason),
                const SizedBox(height: AppSpacing.md),
                ChangesTable(event: selected),
                const SizedBox(height: AppSpacing.md),
                const Text(
                  'Sensitive values (contact details, IDs, passwords) are masked here and never shown in full.',
                  style: AppTypography.helper,
                ),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () =>
                        context.go(AppRoutes.auditEvent(selected.id)),
                    child: const Text('Open event'),
                  ),
                ),
              ],
            ),
          );

    return ResponsivePage(
      child: LayoutBuilder(
        builder: (context, c) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.sm,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: const Text(
                        'Audit log',
                        style: AppTypography.pageTitle,
                      ),
                    ),
                    const Text(
                      'Append-only. Entries can’t be edited or deleted by anyone.',
                      style: AppTypography.small,
                    ),
                  ],
                ),
                if (canExport)
                  AppButton(
                    label: 'Export',
                    icon: Icons.download_outlined,
                    variant: AppButtonVariant.secondary,
                    onPressed: shown.isEmpty ? null : export,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 220,
                  child: SearchBox(
                    label: 'Search events',
                    hint: 'Summary, record or ID',
                    onChanged: (v) => setState(() {
                      _q = _q.copyWith(search: v);
                      _page = 0;
                    }),
                  ),
                ),
                SizedBox(
                  width: 150,
                  child: DashboardSelect<int>(
                    label: 'Date range',
                    value: _q.days,
                    options: const [
                      (1, 'Today'),
                      (7, 'Last 7 days'),
                      (30, 'Last 30 days'),
                      (90, 'Last 90 days'),
                      (0, 'All time'),
                    ],
                    onChanged: (v) => setState(() {
                      _q = _q.copyWith(days: v ?? 7);
                      _page = 0;
                    }),
                  ),
                ),
                SizedBox(
                  width: 170,
                  child: DashboardSelect<String?>(
                    label: 'Actor',
                    value: _q.actor,
                    options: [
                      (null, 'Any actor'),
                      for (final a in actors) (a, a),
                    ],
                    onChanged: (v) =>
                        setState(() => _q = _q.copyWith(actor: v)),
                  ),
                ),
                SizedBox(
                  width: 170,
                  child: DashboardSelect<String?>(
                    label: 'Action',
                    value: _q.areas.isEmpty ? null : _q.areas.first,
                    options: [
                      (null, 'Any action'),
                      for (final a in areas) (a, 'Action: $a'),
                    ],
                    onChanged: (v) => setState(
                      () => _q = _q.copyWith(areas: v == null ? {} : {v}),
                    ),
                  ),
                ),
                SizedBox(
                  width: 170,
                  child: DashboardSelect<String?>(
                    label: 'Entity',
                    value: _q.entityType,
                    options: [
                      (null, 'Any entity'),
                      for (final e in entities) (e, e),
                    ],
                    onChanged: (v) =>
                        setState(() => _q = _q.copyWith(entityType: v)),
                  ),
                ),
                if (session.branchIds.length != 1)
                  SizedBox(
                    width: 170,
                    child: DashboardSelect<String?>(
                      label: 'Branch',
                      value: _q.branchId,
                      options: [
                        (null, 'All branches'),
                        for (final b in branches)
                          if (session.coversBranch(b.id)) (b.id, b.name),
                      ],
                      onChanged: (v) =>
                          setState(() => _q = _q.copyWith(branchId: v)),
                    ),
                  ),
                if (filtered)
                  TextButton(
                    onPressed: () => setState(() {
                      _q = const AuditQuery();
                      _page = 0;
                    }),
                    child: const Text('Clear'),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (c.maxWidth >= 1050 && side != null)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: table),
                  const SizedBox(width: AppSpacing.lg),
                  SizedBox(width: 380, child: side),
                ],
              )
            else
              table,
          ],
        ),
      ),
    );
  }
}

/// Board S78 — one audit entry.
class AuditEventScreen extends ConsumerWidget {
  const AuditEventScreen({super.key, required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(auditEventsProvider);
    final session = ref.watch(sessionProvider);
    if (!events.hasValue || session == null) return _loading(ref, events);
    final all = events.value!;
    final e = all.where((x) => x.id == eventId).firstOrNull;
    if (e == null) {
      return const ErrorState(
        headline: '404',
        title: 'Event not found',
        message: 'It isn’t in the part of the log you can see.',
      );
    }
    final related = [
      for (final id in e.relatedIds) ?all.where((x) => x.id == id).firstOrNull,
      for (final x in all)
        if (x.relatedIds.contains(e.id) && !e.relatedIds.contains(x.id)) x,
    ];
    // The whole chain is checked only for organization-wide viewers, who
    // see every entry.
    final verified = session.branchIds.isEmpty
        ? verifyAuditChain(all.reversed.toList())
        : null;
    final ctx = <(String, String, bool)>[
      ('Actor', '${e.actorName} · ${e.actorRole}', false),
      ('Entity', e.entityLabel, false),
      ('Scope', e.scopeLabel.isEmpty ? 'Organization' : e.scopeLabel, false),
      if (e.reason.isNotEmpty) ('Reason', e.reason, false),
      ('Source', e.source.label, false),
      if (e.ip.isNotEmpty) ('IP address', maskValue('IP address', e.ip), true),
      ('Event ID', e.id, true),
    ];
    return ResponsivePage(
      maxWidth: 1100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => context.go(AppRoutes.auditLog),
              icon: const Icon(Icons.chevron_left),
              label: const Text('Audit log'),
            ),
          ),
          Wrap(
            spacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ActionChip2(e.action),
              Text(_full.format(e.at), style: AppTypography.small),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            header: true,
            child: Text(e.summary, style: AppTypography.pageTitle),
          ),
          const SizedBox(height: AppSpacing.lg),
          LayoutBuilder(
            builder: (context, c) {
              final main = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppCard(
                    header: const CardHeader(title: 'What changed'),
                    child: ChangesTable(event: e),
                  ),
                  if (e.affected.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.lg),
                    AppCard(
                      header: const CardHeader(title: 'People affected'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final p in e.affected)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Text(p, style: AppTypography.small),
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (related.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.lg),
                    AppCard(
                      header: const CardHeader(title: 'Related events'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final r in related)
                            TextButton(
                              onPressed: () =>
                                  context.go(AppRoutes.auditEvent(r.id)),
                              child: Text(
                                '${_stamp.format(r.at)} · ${r.summary}',
                                textAlign: TextAlign.start,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              );
              final side = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppCard(
                    header: const CardHeader(title: 'Context'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (k, v, mono) in ctx)
                          InfoRow(
                            k,
                            v,
                            valueStyle: mono
                                ? AppTypography.code.copyWith(
                                    color: AppColors.textPrimary,
                                  )
                                : null,
                          ),
                        if (e.entityRoute != null)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: () => context.go(e.entityRoute!),
                              child: const Text('Open record'),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppCard(
                    header: const CardHeader(title: 'Entry is sealed'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Linked to the previous entry by checksum, so any later edit would be detectable. Nobody can change or delete it.',
                          style: AppTypography.small,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'checksum · ${e.hash.substring(0, 4)}…${e.hash.substring(e.hash.length - 4)}',
                          style: AppTypography.code,
                        ),
                        if (verified != null)
                          Text(
                            verified
                                ? '✓ Chain verified (${all.length} entries)'
                                : 'Chain check failed — report this to support',
                            style: AppTypography.small.copyWith(
                              color: verified
                                  ? AppColors.successText
                                  : AppColors.danger,
                            ),
                          ),
                        const SizedBox(height: AppSpacing.sm),
                        const Text(
                          'IP addresses, IDs and contact details are partly masked. Owners can reveal them with a reason, which is logged too.',
                          style: AppTypography.helper,
                        ),
                      ],
                    ),
                  ),
                ],
              );
              return c.maxWidth >= 900
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: main),
                        const SizedBox(width: AppSpacing.lg),
                        SizedBox(width: 360, child: side),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        main,
                        const SizedBox(height: AppSpacing.lg),
                        side,
                      ],
                    );
            },
          ),
        ],
      ),
    );
  }
}
