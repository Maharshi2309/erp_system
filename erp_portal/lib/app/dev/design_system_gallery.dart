import 'package:flutter/material.dart';

import '../../core/responsive/breakpoints.dart';
import '../../core/responsive/responsive_grid.dart';
import '../../core/responsive/responsive_page.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_data_table.dart';
import '../../core/widgets/app_dropdown_field.dart';
import '../../core/widgets/app_overlays.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/form_error_summary.dart';
import '../../core/widgets/kpi_card.dart';
import '../../core/widgets/page_header.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/widgets/state_views.dart';
import '../../core/widgets/status_badge.dart';

/// Living version of design boards S01 and S02, for reviewing the shared
/// components at every screen size. Demo builds only. All values here are
/// samples copied from the design.
class DesignSystemGallery extends StatelessWidget {
  const DesignSystemGallery({super.key});

  @override
  Widget build(BuildContext context) {
    return const ResponsivePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            title: 'Design system',
            subtitle:
                'Tokens and components shared by every screen (S01, S02). '
                'Sample values only.',
          ),
          SizedBox(height: AppSpacing.md),
          _ScreenSizeBadge(),
          SizedBox(height: AppSpacing.xl),
          _ColorsSection(),
          _Gap(),
          _TypeSection(),
          _Gap(),
          _ButtonsSection(),
          _Gap(),
          _FormSection(),
          _Gap(),
          _BadgesAndKpisSection(),
          _Gap(),
          _TableSection(),
          _Gap(),
          _StatesSection(),
          _Gap(),
          _OverlaysSection(),
        ],
      ),
    );
  }
}

class _Gap extends StatelessWidget {
  const _Gap();

  @override
  Widget build(BuildContext context) => const SizedBox(height: AppSpacing.xl);
}

class _ScreenSizeBadge extends StatelessWidget {
  const _ScreenSizeBadge();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final size = ScreenSize.fromWidth(width);
    final nav = NavLayout.fromWidth(width);
    return Align(
      alignment: Alignment.centerLeft,
      child: StatusBadge(
        label: 'Screen ${width.round()} px · ${size.name} · menu: ${nav.name}',
        tone: StatusTone.info,
      ),
    );
  }
}

class _ColorsSection extends StatelessWidget {
  const _ColorsSection();

  static const _swatches = <(String, Color)>[
    ('Primary', AppColors.primary),
    ('Primary soft', AppColors.primarySoft),
    ('Success', AppColors.success),
    ('Warning', AppColors.warning),
    ('Danger', AppColors.danger),
    ('Text primary', AppColors.textPrimary),
    ('Text secondary', AppColors.textSecondary),
    ('Text muted', AppColors.textMuted),
    ('Canvas', AppColors.canvas),
    ('Border', AppColors.border),
    ('Border strong', AppColors.borderStrong),
    ('Surface', AppColors.surface),
  ];

  static String _hex(Color c) =>
      '#${c.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

  @override
  Widget build(BuildContext context) {
    return AppCard(
      header: const CardHeader(title: 'Colour tokens'),
      child: ResponsiveGrid(
        minItemWidth: 130,
        children: [
          for (final (name, color) in _swatches)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: color,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
                const SizedBox(height: 6),
                Text(name, style: AppTypography.label),
                Text(_hex(color), style: AppTypography.code),
              ],
            ),
        ],
      ),
    );
  }
}

class _TypeSection extends StatelessWidget {
  const _TypeSection();

