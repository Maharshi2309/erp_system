import 'package:flutter/material.dart';

import '../../core/responsive/responsive_page.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/page_header.dart';
import '../../core/widgets/state_views.dart';

/// Stand-in for a page a later phase builds. Each phase replaces its
/// pending pages with the real screens.
class PendingScreen extends StatelessWidget {
  const PendingScreen({
    super.key,
    required this.title,
    required this.screenId,
    required this.phase,
    this.standalone = false,
    this.actions = const [],
  });

  final String title;

  /// Design screen ID, e.g. "S30".
  final String screenId;
  final int phase;

  /// True outside the app shell (needs its own Scaffold).
  final bool standalone;

  /// e.g. a sign-out button on pages outside the shell.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final page = ResponsivePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(title: title),
          const SizedBox(height: AppSpacing.xl),
          AppCard(
            child: EmptyState(
              icon: Icons.construction_outlined,
              iconTone: AppColors.warning,
              title: 'Not built yet',
              message:
                  'This page ($screenId) is built in Phase $phase. '
                  'This placeholder appears only until then.',
              actions: actions,
            ),
          ),
        ],
      ),
    );
    return standalone ? Scaffold(body: SafeArea(child: page)) : page;
  }
}
