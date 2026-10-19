import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Shown for a moment at start-up while a saved session is checked.
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Semantics(
          label: 'Loading Staffline',
          liveRegion: true,
          child: const SizedBox.square(
            dimension: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppColors.primary,
            ),
          ),
        ),
      ),
    );
  }
}
