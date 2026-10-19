import 'package:erp_portal/core/responsive/breakpoints.dart';
import 'package:erp_portal/core/responsive/responsive_grid.dart';
import 'package:erp_portal/core/responsive/responsive_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScreenSize.fromWidth', () {
    final cases = <double, ScreenSize>{
      320: ScreenSize.smallMobile,
      374: ScreenSize.smallMobile,
      375: ScreenSize.mobile,
      390: ScreenSize.mobile,
      479: ScreenSize.mobile,
      480: ScreenSize.largeMobile,
      767: ScreenSize.largeMobile,
      768: ScreenSize.tablet,
      1023: ScreenSize.tablet,
      1024: ScreenSize.laptop,
      1439: ScreenSize.laptop,
      1440: ScreenSize.desktop,
      1920: ScreenSize.desktop,
    };
    cases.forEach((width, expected) {
      test('$width px is ${expected.name}', () {
        expect(ScreenSize.fromWidth(width), expected);
      });
    });

    test('phone / tablet / laptop helpers', () {
      expect(ScreenSize.largeMobile.isPhone, isTrue);
      expect(ScreenSize.tablet.isPhone, isFalse);
      expect(ScreenSize.tablet.isTabletOrWider, isTrue);
      expect(ScreenSize.tablet.isLaptopOrWider, isFalse);
      expect(ScreenSize.laptop.isLaptopOrWider, isTrue);
    });
  });

  group(
    'NavLayout.fromWidth (design-system breakpoints, not the guide’s 860)',
    () {
      test('drawer below 768', () {
        expect(NavLayout.fromWidth(320), NavLayout.drawer);
        expect(NavLayout.fromWidth(767), NavLayout.drawer);
      });
      test('rail from 768 to 1023', () {
        expect(NavLayout.fromWidth(768), NavLayout.rail);
        expect(NavLayout.fromWidth(860), NavLayout.rail);
        expect(NavLayout.fromWidth(1023), NavLayout.rail);
      });
      test('sidebar from 1024', () {
        expect(NavLayout.fromWidth(1024), NavLayout.sidebar);
        expect(NavLayout.fromWidth(1920), NavLayout.sidebar);
      });
    },
  );

  group('ResponsivePage.gutterFor', () {
    test('16 on phones, 24 on tablets, 32 from laptop', () {
      expect(ResponsivePage.gutterFor(390), 16);
      expect(ResponsivePage.gutterFor(800), 24);
      expect(ResponsivePage.gutterFor(1280), 32);
    });
  });

  group('ResponsiveGrid.columnsFor', () {
    int columns(double width) => ResponsiveGrid.columnsFor(
      width,
      minItemWidth: 160,
      maxColumns: 4,
      spacing: 12,
    );

    test('never fewer than one column', () => expect(columns(100), 1));
    test('two KPIs fit on a 358 px phone content area', () {
      expect(columns(358), 2);
    });
    test('capped at maxColumns', () => expect(columns(1400), 4));
  });
}
