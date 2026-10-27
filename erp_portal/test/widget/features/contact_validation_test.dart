// D-78: the add employee form reports contact problems in its error list.
import 'package:erp_portal/app/router/route_names.dart';
import 'package:erp_portal/core/utils/validators.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/pump_app.dart';

void main() {
  testWidgets('add employee: invalid mobile, name and emergency contact', (
    tester,
  ) async {
    await pumpStafflineApp(
      tester,
      size: const Size(1440, 2400),
      location: AppRoutes.newEmployee,
    );
    await enter(tester, 'First name', 'P00ja');
    await enter(tester, 'Mobile number', '12345');
    await enter(tester, 'Emergency contact', 'Ravi');
    await tapText(tester, 'Save & send invite');
    expect(
      find.textContaining('Mobile number — ${Validators.mobileMessage}'),
      findsOneWidget,
    );
    expect(
      find.textContaining('First name — ${Validators.nameMessage}'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Emergency contact — Add a name and a 10-digit'),
      findsOneWidget,
    );
  });
}
