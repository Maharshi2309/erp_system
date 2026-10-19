/// Spacing, radius and layout tokens from the design system (board S01).
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 40;
}

abstract final class AppRadius {
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 12;
  static const double pill = 999;
}

abstract final class AppLayout {
  static const double sidebarWidth = 248;
  static const double railWidth = 72;
  static const double headerHeight = 64;
  static const double contentMaxWidth = 1360;
  static const double touchTarget = 44;
  static const double fieldHeight = 44;
  static const double tableRowHeight = 52;
  static const double dialogWidth = 440;
  static const double dialogWidthWide = 640;
  static const double sidePanelWidth = 440;

  /// Below this width side panels take the full screen width.
  static const double sidePanelFullWidthBelow = 600;
}
