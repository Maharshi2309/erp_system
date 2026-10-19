import 'package:erp_portal/core/widgets/app_card.dart';
import 'package:erp_portal/core/widgets/app_data_table.dart';
import 'package:erp_portal/core/widgets/kpi_card.dart';
import 'package:erp_portal/core/widgets/page_header.dart';
import 'package:erp_portal/core/widgets/skeleton.dart';
import 'package:erp_portal/core/widgets/state_views.dart';
import 'package:erp_portal/core/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/pump_app.dart';

void main() {
  testWidgets('StatusBadge always shows its word', (tester) async {
    await pumpComponent(
      tester,
      const StatusBadge(label: 'Missing punch', tone: StatusTone.danger),
    );
    expect(find.text('Missing punch'), findsOneWidget);
  });

  testWidgets('KpiCard announces label, value and caption; taps open lists', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var opened = false;
    await pumpComponent(
      tester,
      SizedBox(
        width: 200,
        child: KpiCard(
          label: 'Present today',
          value: '196',
          caption: '79% of scheduled',
          onTap: () => opened = true,
        ),
      ),
    );
    expect(
      find.bySemanticsLabel('Present today, 196, 79% of scheduled'),
      findsOneWidget,
    );
    await tester.tap(find.byType(KpiCard));
    expect(opened, isTrue);
    semantics.dispose();
  });

  testWidgets('AppCard renders header and body', (tester) async {
    await pumpComponent(
      tester,
      const SizedBox(
        width: 400,
        child: AppCard(
          header: CardHeader(title: 'Pending approvals', subtitle: '9 waiting'),
          child: Text('body'),
        ),
      ),
    );
    expect(find.text('Pending approvals'), findsOneWidget);
    expect(find.text('9 waiting'), findsOneWidget);
    expect(find.text('body'), findsOneWidget);
  });

  group('PageHeader', () {
    testWidgets('actions sit beside the title on wide screens', (tester) async {
      await pumpComponent(
        tester,
        SizedBox(
          width: 900,
          child: PageHeader(
            title: 'Employees',
            actions: [TextButton(onPressed: () {}, child: const Text('Add'))],
          ),
        ),
        size: const Size(1000, 600),
      );
      final title = tester.getTopLeft(find.text('Employees'));
      final action = tester.getTopLeft(find.text('Add'));
      expect(action.dx, greaterThan(title.dx + 300));
    });

    testWidgets('actions wrap below the title on narrow screens', (
      tester,
    ) async {
      await pumpComponent(
        tester,
        SizedBox(
          width: 340,
          child: PageHeader(
            title: 'Employees',
            actions: [TextButton(onPressed: () {}, child: const Text('Add'))],
          ),
        ),
        size: const Size(390, 600),
      );
      final title = tester.getBottomLeft(find.text('Employees'));
      final action = tester.getTopLeft(find.text('Add'));
      expect(action.dy, greaterThan(title.dy));
    });

    testWidgets('breadcrumbs separate items with a slash', (tester) async {
      await pumpComponent(
        tester,
        Breadcrumbs(
          items: [
            BreadcrumbItem('Employees', onTap: () {}),
            const BreadcrumbItem('Priya Desai'),
          ],
        ),
      );
      expect(find.text('/'), findsOneWidget);
      expect(find.text('Priya Desai'), findsOneWidget);
    });
  });

  group('States', () {
    testWidgets('EmptyState offers its next step', (tester) async {
      var cleared = false;
      await pumpComponent(
        tester,
        EmptyState(
          icon: Icons.people_outline,
          title: 'No employees yet',
          message: 'Add people one at a time, or import your staff list.',
          actions: [
            TextButton(
              onPressed: () => cleared = true,
              child: const Text('Add employee'),
            ),
          ],
        ),
      );
      expect(find.text('No employees yet'), findsOneWidget);
      await tester.tap(find.text('Add employee'));
      expect(cleared, isTrue);
    });

    testWidgets('ErrorState shows retry and reference', (tester) async {
      var retried = 0;
      await pumpComponent(
        tester,
        ErrorState(
          message: 'Our server didn’t answer in time.',
          reference: 'req_8a234',
          onRetry: () => retried++,
        ),
      );
      expect(find.text('Reference · req_8a234'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      expect(retried, 1);
    });
  });

  group('LoadingSkeleton', () {
    testWidgets('hidden for the first 300 ms, then shown', (tester) async {
      disableAnimations(tester);
      await pumpComponent(
        tester,
        const LoadingSkeleton(
          label: 'Loading employees',
          child: SkeletonBox(width: 100, height: 10),
        ),
      );
      expect(find.byType(SkeletonBox), findsNothing);
      await tester.pump(const Duration(milliseconds: 310));
      expect(find.byType(SkeletonBox), findsOneWidget);
    });

    testWidgets('announced to screen readers by label', (tester) async {
      final semantics = tester.ensureSemantics();
      disableAnimations(tester);
      await pumpComponent(
        tester,
        const LoadingSkeleton(
          label: 'Loading employees',
          delay: Duration.zero,
          child: SkeletonList(rows: 2),
        ),
      );
      expect(find.bySemanticsLabel('Loading employees'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('shimmer does not run when reduced motion is on', (
      tester,
    ) async {
      disableAnimations(tester);
      await pumpComponent(tester, const SkeletonBox(width: 100, height: 10));
      // Settles immediately only if no animation is looping.
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('AppDataTable', () {
    List<DataRow> rows(int n) => [
      for (var i = 0; i < n; i++)
        DataRow(
          cells: [
            DataCell(Text('Row $i')),
            const DataCell(Text('x')),
            const DataCell(Text('y')),
          ],
        ),
    ];
    const columns = [
      DataColumn(label: Text('EMPLOYEE')),
      DataColumn(label: Text('DEPARTMENT')),
      DataColumn(label: Text('STATUS')),
    ];

    testWidgets(
      'narrow screens scroll the table inside its box, page stays put',
      (tester) async {
        await pumpComponent(
          tester,
          SizedBox(
            width: 350,
            child: AppDataTable(columns: columns, rows: rows(2), minWidth: 720),
          ),
          size: const Size(390, 700),
        );
        expect(tester.takeException(), isNull);
        final scrollable = find.descendant(
          of: find.byType(AppDataTable),
          matching: find.byWidgetPredicate(
            (w) =>
                w is SingleChildScrollView &&
                w.scrollDirection == Axis.horizontal,
          ),
        );
        expect(scrollable, findsOneWidget);
        expect(tester.getSize(find.byType(AppDataTable)).width, 350);
      },
    );

    testWidgets('pagination moves between pages and disables at the ends', (
      tester,
    ) async {
      var first = 0;
      Future<void> pump() => pumpComponent(
        tester,
        StatefulBuilder(
          builder: (context, setState) => SizedBox(
            width: 700,
            child: PaginationBar(
              firstIndex: first,
              pageSize: 10,
              totalCount: 23,
              onPageChanged: (value) => setState(() => first = value),
            ),
          ),
        ),
      );
      await pump();
      expect(find.text('Showing 1–10 of 23'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pump();
      expect(find.text('Showing 11–20 of 23'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pump();
      expect(find.text('Showing 21–23 of 23'), findsOneWidget);
      final next = tester.widget<TextButton>(
        find.ancestor(of: find.text('Next'), matching: find.byType(TextButton)),
      );
      expect(next.onPressed, isNull);
    });

    testWidgets('empty list reads 0–0', (tester) async {
      await pumpComponent(
        tester,
        SizedBox(
          width: 600,
          child: PaginationBar(
            firstIndex: 0,
            pageSize: 10,
            totalCount: 0,
            onPageChanged: (_) {},
          ),
        ),
      );
      expect(find.text('Showing 0–0 of 0'), findsOneWidget);
    });
  });
}
