import 'package:flutter_test/flutter_test.dart';

import 'package:iwms_private_app/data/models/operator_trip_models.dart';

void main() {
  group('WasteBreakdownEntry.fromJson', () {
    test('parses waste_type and weight_kg', () {
      final entry = WasteBreakdownEntry.fromJson({
        'waste_type': 'Wet Waste',
        'weight_kg': '3.50',
      });
      expect(entry.wasteType, 'Wet Waste');
      expect(entry.weightKg, 3.5);
    });

    test('defaults missing weight to 0, not null/crash', () {
      final entry = WasteBreakdownEntry.fromJson({'waste_type': 'Dry Waste'});
      expect(entry.weightKg, 0);
    });
  });

  group('OperatorTripHouseholdStop.wasteBreakdown', () {
    test('parses the list the backend sends for a collected stop', () {
      final stop = OperatorTripHouseholdStop.fromJson({
        'unique_id': 'DTHC-1',
        'sequence': 1,
        'is_collected': true,
        'status': 'Collected',
        'collected_weight_kg': '1.68',
        'customer': {'unique_id': 'CUS-1', 'name': 'Test Household'},
        'collection_image_url': 'https://example.test/collections/1.jpg',
        'waste_breakdown': [
          {'waste_type': 'Wet Waste', 'weight_kg': 0.54},
          {'waste_type': 'Dry Waste', 'weight_kg': 0.55},
          {'waste_type': 'Mixed Waste', 'weight_kg': 0.59},
        ],
      });

      expect(stop.wasteBreakdown, hasLength(3));
      expect(stop.wasteBreakdown.first.wasteType, 'Wet Waste');
      // The breakdown must sum to the same total already shown elsewhere on
      // the card — a mismatch here would mean the two numbers disagree.
      final sum = stop.wasteBreakdown.fold<double>(0, (s, e) => s + e.weightKg);
      expect(sum, closeTo(stop.collectedWeightKg!, 0.001));
      expect(
        stop.collectionImageUrl,
        'https://example.test/collections/1.jpg',
      );
    });

    test('defaults to an empty list when the backend omits it', () {
      final stop = OperatorTripHouseholdStop.fromJson({
        'unique_id': 'DTHC-2',
        'sequence': 1,
        'is_collected': false,
        'status': 'Pending',
        'customer': {'unique_id': 'CUS-2', 'name': 'Another Household'},
      });
      expect(stop.wasteBreakdown, isEmpty);
    });
  });

  group('OperatorTripToday dev payload fields', () {
    test('parses paged-progress, ward zone, retrip, and plural waste types',
        () {
      final trip = OperatorTripToday.fromJson({
        'assignment_unique_id': 'DTA-1',
        'trip_date': '2026-10-12',
        'status': 'In Progress',
        'scheduled_time': '06:30:00',
        'actual_start_at': '2026-10-12T06:35:00+05:30',
        'collection_type': 'household_collection',
        'ward': {
          'unique_id': 'WARD-1',
          'name': 'Ward 1',
          'zone_name': 'North Zone',
        },
        'waste_types': [
          {'unique_id': 'WT-1', 'name': 'Wet Waste'},
          {'unique_id': 'WT-2', 'name': 'Dry Waste'},
        ],
        'progress': {
          'collected': 20,
          'resolved': 25,
          'postponed': 5,
          'total': 48,
          'completed': false,
        },
        'retrip_request': {
          'unique_id': 'RTR-1',
          'status': 'Pending',
          'pending_household_count': 5,
        },
        'collection_points': const [],
        'household_collections': const [],
      });

      expect(trip.isHousehold, isTrue);
      expect(trip.isStarted, isTrue);
      expect(trip.ward?.zoneName, 'North Zone');
      expect(trip.wasteType.name, 'Wet Waste');
      expect(trip.progress.total, 48);
      expect(trip.progress.postponed, 5);
      expect(trip.hasPendingRetrip, isTrue);
      expect(trip.retripRequest?.pendingHouseholdCount, 5);
    });
  });
}
