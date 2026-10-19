import 'package:erp_portal/core/widgets/app_button.dart';
import 'package:erp_portal/core/widgets/app_dropdown_field.dart';
import 'package:erp_portal/core/widgets/app_text_field.dart';
import 'package:erp_portal/core/widgets/form_error_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/pump_app.dart';

void main() {
  group('AppButton', () {
    testWidgets('calls onPressed when tapped', (tester) async {
      var taps = 0;
      await pumpComponent(
        tester,
        AppButton(label: 'Save', onPressed: () => taps++),
      );
      await tester.tap(find.text('Save'));
      expect(taps, 1);
    });

    testWidgets('disabled when onPressed is null', (tester) async {
      await pumpComponent(
        tester,
        const AppButton(label: 'Save', onPressed: null),
      );
      final button = tester.widget<TextButton>(find.byType(TextButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('busy shows the busy label, a spinner, and ignores taps', (
      tester,
    ) async {
      var taps = 0;
      await pumpComponent(
        tester,
        AppButton(
          label: 'Save changes',
          busyLabel: 'Saving…',
          busy: true,
          onPressed: () => taps++,
        ),
      );
      expect(find.text('Saving…'), findsOneWidget);
      expect(find.text('Save changes'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.text('Saving…'));
      expect(taps, 0);
    });

    testWidgets('sizes follow the 32 / 40 / 48 px scale', (tester) async {
      for (final size in AppButtonSize.values) {
        await pumpComponent(
          tester,
          AppButton(label: 'Go', size: size, onPressed: () {}),
        );
        expect(tester.getSize(find.byType(TextButton)).height, size.height);
      }
    });

    testWidgets('expand fills the available width', (tester) async {
      await pumpComponent(
        tester,
        SizedBox(
          width: 300,
          child: AppButton(
            label: 'Create account',
            expand: true,
            onPressed: () {},
          ),
        ),
      );
      expect(tester.getSize(find.byType(TextButton)).width, 300);
    });
  });

  group('AppTextField', () {
    testWidgets('shows required marker and announces “required”', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpComponent(
        tester,
        const SizedBox(
          width: 320,
          child: AppTextField(label: 'Branch name', isRequired: true),
        ),
      );
      expect(find.text('Branch name *', findRichText: true), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Branch name, required')),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('error replaces helper text and keeps what was typed', (
      tester,
    ) async {
      final controller = TextEditingController(text: '3942');
      addTearDown(controller.dispose);
      await pumpComponent(
        tester,
        SizedBox(
          width: 320,
          child: AppTextField(
            label: 'PIN code',
            controller: controller,
            helperText: '6 digits',
            errorText: 'PIN codes have 6 digits.',
          ),
        ),
      );
      expect(find.text('PIN codes have 6 digits.'), findsOneWidget);
      expect(find.text('6 digits'), findsNothing);
      expect(controller.text, '3942');
    });

    testWidgets('password toggle shows and hides the text', (tester) async {
      await pumpComponent(
        tester,
        const SizedBox(
          width: 320,
          child: AppTextField(label: 'Password', isPassword: true),
        ),
      );
      bool obscured() =>
          tester.widget<TextField>(find.byType(TextField)).obscureText;
      expect(obscured(), isTrue);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(obscured(), isFalse);
      expect(find.byTooltip('Hide password'), findsOneWidget);
    });

    testWidgets('maxLength limits input', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpComponent(
        tester,
        SizedBox(
          width: 320,
          child: AppTextField(
            label: 'PIN code',
            controller: controller,
            maxLength: 6,
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '39423099');
      expect(controller.text, '394230');
    });
  });

  group('AppDropdownField', () {
    testWidgets('selecting an option reports its value', (tester) async {
      String? picked;
      await pumpComponent(
        tester,
        SizedBox(
          width: 320,
          child: AppDropdownField<String>(
            label: 'Time zone',
            value: 'Asia/Kolkata',
            options: const [
              AppDropdownOption('Asia/Kolkata', 'Asia/Kolkata'),
              AppDropdownOption('Asia/Dubai', 'Asia/Dubai'),
            ],
            onChanged: (value) => picked = value,
          ),
        ),
      );
      await tester.tap(find.text('Asia/Kolkata'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Asia/Dubai').last);
      await tester.pumpAndSettle();
      expect(picked, 'Asia/Dubai');
    });

    testWidgets('shows inline error', (tester) async {
      await pumpComponent(
        tester,
        SizedBox(
          width: 320,
          child: AppDropdownField<String>(
            label: 'Shift',
            value: null,
            hintText: 'Select a shift',
            errorText: 'Choose a shift.',
            options: const [AppDropdownOption('general', 'General')],
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.text('Select a shift'), findsOneWidget);
      expect(find.text('Choose a shift.'), findsOneWidget);
    });
  });

  group('FormErrorSummary', () {
    testWidgets('lists problems and links jump to the field', (tester) async {
      var jumped = false;
      await pumpComponent(
        tester,
        SizedBox(
          width: 400,
          child: FormErrorSummary(
            title: 'Please fix 1 thing below. Nothing you entered was lost.',
            items: [
              FormErrorItem(
                'Enter the branch address.',
                onTap: () => jumped = true,
              ),
            ],
          ),
        ),
      );
      expect(
        find.textContaining('Nothing you entered was lost'),
        findsOneWidget,
      );
      await tester.tap(find.text('Enter the branch address.'));
      expect(jumped, isTrue);
    });
  });
}
