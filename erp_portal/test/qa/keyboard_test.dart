// Phase 8 QA: the critical forms and overlays work from the keyboard alone.

import 'package:erp_portal/app/router/route_names.dart';
import 'package:erp_portal/core/widgets/focus_ring.dart';
import 'package:erp_portal/features/auth/data/demo_auth_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/pump_app.dart';

Finder input(String label) =>
    find.descendant(of: field(label), matching: find.byType(EditableText));

bool focused(WidgetTester tester, String label) =>
    tester.widget<EditableText>(input(label)).focusNode.hasFocus;

void main() {
  testWidgets('sign-in: Tab moves through the form and Enter submits', (
    tester,
  ) async {
    final c = await pumpStafflineApp(
      tester,
      signInAs: null,
      location: AppRoutes.welcome,
    );
    await tester.enterText(input('Work email or employee ID'), employee);
    expect(focused(tester, 'Work email or employee ID'), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(focused(tester, 'Password'), isTrue, reason: 'Tab goes to password');

    await tester.enterText(input('Password'), DemoAuthRepository.demoPassword);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(currentPath(c), isNot(AppRoutes.welcome), reason: 'Enter signs in');
  });

  testWidgets('keyboard focus is visible on buttons', (tester) async {
    await pumpStafflineApp(tester, signInAs: null, location: AppRoutes.welcome);
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(
      () => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic,
    );
    // Tab until a button has focus; it must sit inside a focus ring.
    var ringed = false;
    for (var i = 0; i < 12 && !ringed; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final ctx = FocusManager.instance.primaryFocus?.context;
      ringed = ctx?.findAncestorWidgetOfExactType<FocusRing>() != null;
    }
    expect(ringed, isTrue);
    expect(FocusManager.instance.highlightMode, FocusHighlightMode.traditional);
  });

  testWidgets('Escape closes a dialog and a side panel', (tester) async {
    await pumpStafflineApp(tester, location: AppRoutes.people);
    final change = find.bySemanticsLabel('Change role of Aarav Bhatt');
    await tester.ensureVisible(change);
    await tester.tap(change);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);

    final c = await pumpStafflineApp(tester, location: AppRoutes.leaveBalances);
    await tester.ensureVisible(find.text('Adjust').first);
    await tester.tap(find.text('Adjust').first);
    await tester.pumpAndSettle();
    expect(find.text('Adjust balance'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Adjust balance'), findsNothing);
    expect(currentPath(c), AppRoutes.leaveBalances);
  });
}
