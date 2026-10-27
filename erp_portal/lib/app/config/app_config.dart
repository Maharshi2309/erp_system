import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Build-time configuration, set with `--dart-define`.
@immutable
class AppConfig {
  const AppConfig({required this.showDevTools});

  factory AppConfig.fromEnvironment() => const AppConfig(
    showDevTools: bool.fromEnvironment('SHOW_DEV_TOOLS', defaultValue: true),
  );

  static const appName = 'Staffline';

  /// Design-system gallery, demo-role switcher and "not built yet" pages.
  /// Turn off with `--dart-define=SHOW_DEV_TOOLS=false`.
  final bool showDevTools;
}

final appConfigProvider = Provider<AppConfig>(
  (ref) => AppConfig.fromEnvironment(),
);

/// Simulated network delay for the in-memory demo repositories, so busy
/// states are visible. About one fast server round trip (D-76); tests
/// override it with `Duration.zero`.
final demoLatencyProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 150),
);
