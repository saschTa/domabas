import 'package:domabas/data/server/datasources/preferences_server_data_source.dart';
import 'package:domabas/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'native server setup persists and opens authentication after restart',
    (tester) async {
      const address = String.fromEnvironment('SERVER_TEST_URL');
      expect(
        address,
        isNotEmpty,
        reason:
            'Pass --dart-define=SERVER_TEST_URL with a ready Domabas server.',
      );
      final preferences = SharedPreferencesAsync();
      const key = PreferencesServerDataSource.storageKey;
      final previous = await preferences.getString(key);
      try {
        await preferences.remove(key);
        app.main();
        await tester.pumpAndSettle();
        expect(find.text('Connect to your server'), findsOneWidget);
        await tester.enterText(find.byKey(const Key('serverAddress')), address);
        await tester.ensureVisible(find.byKey(const Key('connectServer')));
        await tester.tap(find.byKey(const Key('connectServer')));
        await tester.pumpAndSettle(const Duration(milliseconds: 100));
        await _waitFor(tester, find.byKey(const Key('authEmail')));
        expect(await preferences.getString(key), address);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        app.main();
        await _waitFor(tester, find.byKey(const Key('authEmail')));
        expect(find.text(address), findsOneWidget);
        expect(find.byKey(const Key('configureServer')), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox());
        if (previous == null) {
          await preferences.remove(key);
        } else {
          await preferences.setString(key, previous);
        }
      }
    },
  );
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 100 && finder.evaluate().isEmpty; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsOneWidget);
}
