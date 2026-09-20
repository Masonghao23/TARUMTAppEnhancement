import 'package:app_enhancement/app.dart';
import 'package:app_enhancement/core/config/supabase_config.dart';
import 'package:app_enhancement/features/parking/presentation/book_slot_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Pumps the widget tree until the condition is met or the step limit is reached.
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration step = const Duration(milliseconds: 300),
  int maxSteps = 60,
}) async {
  for (var i = 0; i < maxSteps; i++) {
    if (condition()) return;
    await tester.pump(step);
  }
}

/// Waits for a parking slot tile and invokes its tap callback.
Future<void> _tapSlotTile(
  WidgetTester tester,
  String label, {
  Finder? within,
}) async {
  final labelFinder = within == null
      ? find.text(label)
      : find.descendant(of: within, matching: find.text(label));
  await _pumpUntil(tester, () => labelFinder.evaluate().isNotEmpty);
  await tester.pump(const Duration(milliseconds: 300));
  final tile = find.ancestor(of: labelFinder, matching: find.byType(InkWell));
  tester.widget<InkWell>(tile).onTap!();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Defines and runs the tests in this file.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'admin sees an already-active session, books a future day, and toggles '
    'a slot non-reservable',
    (tester) async {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        publishableKey: SupabaseConfig.anonKey,
      );

      await tester.pumpWidget(const ProviderScope(child: TarumtApp()));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'admin@tarumt.edu.my');
      await tester.enterText(fields.at(1), 'Testing123');
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Log in'));

      await _pumpUntil(tester, () => find.text('Parking').evaluate().isNotEmpty);
      expect(tester.takeException(), isNull, reason: 'Login should not throw.');

      await tester.tap(find.text('Parking').first);
      await _pumpUntil(
        tester,
        () => find.textContaining('slots available').evaluate().isNotEmpty,
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'Parking dashboard should load without throwing.',
      );
      expect(find.textContaining('slots available'), findsOneWidget);
      expect(find.textContaining('view only'), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      await _pumpUntil(tester, () => find.text('A05').evaluate().isNotEmpty);
      await tester.tap(find.text('A05'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byType(BookSlotScreen),
        findsNothing,
        reason: 'Tapping a slot on today\'s view-only dashboard must not open booking.',
      );

      await _pumpUntil(
        tester,
        () => find.textContaining('Active session at A05').evaluate().isNotEmpty,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.textContaining('Active session at A05'));
      await _pumpUntil(tester, () => find.text('Finish').evaluate().isNotEmpty);
      expect(find.text('Finish'), findsOneWidget);
      expect(find.text('Extend'), findsOneWidget);
      expect(find.textContaining('PARKING A05'), findsOneWidget);

      await tester.pageBack();
      await _pumpUntil(
        tester,
        () => find.text('Reserve parking').evaluate().isNotEmpty,
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'Navigating back should return to the dashboard.',
      );
      expect(find.text('Reserve parking'), findsOneWidget);

      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Reserve parking'),
          )
          .onPressed!();
      await tester.pump();
      await _pumpUntil(
        tester,
        () => find.byType(BookSlotScreen).evaluate().isNotEmpty,
      );
      final bookingScreen = find.byType(BookSlotScreen);
      expect(
        find.descendant(
          of: bookingScreen,
          matching: find.textContaining('at least 1 day in advance'),
        ),
        findsOneWidget,
      );
      await _pumpUntil(
        tester,
        () => find
            .descendant(of: bookingScreen, matching: find.text('A03'))
            .evaluate()
            .isNotEmpty,
      );
      expect(tester.takeException(), isNull);

      final testPlate = 'TU${DateTime.now().millisecondsSinceEpoch}';
      if (find.text(testPlate).evaluate().isEmpty) {
        await tester.tap(find.widgetWithText(TextButton, 'Add vehicle'));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.enterText(
          find.widgetWithText(TextField, 'Plate number'),
          testPlate,
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Add'));
        await _pumpUntil(
          tester,
          () => find.text(testPlate).evaluate().isNotEmpty,
        );
        expect(tester.takeException(), isNull, reason: 'Adding a vehicle should not throw.');
      }

      await _tapSlotTile(tester, 'A03', within: bookingScreen);

      tester
          .widget<ElevatedButton>(
            find.descendant(
              of: bookingScreen,
              matching: find.byType(ElevatedButton),
            ),
          )
          .onPressed!();
      await tester.pump();
      await _pumpUntil(
        tester,
        () => find.byType(BookSlotScreen).evaluate().isEmpty,
        maxSteps: 200,
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'Booking a future day should succeed and return to the dashboard.',
      );
      expect(find.text('Reserve parking'), findsOneWidget);
      expect(find.text('Finish'), findsNothing);

      await _pumpUntil(
        tester,
        () => find.byTooltip('Manage slots').evaluate().isNotEmpty,
      );
      await tester.tap(find.byTooltip('Manage slots'));
      await tester.pump(const Duration(milliseconds: 300));

      await _tapSlotTile(tester, 'A04');
      await _pumpUntil(
        tester,
        () => find.textContaining('non-reservable').evaluate().isNotEmpty,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await _pumpUntil(
        tester,
        () => find.textContaining('A04 updated').evaluate().isNotEmpty,
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'Marking a slot non-reservable should not throw.',
      );

      await _tapSlotTile(tester, 'A04');
      await _pumpUntil(
        tester,
        () => find.textContaining('reservable again').evaluate().isNotEmpty,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await _pumpUntil(
        tester,
        () => find.textContaining('A04 updated').evaluate().isNotEmpty,
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'Re-enabling a slot should not throw.',
      );
    },
  );
}
