import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_brew/screens/maintenance_screen.dart';
import 'package:quick_brew/services/system_maintenance.dart';

void main() {
  group('SystemMaintenanceStatus', () {
    test('normal state is not active', () {
      expect(SystemMaintenanceStatus.normal.isActive, isFalse);
    });

    test('custom status retains active state and message', () {
      const status = SystemMaintenanceStatus(
        isActive: true,
        message: 'System upgrade in progress.',
      );
      expect(status.isActive, isTrue);
      expect(status.message, 'System upgrade in progress.');
    });
  });

  group('MaintenanceScreen', () {
    testWidgets('renders lockout badge, message and refresh control', (tester) async {
      var refreshed = false;
      var bypassed = false;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MaintenanceScreen(
            message: 'Scheduled store server maintenance.',
            onRefresh: () async {
              refreshed = true;
            },
            onAdminBypass: () {
              bypassed = true;
            },
          ),
        ),
      );

      expect(find.text('MAINTENANCE IN PROGRESS'), findsOneWidget);
      expect(find.text('Service Paused'), findsOneWidget);
      expect(find.text('Scheduled store server maintenance.'), findsOneWidget);
      expect(find.text('Check If Back Online'), findsOneWidget);
      expect(find.text('Staff & Admin Sign In'), findsOneWidget);

      await tester.tap(find.text('Check If Back Online'));
      await tester.pump();
      expect(refreshed, isTrue);

      await tester.tap(find.text('Staff & Admin Sign In'));
      await tester.pump();
      expect(bypassed, isTrue);
    });

    testWidgets('pop is disabled to prevent hardware back button bypass', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: MaintenanceScreen(
            message: 'Maintenance ongoing.',
          ),
        ),
      );

      final popScope = tester.widget<PopScope>(find.byType(PopScope));
      expect(popScope.canPop, isFalse);
    });
  });
}
