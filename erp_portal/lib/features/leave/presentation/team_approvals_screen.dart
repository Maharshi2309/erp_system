import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/permissions/permissions.dart';
import '../../../core/responsive/responsive_page.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../employees/presentation/widgets/employee_widgets.dart';
import '../../organization/presentation/providers/organization_providers.dart';
import '../domain/leave.dart';
import '../domain/leave_book.dart';
import 'admin/leave_approvals_screen.dart';
import 'leave_widgets.dart';

/// Board S34 — the leave approver's decisions for their team.
class TeamApprovalsScreen extends ConsumerWidget {
  const TeamApprovalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => withLeaveSelf(ref, (
    book,
    self,
  ) {
    final session = ref.watch(sessionProvider)!;
    final now = ref.watch(orgNowProvider)();
    final visible = book.visibleTo(
      role: session.role,
      self: self,
      branchIds: session.branchIds,
    );
    final waiting =
        visible
            .where(
              (r) =>
                  session.permissions.can(
                    PermissionModule.leave,
                    PermissionAction.approve,
                  ) &&
                  book.canDecide(
                    r,
                    role: session.role,
                    self: self,
                    branchIds: session.branchIds,
                  ),
            )
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final decided =
        visible.where((r) => r.status != LeaveStatus.pending).toList()
          ..sort((a, b) => b.history.last.at.compareTo(a.history.last.at));
    final team = book.employees
        .where((e) => e.managerId == self.id && e.status.isEmployed)
        .length;
    final type = book.data.types.where((t) => t.active).firstOrNull;
    final mine = type == null ? null : book.route(self, type, 1).first;

    return ResponsivePage(
      maxWidth: 960,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              waiting.isEmpty
                  ? 'Nothing needs your decision'
                  : '${waiting.length} ${waiting.length == 1 ? 'request needs' : 'requests need'} your decision',
              style: AppTypography.pageTitle,
            ),
          ),
          Text(switch (session.role.scope) {
            // Owners and HR reach this page too; their scope is wider.
            DataScope.organization =>
              'You approve leave for everyone in the organization.',
            DataScope.assignedBranches =>
              'You approve leave for people in your branches.',
            _ =>
              'You approve leave for the $team people who report to you. You see their leave and balances only.',
          }, style: AppTypography.small),
          const SizedBox(height: AppSpacing.lg),
          if (waiting.isEmpty)
            const AppCard(
              child: EmptyState(
                icon: Icons.task_alt_outlined,
                title: 'All caught up',
                message: 'New requests from your team appear here.',
              ),
            ),
          for (final r in waiting) ...[
            _RequestCard(request: r, book: book, now: now),
            const SizedBox(height: AppSpacing.md),
          ],
          const SizedBox(height: AppSpacing.md),
          AppCard(
            padding: EdgeInsets.zero,
            header: const CardHeader(title: 'Recently decided'),
            child: decided.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: Text(
                      'Nothing decided yet.',
                      style: AppTypography.small,
                    ),
                  )
                : Column(
                    children: [
                      for (final r in decided.take(6))
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                            vertical: 10,
                          ),
                          decoration: const BoxDecoration(
                            border: Border(
                              top: BorderSide(color: AppColors.divider),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${book.person(r.employeeId)?.fullName ?? r.employeeId} · ${leaveRange(r.from, r.to)}',
                                  style: AppTypography.small.copyWith(
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Flexible(child: LeaveStatusBadge(r.status)),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          if (mine != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'Your own leave requests go to ${book.approverName(mine)} — you can’t approve them yourself.',
              textAlign: TextAlign.center,
              style: AppTypography.helper,
            ),
          ],
        ],
      ),
    );
  });
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.book,
    required this.now,
  });

  final LeaveRequest request;
  final LeaveBook book;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final e = book.person(r.employeeId);
    final type = book.data.type(r.typeKey);
    final days = book.daysOf(r);
    final before = e == null || type == null || !type.tracksBalance
        ? null
        : book.balance(e, type.key, r.from.year, exceptRequest: r.id).available;
    final team = book.teamOff(r);
    final old = now.difference(r.createdAt).inHours >= 36;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (e != null) EmployeeAvatar(employee: e, size: 40),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e?.fullName ?? r.employeeId,
                      style: AppTypography.bodyStrong,
                    ),
                    Text(
                      '${type?.name ?? r.typeKey} · ${leaveRange(r.from, r.to)}${r.half == HalfDay.full ? '' : ' (${r.half.label.toLowerCase()})'} · ${dayCount(days)}',
                      style: AppTypography.small,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  'Sent ${sentAgo(r.createdAt, now)}',
                  textAlign: TextAlign.end,
                  style: AppTypography.helper.copyWith(
                    color: old ? AppColors.warningText : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xl,
            runSpacing: AppSpacing.sm,
            children: [
              if (before != null)
                _Fact(
                  'Balance after',
                  before - days < 0
                      ? 'Not enough · ask HR or switch to unpaid'
                      : dayCount(before - days),
                  color: before - days < 0 ? AppColors.danger : null,
                ),
              _Fact('Team off those days', '${team.off} of ${team.team} off'),
              if (r.reason.isNotEmpty) _Fact('Reason', r.reason),
              if (r.amendedFrom case (final f, final t))
                _Fact('Changed from', leaveRange(f, t)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          DecisionActions(
            request: r,
            name: e?.fullName ?? 'The employee',
            days: days,
            allowChanges: false,
          ),
          if (r.history.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                'Last: ${r.history.last.text} · ${DateFormat('d MMM').format(r.history.last.at)}',
                style: AppTypography.helper,
              ),
            ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value, {this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTypography.helper),
            Text(
              value,
              style: AppTypography.small.copyWith(
                color: color ?? AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
