import 'package:flutter_test/flutter_test.dart';
import 'package:iwms_private_app/core/permissions/app_screens.dart';
import 'package:iwms_private_app/data/models/permission_bundle.dart';

void main() {
  /// [sendsAppScreens] false simulates a backend that predates app-screen
  /// gating: it omits the key entirely, which is what tells the bundle to fall
  /// back to allowing everything. A modern backend always sends the key, even
  /// when the list is empty — and an empty list there means "nothing granted".
  PermissionBundle bundleWith({
    List<String> modules = const [],
    Map<String, List<String>> screens = const {},
    Map<String, dynamic> permissions = const {},
    bool sendsAppScreens = true,
  }) =>
      PermissionBundle.fromApi({
        'permissions': permissions,
        'app_surfaces': const [],
        'app_modules': modules,
        if (sendsAppScreens) 'app_screens': screens,
      });

  group('canSeeScreen', () {
    test('shows a screen the backend granted', () {
      final bundle = bundleWith(
        modules: ['supervisor'],
        screens: {
          'supervisor': [
            AppScreens.supervisorTrips,
            AppScreens.supervisorProfile
          ],
        },
      );
      expect(bundle.canSeeScreen(AppScreens.supervisorTrips), isTrue);
    });

    test('hides a screen the backend did not grant', () {
      final bundle = bundleWith(
        modules: ['supervisor'],
        screens: {
          'supervisor': [AppScreens.supervisorTrips],
        },
      );
      expect(bundle.canSeeScreen(AppScreens.supervisorComplaints), isFalse);
    });

    test('allows everything when the backend sent no screen list', () {
      // An older backend. Hiding the whole app would be a worse failure than
      // showing a screen whose calls then 403 with a clear message.
      final bundle = bundleWith(sendsAppScreens: false);
      expect(bundle.canSeeScreen(AppScreens.supervisorTrips), isTrue);
      expect(bundle.hasScreenData, isFalse);
    });

    test('reports real screen data when granted', () {
      final bundle = bundleWith(
        modules: ['driver'],
        screens: {
          'driver': [AppScreens.driverTrips],
        },
      );
      expect(bundle.hasScreenData, isTrue);
    });
  });

  group('screensFor', () {
    test('returns one app\'s screens in backend order', () {
      final bundle = bundleWith(
        modules: ['driver'],
        screens: {
          'driver': [AppScreens.driverTrips, AppScreens.driverBins],
        },
      );
      expect(bundle.screensFor('driver'),
          [AppScreens.driverTrips, AppScreens.driverBins]);
      expect(bundle.screensFor('supervisor'), isEmpty);
    });
  });

  group('hasPermission', () {
    test('answers from the single shared permission list', () {
      // The same rows that govern the web screen govern the app.
      final bundle = bundleWith(permissions: {
        'schedule-operations': {
          'retrip-requests': ['view', 'add'],
        },
      });
      expect(
        bundle.hasPermission('schedule-operations', 'retrip-requests'),
        isTrue,
      );
      expect(
        bundle.hasPermission('schedule-operations', 'retrip-requests',
            action: 'add'),
        isTrue,
      );
      expect(
        bundle.hasPermission('schedule-operations', 'retrip-requests',
            action: 'delete'),
        isFalse,
      );
    });
  });

  test('round-trips modules and screens through toJson', () {
    final bundle = bundleWith(
      modules: ['supervisor'],
      screens: {
        'supervisor': [AppScreens.supervisorTrips],
      },
    );
    final restored = PermissionBundle.fromApi(bundle.toJson());
    expect(restored.appModules, ['supervisor']);
    expect(restored.canSeeScreen(AppScreens.supervisorTrips), isTrue);
  });
}
