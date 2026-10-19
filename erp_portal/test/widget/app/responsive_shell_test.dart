import 'package:erp_portal/app/router/route_names.dart';
import 'package:erp_portal/app/shell/side_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/pump_app.dart';

/// The Phase 8 matrix, plus the 768 / 1023 / 1024 boundaries.
const sizes = <Size>[
  Size(320, 568),
  Size(375, 667),
  Size(390, 844),
  Size(430, 932),
  Size(767, 1024),
  Size(768, 1024),
  Size(1023, 768),
  Size(1024, 768),
  Size(1280, 800),
  Size(1440, 900),
  Size(1920, 1080),
];

enum Expected { drawer, rail, sidebar }

Expected expectedFor(double width) => width < 768
    ? Expected.drawer
    : (width < 1024 ? Expected.rail : Expected.sidebar);

void main() {
  for (final size in sizes) {
    final expected = expectedFor(size.width);
    testWidgets(
      '${size.width.toInt()}×${size.height.toInt()} uses the ${expected.name} '
      'and nothing overflows',
      (tester) async {
        await pumpStafflineApp(tester, size: size);
        // Layout overflow errors would fail the test here.
        expect(tester.takeException(), isNull);

        final menuButton = find.byTooltip('Open navigation');
        final expandButton = find.byTooltip('Expand menu');
        switch (expected) {
          case Expected.drawer:
            expect(menuButton, findsOneWidget);
            expect(find.byType(SideNav), findsNothing);
            await tester.tap(menuButton);
            await tester.pumpAndSettle();
            expect(find.byType(SideNav), findsOneWidget);
            expect(find.text('Employees'), findsOneWidget);
          case Expected.rail:
            expect(menuButton, findsNothing);
            expect(expandButton, findsOneWidget);
            expect(tester.getSize(find.byType(SideNav)).width, 72);
            // Labels live in tooltips on the rail.
            expect(find.byTooltip('Employees'), findsOneWidget);
          case Expected.sidebar:
            expect(menuButton, findsNothing);
            expect(expandButton, findsNothing);
            expect(tester.getSize(find.byType(SideNav)).width, 248);
            expect(find.text('Employees'), findsOneWidget);
        }
      },
    );
  }

  testWidgets('rail expands to the full sidebar and collapses again', (
    tester,
  ) async {
    await pumpStafflineApp(tester, size: const Size(800, 1024));
    await tester.tap(find.byTooltip('Expand menu'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(SideNav)).width, 248);
    expect(find.text('Employees'), findsOneWidget);
    await tester.tap(find.byTooltip('Collapse menu'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(SideNav)).width, 72);
  });

  testWidgets('choosing a page from the drawer navigates and closes it', (
    tester,
  ) async {
    await pumpStafflineApp(tester, size: const Size(390, 844));
    await tester.tap(find.byTooltip('Open navigation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Attendance'));
    await tester.pumpAndSettle();
    expect(find.byType(SideNav), findsNothing);
    expect(find.text('Attendance overview'), findsOneWidget);
  });

  testWidgets('200% text on a 390 px phone still lays out without overflow', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpStafflineApp(tester, size: const Size(390, 844));
    expect(tester.takeException(), isNull);
  });

  testWidgets('gallery at 200% text on a 390 px phone has no overflow', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpStafflineApp(
      tester,
      size: const Size(390, 844),
      location: AppRoutes.designSystem,
    );
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -40000),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  group('design-system gallery renders at every size', () {
    for (final size in sizes) {
      testWidgets('${size.width.toInt()} px', (tester) async {
        await pumpStafflineApp(
          tester,
          size: size,
          location: AppRoutes.designSystem,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Design system'), findsWidgets);
        // Scroll to the bottom so every section is laid out.
        await tester.drag(
          find.byType(SingleChildScrollView).first,
          const Offset(0, -20000),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Dialogs, side panel and toast'), findsOneWidget);
      });
    }
  });
}
