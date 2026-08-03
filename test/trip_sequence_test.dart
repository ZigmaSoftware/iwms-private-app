import 'package:flutter_test/flutter_test.dart';

import 'package:iwms_citizen_app/data/models/operator_trip_models.dart';
import 'package:iwms_citizen_app/modules/module2_driver/presentation/state/trip_sequence.dart';

/// A trip with just the fields sequencing reads.
OperatorTripToday _trip({
  required String id,
  required String type,
  required String time,
  int total = 5,
  int resolved = 0,
  String status = 'Scheduled',
}) {
  return OperatorTripToday(
    assignmentUniqueId: id,
    tripDate: DateTime(2026, 7, 29),
    status: status,
    collectionType: type,
    scheduledTime: time,
    wasteType: const OperatorTripWasteType(uniqueId: 'WT-1', name: 'Organic'),
    progress: OperatorTripProgress(
      collected: resolved,
      total: total,
      resolved: resolved,
      completed: total > 0 && resolved == total,
    ),
    collectionPoints: const [],
  );
}

void main() {
  group('tripBlockers', () {
    test('locks the later same-type trip until the earlier one is finished', () {
      final trips = [
        _trip(id: 'AM', type: 'bin_collection', time: '06:30:00'),
        _trip(id: 'PM', type: 'bin_collection', time: '15:00:00'),
      ];

      final blockers = tripBlockers(trips);

      expect(blockers.containsKey('AM'), isFalse);
      expect(blockers['PM']!.blockedBy.assignmentUniqueId, 'AM');
      expect(blockers['PM']!.message, contains('06:30'));
    });

    test('unlocks the later trip once the earlier one is fully resolved', () {
      final trips = [
        _trip(
            id: 'AM',
            type: 'bin_collection',
            time: '06:30:00',
            total: 5,
            resolved: 5),
        _trip(id: 'PM', type: 'bin_collection', time: '15:00:00'),
      ];

      expect(tripBlockers(trips), isEmpty);
      expect(firstWorkableTrip(trips)!.assignmentUniqueId, 'PM');
    });

    test('a Completed status finishes a trip even with stops outstanding', () {
      final trips = [
        _trip(
            id: 'AM',
            type: 'bin_collection',
            time: '06:30:00',
            resolved: 2,
            status: 'Completed'),
        _trip(id: 'PM', type: 'bin_collection', time: '15:00:00'),
      ];

      expect(tripBlockers(trips), isEmpty);
    });

    test('different collection types never block each other', () {
      final trips = [
        _trip(id: 'BIN', type: 'bin_collection', time: '06:30:00'),
        _trip(id: 'HH', type: 'household_collection', time: '06:30:00'),
      ];

      expect(tripBlockers(trips), isEmpty);
    });

    test('a third same-type trip points at the live trip, not the middle one',
        () {
      final trips = [
        _trip(id: 'T1', type: 'bin_collection', time: '06:30:00'),
        _trip(id: 'T2', type: 'bin_collection', time: '12:00:00'),
        _trip(id: 'T3', type: 'bin_collection', time: '15:00:00'),
      ];

      final blockers = tripBlockers(trips);

      expect(blockers['T2']!.blockedBy.assignmentUniqueId, 'T1');
      // T3 must not tell the driver to finish T2 — T2 is locked too.
      expect(blockers['T3']!.blockedBy.assignmentUniqueId, 'T1');
    });

    test('a single trip of a type is never locked', () {
      final trips = [_trip(id: 'ONLY', type: 'bin_collection', time: '06:30:00')];
      expect(tripBlockers(trips), isEmpty);
      expect(firstWorkableTrip(trips)!.assignmentUniqueId, 'ONLY');
    });

    test('firstWorkableTrip skips finished trips', () {
      final trips = [
        _trip(
            id: 'AM',
            type: 'bin_collection',
            time: '06:30:00',
            total: 3,
            resolved: 3),
        _trip(id: 'PM', type: 'bin_collection', time: '15:00:00'),
      ];
      expect(firstWorkableTrip(trips)!.assignmentUniqueId, 'PM');
    });
  });
}
