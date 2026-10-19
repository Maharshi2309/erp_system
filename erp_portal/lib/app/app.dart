import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/failure.dart';
import '../core/theme/app_theme.dart';
import 'config/app_config.dart';
import 'router/app_router.dart';

/// Provider retry policy for the whole app (pass to `ProviderScope.retry`).
/// A `Failure` is a definite answer (wrong code, expired link), so it is
/// never retried automatically; the screen offers "Try again" instead.
Duration? providerRetry(int retryCount, Object error) =>
    error is Failure ? null : ProviderContainer.defaultRetry(retryCount, error);

class StafflineApp extends ConsumerWidget {
  const StafflineApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: AppConfig.appName,
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
