import 'package:flutter/widgets.dart';

/// Width breakpoints from the design system board (S01).
///
/// The design guide mentions a drawer "below 860 px"; the design-system board
/// wins (see docs/reference_audit.md, D4).
abstract final class Breakpoints {
  static const double mobile = 375;
  static const double largeMobile = 480;
  static const double tablet = 768;
  static const double laptop = 1024;
  static const double desktop = 1440;
}

enum ScreenSize {
  /// 320–374: one column, bottom navigation.
  smallMobile,

  /// 375–479: KPIs two-up, tables become cards.
  mobile,

  /// 480–767: filters move into a drawer.
  largeMobile,

  /// 768–1023: icon rail, two-column forms.
  tablet,

  /// 1024–1439: full sidebar, three to four KPIs per row.
  laptop,

  /// 1440 and wider: content capped at 1360 px.
  desktop;

  static ScreenSize fromWidth(double width) {
    if (width < Breakpoints.mobile) return smallMobile;
    if (width < Breakpoints.largeMobile) return mobile;
    if (width < Breakpoints.tablet) return largeMobile;
    if (width < Breakpoints.laptop) return tablet;
    if (width < Breakpoints.desktop) return laptop;
    return desktop;
  }

  bool get isPhone => index <= largeMobile.index;
  bool get isTabletOrWider => index >= tablet.index;
  bool get isLaptopOrWider => index >= laptop.index;
}

/// How the app shell shows its main navigation.
enum NavLayout {
  /// Below 768 px: top bar with a menu button that opens a drawer.
  drawer,

  /// 768–1023 px: 72 px icon rail that can expand.
  rail,

  /// 1024 px and wider: 248 px sidebar.
  sidebar;

  static NavLayout fromWidth(double width) {
    if (width < Breakpoints.tablet) return drawer;
    if (width < Breakpoints.laptop) return rail;
    return sidebar;
  }
}

extension ResponsiveContext on BuildContext {
  ScreenSize get screenSize =>
      ScreenSize.fromWidth(MediaQuery.sizeOf(this).width);
}
