import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/app_button.dart';
import '../../core/widgets/state_views.dart';
import 'route_names.dart';

/// Unknown URL (board S96, "Record not found").
class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key, required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ErrorState(
        headline: '404',
        title: 'This page doesn’t exist',
        message: 'The link may be mistyped, or the page has moved.',
        reference: path,
        actions: [
          AppButton(
            label: 'Go to your dashboard',
            onPressed: () => context.go(AppRoutes.root),
          ),
        ],
      ),
    );
  }
}
