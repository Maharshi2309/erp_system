// D-76: sign-in and the first page load don't wait on one round trip
// after another. With a simulated 100 ms per call, a chain of sequential
// calls (a "waterfall") shows up as a long simulated wait.
import 'dart:async';

import 'package:erp_portal/app/app.dart';
import 'package:erp_portal/app/config/app_config.dart';
import 'package:erp_portal/app/router/route_names.dart';
import 'package:erp_portal/core/utils/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/pump_app.dart';

const _roundTrip = Duration(milliseconds: 100);

/// Simulated time [work] takes, advancing in 10 ms steps.
Future<Duration> _timed(WidgetTester tester, Future<void> work) async {
  final start = tester.binding.clock.now();
  var done = false;
  unawaited(work.then((_) => done = true));
  while (!done) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  return tester.binding.clock.now().difference(start);
}

void main() {
  for (final (who, home, maxTrips) in [
    (employee, AppRoutes.home, 5),
    (branchManager, AppRoutes.branchDashboard, 3),
  ]) {
    testWidgets('$who signs in and reaches $home without a waterfall', (
      tester,
    ) async {
      setScreenSize(tester, const Size(1440, 900));
      disableAnimations(tester);
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        ProviderScope(
          retry: providerRetry,
          overrides: [
            demoLatencyProvider.overrideWithValue(_roundTrip),
            clockProvider.overrideWithValue(() => designNow),
          ],
          child: const StafflineApp(),
        ),
      );
      await tester.pumpAndSettle();
      final c = ProviderScope.containerOf(
        tester.element(find.byType(StafflineApp)),
      );

      final signIn = await _timed(tester, signInDemo(c, who));
      expect(
        signIn,
        lessThanOrEqualTo(_roundTrip * 4),
        reason: 'sign-in $signIn',
      );

      // Until no loading skeleton is left on the home page.
      final start = tester.binding.clock.now();
      for (var i = 0; i < 300; i++) {
        await tester.pump(const Duration(milliseconds: 10));
        if (i > 5 &&
            find.bySemanticsLabel(RegExp('^Loading')).evaluate().isEmpty) {
          break;
        }
      }
      final load = tester.binding.clock.now().difference(start);
      expect(currentPath(c), home);
      expect(
        load,
        lessThanOrEqualTo(_roundTrip * maxTrips),
        reason: 'first page load took $load',
      );
      // Let background loads (simulated delays) finish before teardown.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  }
}
