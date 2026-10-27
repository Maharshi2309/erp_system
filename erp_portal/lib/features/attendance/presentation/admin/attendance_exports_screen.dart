import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/router/route_names.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/file_download.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_date_field.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../auth/presentation/widgets/auth_widgets.dart';
import '../../../dashboard/presentation/dashboard_widgets.dart';
import '../../../employees/data/spreadsheet.dart';
import '../../domain/attendance_book.dart';
import 'attendance_section.dart';

/// Attendance exports (Q-12 option b): a date range as a spreadsheet.
class AttendanceExportsScreen extends ConsumerStatefulWidget {
  const AttendanceExportsScreen({super.key});

  @override
  ConsumerState<AttendanceExportsScreen> createState() =>
      _AttendanceExportsScreenState();
}

class _AttendanceExportsScreenState
    extends ConsumerState<AttendanceExportsScreen> {
  DateTime? _from;
  DateTime? _to;
  String? _branch;
  bool _exceptionsOnly = false;

  @override
  Widget build(BuildContext context) {
    return AttendanceSection(
      current: AppRoutes.attendanceExports,
      body: (context, scope) {
        final book = scope.book;
        final today = book.today;
        final from = _from ?? DateTime(today.year, today.month);
        final to = _to ?? DateTime(today.year, today.month, today.day - 1);
        if (!scope.session.permissions.can(
          PermissionModule.attendance,
          PermissionAction.export,
        )) {
          return const ErrorState(
            title: 'You can’t export attendance',
            message: 'Ask the owner for export access.',
          );
        }
        final people = [
          for (final e in scope.people)
            if (_branch == null || e.branchId == _branch) e,
        ];
        final days = to.isBefore(from) ? 0 : to.difference(from).inDays + 1;

        void export() {
          final rows = <List<String>>[
            [
              'Employee ID',
              'Name',
              'Branch',
              'Department',
              'Date',
              'In',
              'Out',
              'Worked',
              'Expected',
              'Break (min)',
              'Late (min)',
              'Status',
              'Corrected by',
            ],
          ];
          for (var i = 0; i < days; i++) {
            final d = DateTime(from.year, from.month, from.day + i);
            for (final r in book.daysOn(d, people)) {
              if (r.status == DayStatus.none ||
                  r.status == DayStatus.upcoming) {
                continue;
              }
              if (_exceptionsOnly && !r.status.isException) continue;
              rows.add([
                r.employee.code,
                r.employee.fullName,
                book.branchOf(r.employee)?.name ?? '',
                r.employee.department,
                DateFormat('dd/MM/yyyy').format(d),
                r.firstIn == null ? '' : clockTime(r.firstIn!, r.zone),
                r.lastOut == null ? '' : clockTime(r.lastOut!, r.zone),
                formatMinutes(r.workedMinutes),
                formatMinutes(r.expectedMinutes),
                '${r.breakMinutes}',
                '${r.lateMinutes}',
                r.status.label,
                r.correctedBy ?? '',
              ]);
            }
          }
          startDownload(
            context,
            ref,
            'attendance_${DateFormat('yyyyMMdd').format(from)}_${DateFormat('yyyyMMdd').format(to)}.xlsx',
            buildXlsx('Attendance', rows),
            mimeType: xlsxMimeType,
            done: 'Exported ${rows.length - 1} records',
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AttendanceHeader(
              title: 'Attendance exports',
              subtitle:
                  'One row per person per day, with corrections applied and named.',
            ),
            const SizedBox(height: AppSpacing.lg),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: AppSpacing.md,
                      runSpacing: AppSpacing.md,
                      children: [
                        SizedBox(
                          width: 200,
                          child: AppDateField(
                            label: 'From',
                            value: from,
                            lastDate: today,
                            onChanged: (d) => setState(() => _from = d),
                          ),
                        ),
                        SizedBox(
                          width: 200,
                          child: AppDateField(
                            label: 'To',
                            value: to,
                            lastDate: today,
                            onChanged: (d) => setState(() => _to = d),
                          ),
                        ),
                        if (scope.branches.length > 1)
                          SizedBox(
                            width: 200,
                            child: DashboardSelect<String?>(
                              label: 'Branch',
                              value: _branch,
                              options: [
                                (null, 'All branches'),
                                for (final b in scope.branches) (b.id, b.name),
                              ],
                              onChanged: (v) => setState(() => _branch = v),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    LabeledCheckbox(
                      value: _exceptionsOnly,
                      label: const Text(
                        'Exceptions only (late, early, missing, absent)',
                        style: AppTypography.body,
                      ),
                      onChanged: (v) => setState(() => _exceptionsOnly = v),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      days <= 0
                          ? 'Choose a “To” date after the “From” date.'
                          : '$days days · ${people.length} people · .xlsx',
                      style: AppTypography.small,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AppButton(
                        label: 'Download',
                        icon: Icons.download_outlined,
                        onPressed: days <= 0 ? null : export,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
