import 'dart:typed_data';

import 'package:erp_portal/app/app.dart';
import 'package:erp_portal/app/config/app_config.dart';
import 'package:erp_portal/app/router/app_router.dart';
import 'package:erp_portal/core/theme/app_theme.dart';
import 'package:erp_portal/core/utils/clock.dart';
import 'package:erp_portal/core/utils/file_download.dart';
import 'package:erp_portal/features/auth/data/demo_auth_repository.dart';
import 'package:erp_portal/features/auth/domain/auth_state.dart';
import 'package:erp_portal/features/auth/presentation/providers/auth_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The design boards' moment: Wednesday 14 October 2026, 14:10.
/// (08:40 UTC = 14:10 in Asia/Kolkata.)
final designNow = DateTime.utc(2026, 10, 14, 8, 40);

/// Captures files the app offers for download.
class FakeDownloads implements FileDownloads {
  final saved = <(String, Uint8List)>[];

  /// Tests set this to simulate the person cancelling the save dialog.
  bool cancel = false;

  /// Tests set this to simulate a file that can't be written.
  bool fail = false;

  @override
  Future<bool> save(
    String fileName,
    Uint8List bytes, {
    required String mimeType,
  }) async {
    if (fail) throw StateError('disk full');
    if (cancel) return false;
    saved.add((fileName, bytes));
    return true;
  }
}

/// Downloads from the most recent [pumpStafflineApp].
FakeDownloads downloads = FakeDownloads();

const owner = 'ankit@meridiantex.in';
const hrAdmin = 'hetal.s@meridiantex.in';
const branchManager = 'jignesh.p@meridiantex.in';
const attendanceManager = 'mitesh.r@meridiantex.in';
const leaveApprover = 'aarav.b@meridiantex.in';
const employee = 'EMP-0229';

/// Sets the logical screen size for one test (device pixel ratio 1).
void setScreenSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Turns on "reduce motion" so looping animations (skeleton shimmer) stop
/// and `pumpAndSettle` can finish.
void disableAnimations(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

/// Pumps the whole app with a zero-latency demo backend and empty browser
/// storage. Signs in as [signInAs] (null stays on the welcome page), then
/// navigates to [location].
Future<ProviderContainer> pumpStafflineApp(
  WidgetTester tester, {

  /// Null keeps the real window (integration tests on a device).
  Size? size = const Size(1440, 900),
  String? signInAs = owner,
  String? location,
  Map<String, Object> storedPrefs = const {},
  List<Override> overrides = const [],
}) async {
  if (size != null) setScreenSize(tester, size);
  disableAnimations(tester);
  downloads = FakeDownloads();
  SharedPreferences.setMockInitialValues(storedPrefs);
  await tester.pumpWidget(
    ProviderScope(
      // A new key each call: a fresh container, even when one test pumps
      // the app several times.
      key: UniqueKey(),
      retry: providerRetry,
      overrides: [
        demoLatencyProvider.overrideWithValue(Duration.zero),
        clockProvider.overrideWithValue(() => designNow),
        fileDownloadsProvider.overrideWithValue(downloads),
        ...overrides,
      ],
      child: const StafflineApp(),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(StafflineApp)),
  );
  if (signInAs != null) {
    await signInDemo(container, signInAs);
    await tester.pumpAndSettle();
  }
  if (location != null) {
    container.read(appRouterProvider).go(location);
    await tester.pumpAndSettle();
  }
  return container;
}

/// Completes the whole sign-in journey for a demo account: password,
/// two-step code if asked, and the last-used organization if asked.
Future<void> signInDemo(ProviderContainer container, String identifier) async {
  final auth = container.read(authControllerProvider.notifier);
  await auth.signIn(
    identifier: identifier,
    password: DemoAuthRepository.demoPassword,
    keepSignedIn: false,
  );
  if (container.read(authControllerProvider) is AwaitingTwoStep) {
    await auth.verifyTwoStep(
      code: DemoAuthRepository.demoAuthenticatorCode,
      isBackupCode: false,
      trustDevice: false,
    );
  }
  final state = container.read(authControllerProvider);
  if (state is AwaitingOrganizationChoice) {
    final last = state.memberships.firstWhere((m) => m.lastUsed);
    await auth.chooseOrganization(last.organizationId);
  }
}

/// Pumps a single component inside the app theme.
Future<void> pumpComponent(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(800, 600),
}) async {
  setScreenSize(tester, size);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

/// Current router location (path only).
String currentPath(ProviderContainer container) =>
    container.read(appRouterProvider).routeInformationProvider.value.uri.path;

/// Current router location with query.
Uri currentUri(ProviderContainer container) =>
    container.read(appRouterProvider).routeInformationProvider.value.uri;

/// A form field by the start of its accessible label.
Finder field(String label) => find.bySemanticsLabel(RegExp('^$label'));

Future<void> enter(WidgetTester tester, String label, String text) async {
  await tester.enterText(
    find
        .descendant(of: field(label), matching: find.byType(EditableText))
        .first,
    text,
  );
  await tester.pump();
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).last);
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

/// Clears toasts so they don't cover bottom action bars.
Future<void> dismissToasts(WidgetTester tester) async {
  for (final messenger in tester.stateList<ScaffoldMessengerState>(
    find.byType(ScaffoldMessenger),
  )) {
    messenger.removeCurrentSnackBar();
  }
  await tester.pumpAndSettle();
}

/// Sets an [AppDateField] through the picker's text input.
Future<void> pickDate(
  WidgetTester tester,
  String label,
  String mmddyyyy,
) async {
  await tester.ensureVisible(find.bySemanticsLabel(RegExp('^$label')).first);
  await tester.tap(find.bySemanticsLabel(RegExp('^$label')).first);
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.edit_outlined).last);
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).last, mmddyyyy);
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

/// Switches the signed-in account, keeping the same demo backend.
Future<void> switchTo(
  WidgetTester tester,
  ProviderContainer c,
  String account, {
  String? location,
}) async {
  await c.read(authControllerProvider.notifier).signOut();
  await tester.pumpAndSettle();
  await signInDemo(c, account);
  await tester.pumpAndSettle();
  if (location != null) {
    c.read(appRouterProvider).go(location);
    await tester.pumpAndSettle();
  }
}
