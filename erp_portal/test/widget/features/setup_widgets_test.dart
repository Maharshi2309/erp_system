import 'dart:typed_data';

import 'package:erp_portal/core/utils/image_picking.dart';
import 'package:erp_portal/features/onboarding/presentation/widgets/image_upload_field.dart';
import 'package:erp_portal/features/organization/domain/branch.dart';
import 'package:erp_portal/features/organization/presentation/widgets/weekly_hours_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/pump_app.dart';

class _FakePicker implements ImagePicking {
  _FakePicker(this.next);

  PickedImage? next;

  @override
  Future<PickedImage?> pickImage() async => next;
}

final _png = Uint8List(64)..setAll(0, [0x89, 0x50, 0x4E, 0x47]);

/// Hosts the editor with real state so edits show up.
class _HoursHost extends StatefulWidget {
  const _HoursHost({required this.onCopied});

  final ValueChanged<String> onCopied;

  @override
  State<_HoursHost> createState() => _HoursHostState();
}

class _HoursHostState extends State<_HoursHost> {
  WeeklyHours hours = HoursPresets.monFri900;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: WeeklyHoursEditor(
      hours: hours,
      onChanged: (h) => setState(() => hours = h),
      onCopied: widget.onCopied,
    ),
  );
}

void main() {
  group('WeeklyHoursEditor', () {
    Future<_HoursHostState> pump(
      WidgetTester tester,
      List<String> copied, {
      Size size = const Size(900, 1400),
    }) async {
      await pumpComponent(tester, _HoursHost(onCopied: copied.add), size: size);
      return tester.state<_HoursHostState>(find.byType(_HoursHost));
    }

    testWidgets('quick fill replaces the week', (tester) async {
      final host = await pump(tester, []);
      await tapText(tester, 'Every day · 10:00–20:00');
      expect(host.hours.every((d) => d.open), isTrue);
      expect(host.hours[6].opensAt, hm(10, 0));
    });

    testWidgets('a day can be closed', (tester) async {
      final host = await pump(tester, []);
      await tester.tap(find.bySemanticsLabel('Open on Monday'));
      await tester.pumpAndSettle();
      expect(host.hours[0].open, isFalse);
    });

    testWidgets('copy Monday to Saturday', (tester) async {
      final copied = <String>[];
      final host = await pump(tester, copied);
      await tapText(tester, 'Copy to…');
      await tapText(tester, 'Sat');
      await tapText(tester, 'Apply to 1 day');
      expect(host.hours[5].open, isTrue);
      expect(host.hours[5].opensAt, host.hours[0].opensAt);
      expect(copied, hasLength(1));
    });

    testWidgets('stacked rows on a phone copy via an icon', (tester) async {
      final host = await pump(tester, [], size: const Size(360, 1600));
      await tester.tap(find.byTooltip('Copy Monday’s hours to…'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Select Mon–Sat');
      await tester.tap(find.textContaining('Apply to').last);
      await tester.pumpAndSettle();
      expect(host.hours[5].open, isTrue);
    });
  });

  group('ImageUploadField', () {
    Future<List<Uint8List?>> pump(
      WidgetTester tester,
      _FakePicker picker,
    ) async {
      final changes = <Uint8List?>[];
      setScreenSize(tester, const Size(600, 300));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [imagePickingProvider.overrideWithValue(picker)],
          child: MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => ImageUploadField(
                  label: 'Logo',
                  image: changes.isEmpty ? null : changes.last,
                  onChanged: (b) => setState(() => changes.add(b)),
                ),
              ),
            ),
          ),
        ),
      );
      return changes;
    }

    testWidgets('accepts a PNG, then removes it', (tester) async {
      final changes = await pump(
        tester,
        _FakePicker(PickedImage(name: 'logo.png', bytes: _png)),
      );
      await tapText(tester, 'Upload');
      expect(changes.single, _png);
      await tapText(tester, 'Remove');
      expect(changes.last, isNull);
    });

    testWidgets('rejects a file that is not an image', (tester) async {
      final changes = await pump(
        tester,
        _FakePicker(PickedImage(name: 'x.png', bytes: Uint8List(64))),
      );
      await tapText(tester, 'Upload');
      expect(changes, isEmpty);
      expect(
        find.text('That file isn’t an image. Use PNG or JPG.'),
        findsOneWidget,
      );
    });

    testWidgets('cancelling the picker changes nothing', (tester) async {
      final changes = await pump(tester, _FakePicker(null));
      await tapText(tester, 'Upload');
      expect(changes, isEmpty);
    });
  });
}
