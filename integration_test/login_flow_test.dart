import 'package:app_enhancement/app.dart';
import 'package:app_enhancement/core/config/supabase_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Defines and runs the tests in this file.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('admin logs in and lands on the home shell', (tester) async {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.anonKey,
    );

    await tester.pumpWidget(const ProviderScope(child: TarumtApp()));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'admin@tarumt.edu.my');
    await tester.enterText(fields.at(1), 'Testing123');
    await tester.pump();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Log in'));

    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }

    final exception = tester.takeException();
    if (exception != null) {
      fail('App threw during login: $exception');
    }

    expect(
      find.text('TARUMT Campus'),
      findsOneWidget,
      reason: 'Expected the home shell app bar after a successful login.',
    );
  });
}
