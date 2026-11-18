import 'package:domabas/ui/glacier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'followup_contract_test.dart' show openDesktopFollowup, settleFollowup;

void main() {
  testWidgets(
    'inline settings toggle without routing and retain selected leaf',
    (tester) async {
      await openDesktopFollowup(tester);
      final admin = find.byKey(const ValueKey('navigation-trigger-admin'));
      await tester.tap(admin);
      await settleFollowup(tester);
      expect(find.byType(GlacierSettingsOverview), findsNothing);
      expect(find.byType(GlacierDialog), findsNothing);
      expect(
        tester.widget<GlacierWorkspace>(find.byType(GlacierWorkspace)).selected,
        'documents-grid',
      );
      final workload = find.byKey(
        const ValueKey('navigation-trigger-settings-workload'),
      );
      await tester.tap(workload);
      await settleFollowup(tester);
      expect(find.byType(GlacierSettingsHeader), findsOneWidget);
      expect(workload, findsOneWidget);
      expect(find.byType(GlacierWorkloadResource), findsWidgets);
      expect(
        tester.widget<GlacierWorkspace>(find.byType(GlacierWorkspace)).selected,
        'settings-workload',
      );
      await tester.tap(admin);
      await settleFollowup(tester);
      expect(workload, findsNothing);
      expect(
        tester.widget<GlacierWorkspace>(find.byType(GlacierWorkspace)).selected,
        'settings-workload',
      );
      await tester.tap(admin);
      await settleFollowup(tester);
      expect(workload, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
