import 'package:flutter_test/flutter_test.dart';

import 'package:iwms_private_app/data/models/operator_trip_models.dart';
import 'package:iwms_private_app/modules/module2_driver/presentation/widgets/trip_completion_nudge.dart';

/// A trip with just the fields the nudge logic reads.
///
/// [postponed] is passed straight through to `progress.postponed` — that
/// field is server-computed (see `get_progress` in
/// `trip_today_serializer.py`) precisely because `collectionPoints`/
/// `householdCollections` only ever hold the FIRST PAGE of stops once a trip
/// has more than `STOPS_PAGE_SIZE` (20) of them, so `postponedStopCount`
/// cannot count them locally any more.
OperatorTripToday _trip({
  required int total,
  required int resolved,
  required int collected,
  int postponed = 0,
  String status = 'In Progress',
}) {
  return OperatorTripToday(
    assignmentUniqueId: 'TRIP-1',
    tripDate: DateTime(2026, 9, 1),
    status: status,
    collectionType: 'bin_collection',
    wasteType: const OperatorTripWasteType(uniqueId: 'WT-1', name: 'Organic'),
    progress: OperatorTripProgress(
      collected: collected,
      total: total,
      resolved: resolved,
      postponed: postponed,
      completed: total > 0 && collected == total,
    ),
    collectionPoints: const [],
    householdCollections: const [],
  );
}

void main() {
  group('isFullyResolved', () {
    test('false while any stop is still Pending', () {
      expect(isFullyResolved(_trip(total: 5, resolved: 4, collected: 4)), isFalse);
    });

    test('true once every stop is acted on, even with zero collected', () {
      // Mirrors the backend's `resolved` definition: is_collected OR status
      // != Pending — so Collect Later / Not Available count as resolved.
      expect(isFullyResolved(_trip(total: 3, resolved: 3, collected: 0)), isTrue);
    });

    test('true when every stop is strictly collected', () {
      expect(isFullyResolved(_trip(total: 3, resolved: 3, collected: 3)), isTrue);
    });

    test('false for a trip with no stops at all', () {
      expect(isFullyResolved(_trip(total: 0, resolved: 0, collected: 0)), isFalse);
    });

    test('stays accurate for a trip with more stops than one page', () {
      // 48 stops (more than STOPS_PAGE_SIZE=20 on the backend) — this must
      // still work correctly even though collectionPoints/householdCollections
      // on this trip would only ever hold the first 20 in the real app.
      expect(isFullyResolved(_trip(total: 48, resolved: 48, collected: 40)), isTrue);
      expect(isFullyResolved(_trip(total: 48, resolved: 47, collected: 40)), isFalse);
    });
  });

  group('postponedStopCount', () {
    test('reads progress.postponed directly, not the (possibly partial) stop lists', () {
      expect(postponedStopCount(_trip(total: 2, resolved: 2, collected: 1, postponed: 1)), 1);
    });

    test('zero when nothing was postponed', () {
      expect(postponedStopCount(_trip(total: 2, resolved: 2, collected: 2, postponed: 0)), 0);
    });

    test('reflects postponed stops beyond the first loaded page', () {
      // Only 20 of 48 stops are ever embedded/loaded client-side, but 5 of
      // the 48 were postponed — 3 of them past page 1. progress.postponed
      // must still report all 5, since it comes from the server, not from
      // whatever pages the app happens to have loaded so far.
      expect(
        postponedStopCount(_trip(total: 48, resolved: 48, collected: 43, postponed: 5)),
        5,
      );
    });
  });

  group('the two nudge scenarios from the request', () {
    test('"all collected" — resolved, zero postponed', () {
      final trip = _trip(total: 3, resolved: 3, collected: 3, postponed: 0);
      expect(isFullyResolved(trip), isTrue);
      expect(postponedStopCount(trip), 0);
    });

    test('"some marked collect later" — resolved, some postponed', () {
      final trip = _trip(total: 3, resolved: 3, collected: 1, postponed: 1);
      expect(isFullyResolved(trip), isTrue);
      expect(postponedStopCount(trip), 1);
    });

    test('untouched stops remaining — must NOT be treated as resolved', () {
      final trip = _trip(total: 3, resolved: 2, collected: 1, postponed: 1);
      expect(isFullyResolved(trip), isFalse);
    });
  });
}
