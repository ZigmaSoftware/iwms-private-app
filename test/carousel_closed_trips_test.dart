import 'package:flutter_test/flutter_test.dart';

import 'package:iwms_private_app/data/models/operator_trip_models.dart';
import 'package:iwms_private_app/modules/module2_driver/presentation/state/trip_sequence.dart';

/// Mirrors `DriverHomePage._tripsForMode`'s rule: the carousel shows only the
/// trips of the selected collection type that are still OPEN.
List<OperatorTripToday> visibleTrips(
  List<OperatorTripToday> trips, {
  required bool household,
}) {
  return trips
      .where((t) => t.isHousehold == household && !t.isClosed)
      .toList();
}

OperatorTripToday _trip({
  required String id,
  String type = 'bin_collection',
  required String time,
  int total = 5,
  int resolved = 0,
  String status = 'Scheduled',
  OperatorTripRetripRequest? retrip,
}) {
  return OperatorTripToday(
    assignmentUniqueId: id,
    tripDate: DateTime(2026, 7, 29),
    status: status,
    collectionType: type,
    scheduledTime: time,
    retripRequest: retrip,
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
  group('isClosed', () {
    test('a Completed assignment is closed', () {
      expect(_trip(id: 'A', time: '06:30:00', status: 'Completed').isClosed,
          isTrue);
    });

    test('an open assignment is not closed', () {
      expect(_trip(id: 'A', time: '06:30:00').isClosed, isFalse);
    });

    test(
        'all stops resolved but NOT ended is finished yet still open — the '
        'driver must keep the card to press End Trip', () {
      final t = _trip(id: 'A', time: '06:30:00', total: 5, resolved: 5);
      expect(t.isFinished, isTrue, reason: 'no work left');
      expect(t.isClosed, isFalse, reason: 'must stay on the carousel');
    });

    test('a Re-Trip-closed source assignment is closed', () {
      // approve_retrip() calls mark_ended() on the source -> Completed.
      final source = _trip(id: 'SRC', time: '06:30:00', status: 'Completed');
      expect(source.isClosed, isTrue);
    });

    test('a PENDING retrip leaves the trip open — collection continues', () {
      final t = _trip(
        id: 'A',
        time: '06:30:00',
        retrip: const OperatorTripRetripRequest(
            uniqueId: 'RT-1', status: 'Pending'),
      );
      expect(t.hasPendingRetrip, isTrue);
      expect(t.isClosed, isFalse);
    });
  });

  group('carousel visibility', () {
    test('drops the completed trip, keeps the open one', () {
      final trips = [
        _trip(id: 'AM', time: '06:30:00', status: 'Completed'),
        _trip(id: 'PM', time: '15:00:00'),
      ];
      final visible = visibleTrips(trips, household: false);
      expect(visible.map((t) => t.assignmentUniqueId), ['PM']);
    });

    test('re-trip: source disappears, continuation remains', () {
      final trips = [
        _trip(id: 'SRC', time: '06:30:00', status: 'Completed'),
        _trip(id: 'CONT', time: '06:30:00'),
      ];
      final visible = visibleTrips(trips, household: false);
      expect(visible.map((t) => t.assignmentUniqueId), ['CONT']);
    });

    test('completing every trip empties the carousel', () {
      final trips = [
        _trip(id: 'AM', time: '06:30:00', status: 'Completed'),
        _trip(id: 'PM', time: '15:00:00', status: 'Completed'),
      ];
      expect(visibleTrips(trips, household: false), isEmpty);
    });

    test('a household trip is unaffected by a closed bin trip', () {
      final trips = [
        _trip(id: 'BIN', time: '06:30:00', status: 'Completed'),
        _trip(id: 'HH', type: 'household_collection', time: '07:00:00'),
      ];
      expect(visibleTrips(trips, household: true).map((t) => t.assignmentUniqueId),
          ['HH']);
      expect(visibleTrips(trips, household: false), isEmpty);
    });
  });

  group('sequencing still works after closed trips are removed', () {
    test('finishing the morning trip UNLOCKS the afternoon one', () {
      final all = [
        _trip(id: 'AM', time: '06:30:00', status: 'Completed'),
        _trip(id: 'PM', time: '15:00:00'),
      ];
      final visible = visibleTrips(all, household: false);
      final blockers = tripBlockers(visible);
      expect(blockers.containsKey('PM'), isFalse,
          reason: 'PM must not stay locked once AM is gone from the list');
      expect(firstWorkableTrip(visible)!.assignmentUniqueId, 'PM');
    });

    test('with three trips, only the next one opens', () {
      final all = [
        _trip(id: 'T1', time: '06:30:00', status: 'Completed'),
        _trip(id: 'T2', time: '12:00:00'),
        _trip(id: 'T3', time: '15:00:00'),
      ];
      final visible = visibleTrips(all, household: false);
      final blockers = tripBlockers(visible);
      expect(blockers.containsKey('T2'), isFalse);
      expect(blockers['T3']!.blockedBy.assignmentUniqueId, 'T2');
      expect(firstWorkableTrip(visible)!.assignmentUniqueId, 'T2');
    });
  });
}
