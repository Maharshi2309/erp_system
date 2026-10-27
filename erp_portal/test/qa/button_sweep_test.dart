// D-80: presses every enabled button on the main pages for several roles
// and checks that none of them throws. Dialogs and menus that open are
// closed again before the next press.
@Tags(['sweep'])
library;

import 'package:erp_portal/app/router/app_router.dart';
import 'package:erp_portal/app/router/route_names.dart';
import 'package:erp_portal/core/widgets/app_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/pump_app.dart';
import 'responsive_matrix_test.dart' show pagesByRole;

final _buttons = find.byWidgetPredicate(
  (w) =>
      (w is AppButton && w.onPressed != null) ||
      (w is TextButton && w.onPressed != null) ||
      (w is IconButton && w.onPressed != null) ||
      (w is OutlinedButton && w.onPressed != null) ||
      (w is FilledButton && w.onPressed != null),
);

String _describe(Widget w) => switch (w) {
  AppButton(:final label) => label,
  IconButton(:final tooltip) => tooltip ?? 'icon',
  TextButton(:final child) ||
  OutlinedButton(:final child) ||
  FilledButton(
    :final child,
  ) => child is Text ? (child.data ?? '') : child.runtimeType.toString(),
  _ => w.runtimeType.toString(),
};

const _skip = {'Sign out', 'Open account menu'};

Future<void> _closeOverlays(WidgetTester tester) async {
  final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
  nav.popUntil((r) => r is! PopupRoute);
  await tester.pumpAndSettle();
}

Future<List<String>> _sweep(
  WidgetTester tester,
  ProviderContainer c,
  String page,
) async {
  final problems = <String>[];
  c.read(appRouterProvider).go(page);
  await tester.pumpAndSettle();
  final count = _buttons.evaluate().length;
  for (var i = 0; i < count && i < 40; i++) {
    c.read(appRouterProvider).go(page);
    await tester.pumpAndSettle();
    await _closeOverlays(tester);
    final all = _buttons.evaluate().toList();
    if (i >= all.length) break;
    final w = all[i].widget;
    final name = _describe(w);
    if (_skip.contains(name)) continue;
    final f = find.byWidget(w);
    try {
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f, warnIfMissed: false);
      await tester.pumpAndSettle();
    } on Object catch (e) {
      problems.add('$page · "$name": $e');
    }
    final ex = tester.takeException();
    if (ex != null) problems.add('$page · "$name": $ex');
    await _closeOverlays(tester);
  }
  return problems;
}

void main() {
  for (final who in [owner, branchManager, employee]) {
    testWidgets('every button works for $who', (tester) async {
      final c = await pumpStafflineApp(
        tester,
        signInAs: who,
        size: const Size(1440, 2400),
      );
      final problems = <String>[];
      for (final page in [
        ...pagesByRole[who]!,
        if (who == owner) ...[
          AppRoutes.settingsAttendance,
          AppRoutes.settingsBranding,
          AppRoutes.employeeFields,
          AppRoutes.faceCheck,
          AppRoutes.corrections,
          AppRoutes.attendanceExports,
          AppRoutes.holidayImport,
        ],
      ]) {
        problems.addAll(await _sweep(tester, c, page));
        // A press may have signed out or changed the account: restore.
        if (currentPath(c) == AppRoutes.welcome) {
          await signInDemo(c, who);
          await tester.pumpAndSettle();
        }
      }
      expect(problems, isEmpty, reason: problems.join('\n'));
    }, timeout: const Timeout(Duration(minutes: 15)));
  }
}
