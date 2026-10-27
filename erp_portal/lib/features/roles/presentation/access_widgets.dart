import 'package:flutter/material.dart';

import '../../../core/permissions/permissions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/selection_controls.dart';
import '../../../core/widgets/status_badge.dart';
import '../domain/access.dart';
import '../domain/access_levels.dart';

/// One area of the app (D-79): pick a level, see in sentences what it
/// allows, flip the special abilities, or fine-tune every ability.
class AccessAreaCard extends StatefulWidget {
  const AccessAreaCard({
    super.key,
    required this.module,
    required this.grants,
    required this.onChanged,
    this.saved,
    this.readOnly = false,
  });

  final PermissionModule module;
  final PermissionSet grants;
  final PermissionSet? saved;
  final bool readOnly;
  final ValueChanged<PermissionSet> onChanged;

  @override
  State<AccessAreaCard> createState() => _AccessAreaCardState();
}

class _AccessAreaCardState extends State<AccessAreaCard> {
  bool _fine = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.module;
    final area = accessAreas[m]!;
    final grants = widget.grants;
    final level = levelOf(grants, m);
    final plain = isPlainLevel(grants, m);
    final abilities = [
      for (final a in PermissionAction.values)
        if (isApplicable(m, a) && area.abilities[a] != null) a,
    ];
    final changed =
        widget.saved != null &&
        abilities.any((a) => widget.saved!.can(m, a) != grants.can(m, a));
    final switches = [
      if (level == AccessLevel.view || level == AccessLevel.edit)
        for (final a in extraActions)
          if (assignable(m).contains(a)) a,
    ];

    Widget levelChip(AccessLevel l) {
      final selected = l == level;
      return Semantics(
        button: true,
        selected: selected,
        label: '${area.name}: ${l.label}',
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: widget.readOnly
              ? null
              : () => widget.onChanged(withLevel(grants, m, l)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? AppColors.ink : AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(
                color: selected ? AppColors.ink : AppColors.borderStrong,
              ),
            ),
            child: Text(
              l.label,
              style: AppTypography.label.copyWith(
                color: selected ? AppColors.surface : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      );
    }

    return AppCard(
      header: CardHeader(
        title: area.name,
        subtitle: area.about,
        trailing: changed
            ? const StatusBadge(label: 'Changed', tone: StatusTone.warning)
            : (!plain
                  ? const StatusBadge(
                      label: 'Custom mix',
                      tone: StatusTone.info,
                    )
                  : null),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [for (final l in levelsFor(m)) levelChip(l)],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            plain
                ? level.hint
                : 'A hand-picked set of abilities, listed below.',
            style: AppTypography.helper,
          ),
          if (level != AccessLevel.none && !_fine) ...[
            const SizedBox(height: AppSpacing.sm),
            for (final a in abilities)
              if (grants.can(m, a) && !switches.contains(a))
                _Allowed(area.abilities[a]!),
            for (final a in switches)
              Semantics(
                label: '${area.name}: ${area.abilities[a]}',
                excludeSemantics: true,
                toggled: grants.can(m, a),
                child: SwitchRow(
                  label: area.abilities[a]!,
                  value: grants.can(m, a),
                  onChanged: widget.readOnly
                      ? null
                      : (v) => widget.onChanged(withAbility(grants, m, a, v)),
                ),
              ),
          ],
          if (_fine) ...[
            const SizedBox(height: AppSpacing.sm),
            for (final a in abilities)
              isOwnerOnly(m, a)
                  ? SwitchRow(
                      label: area.abilities[a]!,
                      value: false,
                      onChanged: null,
                      lockedNote: ' · owner only',
                    )
                  : Semantics(
                      label: '${area.name}: ${area.abilities[a]}',
                      excludeSemantics: true,
                      toggled: grants.can(m, a),
                      child: SwitchRow(
                        label: area.abilities[a]!,
                        value: grants.can(m, a),
                        onChanged: widget.readOnly
                            ? null
                            : (v) => widget.onChanged(
                                withAbility(grants, m, a, v),
                              ),
                      ),
                    ),
          ],
          if (!widget.readOnly)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _fine = !_fine),
                child: Text(
                  _fine ? 'Done fine-tuning' : 'Fine-tune…',
                  semanticsLabel: _fine
                      ? 'Done fine-tuning ${area.name}'
                      : 'Fine-tune ${area.name}',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Allowed extends StatelessWidget {
  const _Allowed(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.check, size: 16, color: AppColors.success),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(text, style: AppTypography.small)),
      ],
    ),
  );
}

/// "In plain words": who they see, what they can do, what they can't open.
class PlainSummaryCard extends StatelessWidget {
  const PlainSummaryCard({
    super.key,
    required this.role,
    this.title = 'In plain words',
    this.maxItems = 14,
  });

  final RoleDefinition role;
  final String title;
  final int maxItems;

  @override
  Widget build(BuildContext context) {
    final s = plainSummary(role);
    return AppCard(
      header: CardHeader(title: title),
      child: PlainSummary(role: role, maxItems: maxItems, summary: s),
    );
  }
}

class PlainSummary extends StatelessWidget {
  const PlainSummary({
    super.key,
    required this.role,
    this.maxItems = 14,
    this.summary,
  });

  final RoleDefinition role;
  final int maxItems;
  final ({String sees, List<String> can, List<String> cannot})? summary;

  @override
  Widget build(BuildContext context) {
    final s = summary ?? plainSummary(role);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.visibility_outlined,
              size: 16,
              color: AppColors.primary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(s.sees, style: AppTypography.bodyStrong)),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (s.can.isEmpty)
          const Text(
            'They can only use their own self-service pages.',
            style: AppTypography.small,
          )
        else ...[
          const Text('They can', style: AppTypography.label),
          for (final c in s.can.take(maxItems)) _Allowed(c),
          if (s.can.length > maxItems)
            Text(
              '+ ${s.can.length - maxItems} more',
              style: AppTypography.helper,
            ),
        ],
        if (s.cannot.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          const Text('They can’t open', style: AppTypography.label),
          const SizedBox(height: 2),
          Text(s.cannot.join(' · '), style: AppTypography.small),
        ],
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'Everyone also has their own Home, Attendance, Leave, Holidays and Profile.',
          style: AppTypography.helper,
        ),
      ],
    );
  }
}
