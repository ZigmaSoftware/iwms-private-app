import 'package:flutter_test/flutter_test.dart';
import 'package:iwms_private_app/data/models/operator_trip_models.dart';
import 'package:iwms_private_app/data/models/trip_retrip_models.dart';

void main() {
  test('supervisor Re-Trip model parses and formats its deadline', () {
    final request = TripRetripRequest.fromJson({
      'unique_id': 'RETRIP-1',
      'assignment_unique_id': 'DTA-1',
      'status': 'Pending',
      'reason': 'Shift ended',
      'pending_bin_count': 2,
      'pending_household_count': 0,
      'expires_at': '2026-10-14T10:30:00Z',
    });

    expect(request.expiresAt, DateTime.utc(2026, 10, 14, 10, 30));
    expect(
      request.expiryLabel(DateTime.utc(2026, 10, 14, 10, 20)),
      'Expires in 10 min',
    );
  });

  test('driver Re-Trip model reports an elapsed deadline', () {
    final request = OperatorTripRetripRequest.fromJson({
      'unique_id': 'RETRIP-2',
      'status': 'Pending',
      'expires_at': '2026-10-14T10:30:00Z',
    });

    expect(
      request.expiryLabel(DateTime.utc(2026, 10, 14, 10, 31)),
      'Request expired - refresh to continue',
    );
  });
}
