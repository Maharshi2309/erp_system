// D-81: every interactive control on every page each account can open is
// pressed once. A press must not throw, and must not land on Access
// denied, Page not found or an error screen that wasn't there before.
@Tags(['sweep'])
library;

import 'package:erp_portal/app/router/app_router.dart';
import 'package:erp_portal/app/router/not_found_screen.dart';
import 'package:erp_portal/app/router/route_names.dart';
import 'package:erp_portal/core/widgets/app_button.dart';
import 'package:erp_portal/core/widgets/state_views.dart';
import 'package:erp_portal/features/auth/data/demo_auth_repository.dart';
import 'package:erp_portal/features/auth/presentation/providers/auth_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/pump_app.dart';
import 'role_rules_test.dart' show access, roles;

final _controls = find.byWidgetPredicate(
  (w) => switch (w) {
    AppButton(:final onPressed) => onPressed != null,
    ButtonStyleButton(:final onPressed) => onPressed != null,
    IconButton(:final onPressed) => onPressed != null,
    Switch(:final onChanged) => onChanged != null,
    Checkbox(:final onChanged) => onChanged != null,
    InkWell(:final onTap) => onTap != null,
    PopupMenuButton(:final enabled) => enabled,
    _ => false,
  },
);

/// A readable name for a control: its label, tooltip or first text.
String _name(WidgetTester tester, Element e) {
  final w = e.widget;
  if (w is AppButton) return w.label;
  if (w is IconButton && w.tooltip != null) return w.tooltip!;
  final texts = find
      .descendant(of: find.byWidget(w), matching: find.byType(Text))
      .evaluate();
  if (texts.isNotEmpty) {
    final t = texts.first.widget as Text;
    return t.data ?? t.textSpan?.toPlainText() ?? w.runtimeType.toString();
  }
  return w.runtimeType.toString();
}

// Sign-out ends the session; the design gallery shows sample error
// screens on purpose (demo builds only).
const _skip = {'Sign out', 'Open account menu', 'Design system'};

/// Detail pages to sweep besides the menu pages, if the account may open
/// them.
const _extraPages = [
  '/employees/e-13',
  '/employees/e-13/edit',
  '/branches/b-sur',
  '/audit-log/evt_8f2206',
  '/roles/branchManager',
  '/roles/new',
  '/reports/results?report=monthly&from=2026-10-01&to=2026-10-14',
  '/attendance/correct/e-10/2026-10-13',
  '/attendance/missing-punches',
  '/attendance/corrections',
  '/attendance/monthly',
  '/attendance/face-check',
  '/holidays/list',
  '/holidays/schedules',
  '/holidays/import',
  '/settings/notifications',
  '/settings/branding',
  '/settings/schedules',
  '/my/attendance/2026-10-13',
  '/my/leave/apply',
  '/my/leave/history',
  '/my/profile/face',
  '/notifications',
];

Future<void> _closeOverlays(WidgetTester tester) async {
  final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
  nav.popUntil((r) => r is! PopupRoute);
  await tester.pumpAndSettle();
}

bool _errorShown() =>
    find.byType(NotFoundScreen).evaluate().isNotEmpty ||
    find.byType(ErrorState).evaluate().isNotEmpty;

Future<List<String>> _sweep(
  WidgetTester tester,
  ProviderContainer c,
  String page, {
  required Future<void> Function() restore,
  int max = 80,
}) async {
  final problems = <String>[];
  for (var i = 0; i < max; i++) {
    c.read(appRouterProvider).go(page);
    await tester.pumpAndSettle();
    await _closeOverlays(tester);
    final all = _controls.evaluate().toList();
    if (i >= all.length) break;
    final element = all[i];
    final name = _name(tester, element);
    if (_skip.contains(name)) continue;
    final errorBefore = _errorShown();
    final f = find.byWidget(element.widget);
    try {
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f, warnIfMissed: false);
      await tester.pumpAndSettle();
    } on Object catch (e) {
      problems.add('$page · "$name" threw: $e');
    }
    final ex = tester.takeException();
    if (ex != null) problems.add('$page · "$name" threw: $ex');
    final path = currentPath(c);
    if (path == AppRoutes.accessDenied) {
      problems.add('$page · "$name" leads to Access denied');
    } else if (!errorBefore && _errorShown()) {
      problems.add('$page · "$name" leads to an error page ($path)');
    }
    await _closeOverlays(tester);
    await restore();
  }
  return problems;
}

void main() {
  for (final (i, who) in roles.indexed) {
    testWidgets('every control works for $who', (tester) async {
      final c = await pumpStafflineApp(
        tester,
        signInAs: who,
        size: const Size(1440, 2400),
      );
      final org = c.read(sessionProvider)!.organizationId;
      Future<void> restore() async {
        // A press may have signed out or switched organization.
        if (c.read(sessionProvider)?.organizationId != org) {
          await c.read(authControllerProvider.notifier).signOut();
          await tester.pumpAndSettle();
          await signInDemo(c, who);
          await tester.pumpAndSettle();
        }
      }

      final pages = <String>[
        for (final MapEntry(key: page, value: bits) in access.entries)
          if (bits[i] == '1') page,
      ];
      for (final p in _extraPages) {
        c.read(appRouterProvider).go(p);
        await tester.pumpAndSettle();
        if (currentPath(c) == Uri.parse(p).path && !pages.contains(p)) {
          pages.add(p);
        }
      }
      final problems = <String>[];
      for (final p in pages) {
        problems.addAll(await _sweep(tester, c, p, restore: restore));
      }
      expect(problems, isEmpty, reason: problems.join('\n'));
    }, timeout: const Timeout(Duration(minutes: 20)));
  }

  testWidgets(
    'every control works for the platform admin',
    (tester) async {
      final c = await pumpStafflineApp(
        tester,
        signInAs: DemoAuthRepository.platformAdminEmail,
        size: const Size(1440, 2400),
      );
      final problems = <String>[];
      for (final p in [
        AppRoutes.platform,
        AppRoutes.platformOrg('org_meridian-tex'),
      ]) {
        problems.addAll(
          await _sweep(
            tester,
            c,
            p,
            restore: () async {
              if (currentPath(c) == AppRoutes.welcome) {
                await signInDemo(c, DemoAuthRepository.platformAdminEmail);
                await tester.pumpAndSettle();
              }
            },
          ),
        );
      }
      expect(problems, isEmpty, reason: problems.join('\n'));
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  testWidgets(
    'every control works on the signed-out pages',
    (tester) async {
      final c = await pumpStafflineApp(
        tester,
        signInAs: null,
        size: const Size(1440, 2400),
      );
      final problems = <String>[];
      for (final p in [
        AppRoutes.welcome,
        AppRoutes.register,
        AppRoutes.forgotPassword,
        '${AppRoutes.resetPassword}?token=${DemoAuthRepository.demoResetToken}',
        '${AppRoutes.acceptInvite}?token=${DemoAuthRepository.demoInviteToken}',
      ]) {
        problems.addAll(
          await _sweep(
            tester,
            c,
            p,
            restore: () async {
              // Demo sign-in buttons may sign someone in: sign out again.
              if (c.read(sessionProvider) != null) {
                await c.read(authControllerProvider.notifier).signOut();
                await tester.pumpAndSettle();
              }
            },
          ),
        );
      }
      expect(problems, isEmpty, reason: problems.join('\n'));
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
