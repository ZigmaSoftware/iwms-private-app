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
}
