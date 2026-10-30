import 'package:flutter_test/flutter_test.dart';
import 'package:iwms_private_app/core/api_config.dart';

void main() {
  group('ApiConfig dev branch contract', () {
    test('uses the current staff and master routers', () {
      expect(ApiConfig.users, contains('/staff-creations/staffcreation/'));
      expect(ApiConfig.registerStaffFcmToken,
          contains('/staff-creations/staffcreation/register-fcm-token/'));
      expect(ApiConfig.zones, contains('/masters/zones/'));

      for (final url in [
        ApiConfig.users,
        ApiConfig.registerStaffFcmToken,
        ApiConfig.zones,
      ]) {
        expect(url, isNot(contains('/user-creation/')));
        expect(url, isNot(contains('/users-creation/')));
        expect(url, isNot(contains('/hierarchy-nodes/')));
      }
    });

    test('keeps trip plan stops on the route-backed trip-plan surface', () {
      expect(ApiConfig.tripRoutePlans, contains('/schedule-setup/trip-plans/'));
      expect(
          ApiConfig.tripPlannedStops, contains('/schedule-setup/trip-plans/'));
      expect(ApiConfig.tripPlannedStops,
          isNot(contains('/schedule-masters/trip-plan-collection-points/')));
    });

    test('exposes mobile operator lifecycle, paging, and delay endpoints', () {
      expect(ApiConfig.operatorMyTripsToday,
          contains('/operator-mobile/my-trips-today/'));
      expect(ApiConfig.operatorTripStops,
          contains('/operator-mobile/trip-stops/'));
      expect(ApiConfig.operatorTripStart('A-1'),
          endsWith('/operator-mobile/trip-lifecycle/A-1/start/'));
      expect(ApiConfig.operatorTripEnd('A-1'),
          endsWith('/operator-mobile/trip-lifecycle/A-1/end/'));
      expect(ApiConfig.tripDelayReports,
          contains('/schedule-operations/trip-delay-reports/'));
    });
  });
}
