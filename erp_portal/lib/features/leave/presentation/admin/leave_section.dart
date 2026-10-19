import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/route_names.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../../core/permissions/system_roles.dart';
import '../../../../core/responsive/responsive_page.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/tab_strip.dart';
import '../../../../shared/models/app_session.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../employees/domain/employee.dart';
import '../../../employees/presentation/providers/employee_providers.dart';
import '../../domain/leave_book.dart';
import '../leave_providers.dart';

/// Pages of Leave Management (board S57–S61 sub-navigation). Leave types and
/// policy need `leave.edit`; branch managers see the first three.
List<(String, String)> leavePagesFor(PermissionSet p) => [
  ('Approvals', AppRoutes.leave),
  ('Requests', AppRoutes.leaveRequests),
  ('Balances', AppRoutes.leaveBalances),
  if (p.can(PermissionModule.leave, PermissionAction.edit)) ...[
    ('Leave types', AppRoutes.leaveTypes),
    ('Policy', AppRoutes.leavePolicy),
  ],
];

class LeaveSection extends ConsumerWidget {
  const LeaveSection({
    super.key,
    required this.current,
    required this.body,
    this.scrollable = true,
  });

  final String current;
  final Widget Function(BuildContext context, LeaveScopeData scope) body;
  final bool scrollable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final book = ref.watch(leaveBookProvider);
    if (session == null) return const SizedBox.shrink();
    if (book.isLoading) {
      return const ResponsivePage(
        child: LoadingSkeleton(
          label: 'Loading leave',
          child: SkeletonList(rows: 6),
        ),
      );
    }
    if (book.hasError) {
      return ErrorState(
        message: userMessageFor(book.error!),
        onRetry: () => ref.invalidate(leaveDataProvider),
      );
    }
    final self = ref.watch(selfEmployeeProvider);
    final pages = leavePagesFor(session.permissions);
    final index = pages.indexWhere((p) => p.$2 == current);
    return ResponsivePage(
      scrollable: scrollable,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTabStrip(
            tabs: [for (final p in pages) p.$1],
            selected: index < 0 ? 0 : index,
            onSelected: (i) => context.go(pages[i].$2),
          ),
          const SizedBox(height: AppSpacing.lg),
          body(
            context,
            LeaveScopeData(book: book.value!, session: session, self: self),
          ),
        ],
      ),
    );
  }
}

/// The leave book plus who is looking.
class LeaveScopeData {
  LeaveScopeData({
    required this.book,
    required this.session,
    required this.self,
  });

  final LeaveBook book;
  final AppSession session;
  final Employee? self;

  late final requests = book.visibleTo(
    role: session.role,
    self: self,
    branchIds: session.branchIds,
  );

  /// People whose balances the member may see: a leave approver only
  /// their reports, others their branches.
  late final people = [
    for (final e in book.employees)
      if (e.status.isEmployed &&
          (session.role == SystemRole.leaveApprover
              ? e.managerId == self?.id
              : (session.branchIds.isEmpty ||
                    session.branchIds.contains(e.branchId))))
        e,
  ];

  bool get canEdit =>
      session.permissions.can(PermissionModule.leave, PermissionAction.edit);
}
