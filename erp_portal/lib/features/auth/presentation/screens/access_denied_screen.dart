import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/app_destinations.dart';
import '../../../../app/router/route_names.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/responsive/responsive_page.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_overlays.dart';
import '../providers/auth_providers.dart';

/// Board S72 — shown inside the member's own shell when they open a page
/// their role doesn't cover. Says who to ask.
class AccessDeniedScreen extends ConsumerStatefulWidget {
  const AccessDeniedScreen({super.key, this.from});

  /// The page that was refused.
  final String? from;

  @override
  ConsumerState<AccessDeniedScreen> createState() => _AccessDeniedScreenState();
}

class _AccessDeniedScreenState extends ConsumerState<AccessDeniedScreen> {
  bool _busy = false;
  bool _requested = false;

  Future<void> _requestAccess() async {
    setState(() => _busy = true);
    try {
      final owner = await ref
          .read(authControllerProvider.notifier)
          .requestAccess(widget.from ?? '');
      if (!mounted) return;
      setState(() => _requested = true);
      showAppToast(context, 'Request sent to $owner.');
    } on Failure catch (failure) {
      if (mounted) {
        showAppToast(context, failure.message, icon: Icons.error_outline);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    if (session == null) return const SizedBox.shrink();
    final page = widget.from == null
        ? null
        : bestMatch(widget.from!, allDestinations)?.label;
    final covers = session.scopeLabel.isEmpty
        ? 'doesn’t include it'
        : 'covers ${session.scopeLabel}';

    return ResponsivePage(
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          margin: const EdgeInsets.only(top: AppSpacing.xxl),
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: AppColors.neutralSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_outline,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Semantics(
                header: true,
                child: const Text(
                  'You don’t have access to this page',
                  style: AppTypography.sectionTitle,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${page ?? 'This page'} is managed by the organization owner. '
                'Your role, ${session.roleName}, $covers.',
                style: AppTypography.bodySecondary,
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  AppButton(
                    label: 'Go to your dashboard',
                    onPressed: () => context.go(AppRoutes.root),
                  ),
                  AppButton(
                    label: _requested
                        ? 'Request sent'
                        : 'Ask the owner for access',
                    busyLabel: 'Sending…',
                    busy: _busy,
                    variant: AppButtonVariant.secondary,
                    onPressed: _requested ? null : _requestAccess,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              const Divider(),
              const SizedBox(height: AppSpacing.md),
              const Text(
                'If you followed a link someone shared, they may have more '
                'access than you. Reference 403.',
                style: AppTypography.helper,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
