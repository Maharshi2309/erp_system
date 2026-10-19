import 'package:erp_portal/core/widgets/app_overlays.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/pump_app.dart';

/// A button that runs [onPressed] with a context under the Scaffold.
Widget launcher(void Function(BuildContext) onPressed) => Builder(
  builder: (context) => TextButton(
    onPressed: () => onPressed(context),
    child: const Text('Open'),
  ),
);

void main() {
  group('showConfirmDialog', () {
    Future<bool?> openAndChoose(
      WidgetTester tester,
      Future<void> Function() choose,
    ) async {
      bool? result;
      await pumpComponent(
        tester,
        launcher((context) async {
          result = await showConfirmDialog(
            context,
            title: 'Deactivate Isha Rathod?',
            message: 'History is kept.',
            confirmLabel: 'Deactivate',
            destructive: true,
          );
        }),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Deactivate Isha Rathod?'), findsOneWidget);
      await choose();
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('confirm resolves true', (tester) async {
      final result = await openAndChoose(
        tester,
        () => tester.tap(find.text('Deactivate')),
      );
      expect(result, isTrue);
    });

    testWidgets('cancel resolves false', (tester) async {
      final result = await openAndChoose(
        tester,
        () => tester.tap(find.text('Cancel')),
      );
      expect(result, isFalse);
    });

    testWidgets('Esc resolves false', (tester) async {
      final result = await openAndChoose(
        tester,
        () => tester.sendKeyEvent(LogicalKeyboardKey.escape),
      );
      expect(result, isFalse);
    });
  });

  group('showSidePanel', () {
    Future<void> open(WidgetTester tester, Size size) async {
      await pumpComponent(
        tester,
        launcher(
          (context) => showSidePanel<void>(
            context,
            title: 'Isha Rathod · Casual leave',
            body: (_) => const Text('Mon 19 Oct · 1 day'),
            actions: (context) => [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Approve'),
              ),
            ],
          ),
        ),
        size: size,
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    double panelWidth(WidgetTester tester) => tester
        .getSize(
          find
              .ancestor(
                of: find.text('Mon 19 Oct · 1 day'),
                matching: find.byType(Material),
              )
              .first,
        )
        .width;

    testWidgets('440 px wide on desktop', (tester) async {
      await open(tester, const Size(1280, 800));
      expect(panelWidth(tester), 440);
    });

    testWidgets('full width below 600 px', (tester) async {
      await open(tester, const Size(390, 800));
      expect(panelWidth(tester), 390);
    });

    testWidgets('Esc closes it', (tester) async {
      await open(tester, const Size(1280, 800));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Mon 19 Oct · 1 day'), findsNothing);
    });

    testWidgets('Close button closes it', (tester) async {
      await open(tester, const Size(1280, 800));
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Mon 19 Oct · 1 day'), findsNothing);
    });

    testWidgets('actions run', (tester) async {
      await open(tester, const Size(1280, 800));
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      expect(find.text('Mon 19 Oct · 1 day'), findsNothing);
    });
  });

  testWidgets('showAppToast shows the message and fits a phone', (
    tester,
  ) async {
    await pumpComponent(
      tester,
      launcher((context) => showAppToast(context, 'Owner profile saved')),
      size: const Size(390, 800),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    expect(find.text('Owner profile saved'), findsOneWidget);
    // The visible toast card (the SnackBar widget itself spans the screen).
    final card = find.descendant(
      of: find.byType(SnackBar),
      matching: find.byType(Material),
    );
    expect(tester.getSize(card.first).width, lessThanOrEqualTo(358));
    expect(tester.takeException(), isNull);
  });
}