  @override
  Widget build(BuildContext context) {
    const samples = <(String, TextStyle, String)>[
      ('Page title · 24/32', AppTypography.pageTitle, 'Employee directory'),
      ('Section · 16/24', AppTypography.sectionTitle, 'Work schedule'),
      ('Card title · 15/22', AppTypography.cardTitle, 'Pending approvals'),
      ('Body · 14/22', AppTypography.body, 'Leave is deducted after approval.'),
      ('Label · 13/18', AppTypography.label, 'Branch code'),
      ('Helper · 12/18', AppTypography.helper, 'Visible to HR admins only.'),
      ('Metric · mono 30/36', AppTypography.metric, '8h 42m'),
      ('ID / code · mono 13', AppTypography.code, 'EMP-0142 · AHM-01'),
    ];
    return AppCard(
      header: const CardHeader(title: 'Type scale'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (name, style, text) in samples)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs + 2),
              child: Wrap(
                spacing: AppSpacing.lg,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 160,
                    child: Text(name, style: AppTypography.helper),
                  ),
                  Text(text, style: style),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ButtonsSection extends StatefulWidget {
  const _ButtonsSection();

  @override
  State<_ButtonsSection> createState() => _ButtonsSectionState();
}

class _ButtonsSectionState extends State<_ButtonsSection> {
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    setState(() => _saving = false);
    showAppToast(context, 'Saved (demo — nothing was stored)');
  }

  @override
  Widget build(BuildContext context) {
    void noop() {}
    return AppCard(
      header: const CardHeader(
        title: 'Buttons',
        subtitle: 'Heights 32 / 40 / 48. One primary action per view.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              AppButton(label: 'Primary', onPressed: noop),
              AppButton(
                label: 'Secondary',
                variant: AppButtonVariant.secondary,
                onPressed: noop,
              ),
              AppButton(
                label: 'Ghost',
                variant: AppButtonVariant.ghost,
                onPressed: noop,
              ),
              AppButton(
                label: 'Deactivate',
                variant: AppButtonVariant.danger,
                onPressed: noop,
              ),
              AppButton(
                label: 'Reject…',
                variant: AppButtonVariant.dangerOutline,
                onPressed: noop,
              ),
              const AppButton(label: 'Disabled', onPressed: null),
              AppButton(
                label: 'Save changes',
                busyLabel: 'Saving…',
                busy: _saving,
                onPressed: _save,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AppButton(
                label: 'Small',
                size: AppButtonSize.small,
                variant: AppButtonVariant.secondary,
                onPressed: noop,
              ),
              AppButton(
                label: 'Medium',
                variant: AppButtonVariant.secondary,
                onPressed: noop,
              ),
              AppButton(
                label: 'Add employee',
                icon: Icons.add,
                size: AppButtonSize.large,
                onPressed: noop,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FormSection extends StatefulWidget {
  const _FormSection();

  @override
  State<_FormSection> createState() => _FormSectionState();
}

class _FormSectionState extends State<_FormSection> {
  final _name = TextEditingController(text: 'Surat Ring Road');
  final _code = TextEditingController(text: 'AHM-01');
  final _nameFocus = FocusNode();
  final _codeFocus = FocusNode();
  String? _timeZone = 'Asia/Kolkata';
  Map<String, String> _errors = {};
  bool _showSummary = false;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _nameFocus.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  void _submit() {
    final errors = <String, String>{};
    if (_name.text.trim().isEmpty) errors['name'] = 'Enter a branch name.';
    final code = _code.text.trim().toUpperCase();
    if (code.isEmpty) {
      errors['code'] = 'Enter a branch code.';
    } else if (code == 'AHM-01') {
      errors['code'] =
          'AHM-01 is already used by Ahmedabad HQ. Choose another code.';
    }
    setState(() {
      _errors = errors;
      _showSummary = errors.isNotEmpty;
    });
    if (errors.isEmpty) showAppToast(context, 'Looks good (demo only)');
  }

  void _clearError(String key) {
    if (!_errors.containsKey(key)) return;
    setState(() => _errors = {..._errors}..remove(key));
  }

  @override
  Widget build(BuildContext context) {
    final count = _errors.length;
    return AppCard(
      header: const CardHeader(
        title: 'Form fields',
        subtitle:
            'Inline error under the field plus a summary at the top. '
            'Nothing typed is lost.',
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_showSummary && count > 0) ...[
              FormErrorSummary(
                title:
                    'Please fix ${count == 1 ? '1 thing' : '$count things'}. '
                    'Nothing you entered was lost.',
                items: [
                  if (_errors['name'] case final message?)
                    FormErrorItem(message, onTap: _nameFocus.requestFocus),
                  if (_errors['code'] case final message?)
                    FormErrorItem(message, onTap: _codeFocus.requestFocus),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            AppTextField(
              label: 'Branch name',
              isRequired: true,
              controller: _name,
              focusNode: _nameFocus,
              errorText: _errors['name'],
              onChanged: (_) => _clearError('name'),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              label: 'Branch code',
              isRequired: true,
              monospace: true,
              controller: _code,
              focusNode: _codeFocus,
              errorText: _errors['code'],
              onChanged: (_) => _clearError('code'),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppDropdownField<String>(
              label: 'Time zone',
              isOptional: true,
              value: _timeZone,
              helperText: 'Used to calculate shift windows and late arrivals.',
              options: const [
                AppDropdownOption('Asia/Kolkata', 'Asia/Kolkata (UTC+05:30)'),
                AppDropdownOption('Asia/Dubai', 'Asia/Dubai (UTC+04:00)'),
                AppDropdownOption('Europe/London', 'Europe/London (UTC+00:00)'),
              ],
              onChanged: (value) => setState(() => _timeZone = value),
            ),
            const SizedBox(height: AppSpacing.lg),
            const AppTextField(
              label: 'Password',
              isPassword: true,
              hintText: 'At least 10 characters',
            ),
            const SizedBox(height: AppSpacing.xl),
            Align(
              alignment: Alignment.centerLeft,
              child: AppButton(label: 'Validate', onPressed: _submit),
            ),
          ],
        ),
      ),
    );
  }
}

class _BadgesAndKpisSection extends StatelessWidget {
  const _BadgesAndKpisSection();

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      header: CardHeader(
        title: 'Status badges and KPI cards',
        subtitle: 'Status is never colour alone — a word always comes with it.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              StatusBadge(label: 'Active', tone: StatusTone.success),
              StatusBadge(label: 'Present', tone: StatusTone.success),
              StatusBadge(label: 'Pending', tone: StatusTone.warning),
              StatusBadge(label: 'Late', tone: StatusTone.warning),
              StatusBadge(label: 'Rejected', tone: StatusTone.danger),
              StatusBadge(label: 'Missing punch', tone: StatusTone.danger),
              StatusBadge(label: 'Invited', tone: StatusTone.info),
              StatusBadge(label: 'Inactive', tone: StatusTone.neutral),
            ],
          ),
          SizedBox(height: AppSpacing.lg),
          ResponsiveGrid(
            minItemWidth: 160,
            children: [
              KpiCard(
                label: 'Total employees',
                value: '248',
                caption: '+6 this month',
              ),
              KpiCard(
                label: 'Present today',
                value: '196',
                caption: '79% of scheduled',
                captionTone: StatusTone.success,
              ),
              KpiCard(
                label: 'Absent · late',
                value: '17 · 12',
                caption: '3 more late than avg',
                captionTone: StatusTone.warning,
              ),
              KpiCard(
                label: 'Pending leave',
                value: '9',
                caption: '2 waiting over 48h',
                captionTone: StatusTone.warning,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TableSection extends StatefulWidget {
  const _TableSection();

  @override
  State<_TableSection> createState() => _TableSectionState();
}

class _TableSectionState extends State<_TableSection> {
  static const _people = <(String, String, String, String, StatusTone)>[
    ('Aarav Bhatt', 'EMP-0201', 'Production', 'Active', StatusTone.success),
    ('Bhavna Solanki', 'EMP-0217', 'Quality', 'Active', StatusTone.success),
    (
      'Chirag Vaghela',
      'EMP-0233',
      'Production',
      'Probation',
      StatusTone.warning,
    ),
    ('Deepa Nair', 'EMP-0198', 'People Ops', 'Active', StatusTone.success),
    ('Faisal Shaikh', 'EMP-0240', 'Logistics', 'Probation', StatusTone.warning),
    ('Gauri Pandya', 'EMP-0176', 'Finance', 'Active', StatusTone.success),
    (
      'Harsh Trivedi',
      'EMP-0152',
      'Facilities',
      'Notice period',
      StatusTone.warning,
    ),
    ('Isha Rathod', 'EMP-0229', 'Production', 'Active', StatusTone.success),
    ('Jayesh Makwana', 'EMP-0118', 'Logistics', 'Inactive', StatusTone.neutral),
    ('Komal Desai', 'EMP-0236', 'Logistics', 'Active', StatusTone.success),
    ('Mansi Thakkar', 'EMP-0212', 'Quality', 'Active', StatusTone.success),
    ('Rohan Pillai', 'EMP-0187', 'Stores', 'Active', StatusTone.success),
  ];

  int _first = 0;
  int _pageSize = 5;

  @override
  Widget build(BuildContext context) {
    final page = _people.skip(_first).take(_pageSize);
    return AppCard(
      header: const CardHeader(
        title: 'Table and pagination',
        subtitle: 'Wide tables scroll sideways inside their own box.',
      ),
      padding: const EdgeInsets.all(AppSpacing.xl - 4),
      child: AppDataTable(
        minWidth: 640,
        columns: const [
          DataColumn(label: Text('EMPLOYEE')),
          DataColumn(label: Text('DEPARTMENT')),
          DataColumn(label: Text('EMPLOYMENT')),
        ],
        rows: [
          for (final (name, id, dept, status, tone) in page)
            DataRow(
              cells: [
                DataCell(
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: AppTypography.bodyStrong),
                      Text(id, style: AppTypography.code),
                    ],
                  ),
                ),
                DataCell(Text(dept)),
                DataCell(StatusBadge(label: status, tone: tone)),
              ],
            ),
        ],
        footer: PaginationBar(
          firstIndex: _first,
          pageSize: _pageSize,
          totalCount: _people.length,
          pageSizeOptions: const [5, 10],
          onPageChanged: (first) => setState(() => _first = first),
          onPageSizeChanged: (size) => setState(() {
            _pageSize = size;
            _first = 0;
          }),
        ),
      ),
    );
  }
}

class _StatesSection extends StatelessWidget {
  const _StatesSection();

  @override
  Widget build(BuildContext context) {
    void noop() {}
    return AppCard(
      header: const CardHeader(
        title: 'Empty, error and loading states',
        subtitle: 'Every list has an empty state; every load has a skeleton.',
      ),
      child: ResponsiveGrid(
        minItemWidth: 280,
        maxColumns: 3,
        children: [
          _Framed(
            child: EmptyState(
              icon: Icons.filter_alt_off_outlined,
              title: 'No employees match these filters',
              message: 'Try removing “Surat” or “On probation”.',
              actions: [
                AppButton(
                  label: 'Clear filters',
                  variant: AppButtonVariant.secondary,
                  onPressed: noop,
                ),
              ],
            ),
          ),
          _Framed(
            child: ErrorState(
              title: 'Couldn’t load this summary',
              message:
                  'Our server didn’t answer in time. Nothing was changed. '
                  'Try again — if it keeps happening, share the reference '
                  'with support.',
              reference: 'req_8a234',
              onRetry: noop,
            ),
          ),
          const _Framed(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: LoadingSkeleton(
                label: 'Loading employees',
                delay: Duration.zero,
                child: SkeletonList(rows: 4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Framed extends StatelessWidget {
  const _Framed({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 260),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: child,
    );
  }
}

class _OverlaysSection extends StatelessWidget {
  const _OverlaysSection();

  Future<void> _confirm(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Deactivate Isha Rathod?',
      message:
          'Removes sign-in access. Attendance, leave and audit history are kept.',
      confirmLabel: 'Deactivate',
      destructive: true,
    );
    if (!context.mounted) return;
    showAppToast(
      context,
      confirmed ? 'Confirmed (demo — nothing changed)' : 'Cancelled',
    );
  }

  Future<void> _panel(BuildContext context) => showSidePanel<void>(
    context,
    title: 'Isha Rathod · Casual leave',
    subtitle: 'Sent 13 Oct, 18:42',
    body: (context) => const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _KeyValue('Dates', 'Mon 19 Oct · 1 day'),
        _KeyValue('Balance after', '3.0 days', mono: true),
        _KeyValue('Approver', 'Aarav Bhatt'),
        _KeyValue('Reason', 'Licence renewal appointment'),
        _KeyValue('Team off', '2 of 24'),
      ],
    ),
    actions: (context) => [
      AppButton(
        label: 'Reject…',
        variant: AppButtonVariant.dangerOutline,
        onPressed: () => Navigator.of(context).pop(),
      ),
      AppButton(label: 'Approve', onPressed: () => Navigator.of(context).pop()),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return AppCard(
      header: const CardHeader(
        title: 'Dialogs, side panel and toast',
        subtitle:
            'Side panel: 440 px, full width below 600 px; Esc closes; focus '
            'stays inside.',
      ),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          AppButton(
            label: 'Confirm dialog',
            variant: AppButtonVariant.secondary,
            onPressed: () => _confirm(context),
          ),
          AppButton(
            label: 'Side panel',
            variant: AppButtonVariant.secondary,
            onPressed: () => _panel(context),
          ),
          AppButton(
            label: 'Toast',
            variant: AppButtonVariant.secondary,
            onPressed: () => showAppToast(context, 'Owner profile saved'),
          ),
        ],
      ),
    );
  }
}

class _KeyValue extends StatelessWidget {
  const _KeyValue(this.label, this.value, {this.mono = false});

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(label, style: AppTypography.small)),
          Expanded(
            child: Text(
              value,
              style: mono
                  ? AppTypography.body.copyWith(fontFamily: AppTypography.mono)
                  : AppTypography.body,
            ),
          ),
        ],
      ),
    );
  }
}
