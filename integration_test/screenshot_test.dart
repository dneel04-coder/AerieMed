// Generates App Store screenshots by driving the real app on a booted iOS
// Simulator (run via `flutter drive`, see test_driver/integration_test.dart
// for how each screenshot gets saved to disk). Seeds SharedPreferences with
// an already-logged-in, already-unlocked profile so the run never touches
// the real login/access-code/paywall flow or needs real credentials --
// everything else (Protocols, Team data, etc.) still comes from the live
// Supabase backend, so screenshots reflect real app behavior.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:resqruck/main.dart' as app;

/// Waits a fixed wall-clock duration rather than tester.pumpAndSettle(),
/// which throws if any infinite animation (e.g. a loading CircularProgress
/// Indicator while Supabase data is in flight) is still running -- exactly
/// the situation most of these screens are in right after navigation.
Future<void> _wait(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture App Store screenshots', (tester) async {
    SharedPreferences.setMockInitialValues({
      'profile_logged_in': true,
      'profile_access_validated': true,
      'profile_purchase_unlocked': true,
      'profile_name': 'Demo User',
      'profile_callsign': 'DEMO',
      'profile_cert_level': 'EMT-P',
      'tac_user_id': 'screenshot-demo-device',
      'tac_callsign': 'DEMO',
    });

    app.main();
    await _wait(tester, const Duration(seconds: 6));
    await binding.takeScreenshot('01_home');

    // Decision Trees list -- shows the newly-fixed citation banner.
    await tester.tap(find.text('Decision Tree'));
    await _wait(tester, const Duration(seconds: 2));
    await binding.takeScreenshot('02_decision_trees');

    // Into one tree -- shows the citation banner now present on the step
    // screen too, plus the actual clinical-decision-support UI.
    await tester.tap(find.text('MARCH Protocol'));
    await _wait(tester, const Duration(seconds: 2));
    await binding.takeScreenshot('03_march_protocol');

    // Back to home.
    await tester.tap(find.byTooltip('Back'));
    await _wait(tester, const Duration(seconds: 1));
    await tester.pageBack();
    await _wait(tester, const Duration(seconds: 1));

    // Protocols.
    await tester.tap(find.text('Protocols'));
    await _wait(tester, const Duration(seconds: 3));
    await binding.takeScreenshot('04_protocols');
  });
}
