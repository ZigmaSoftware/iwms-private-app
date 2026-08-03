/// Sequencing rules for a crew holding more than one trip of the SAME
/// collection type in a day.
///
/// The domain allows a second same-type trip only at a different time (a 06:30
/// bin run and a 15:00 bin run), and those run one after the other: the later
/// trip stays locked until the earlier one has no work left. The backend
/// enforces the same order — `find_active_assignment_for_operator` resolves
/// scans to the earliest unfinished trip of the scanned type, and rejects a
/// locked trip's bin with `TRIP_LOCKED` — so this is the UI half of one rule,
/// not a second opinion.
///
/// Different collection types do NOT block each other: a household trip and a
/// bin trip at the same time are both live.
library;

import 'package:iwms_citizen_app/data/models/operator_trip_models.dart';

/// The trip that must be finished before a locked trip opens.
class TripBlocker {
  const TripBlocker({required this.blockedBy, required this.position});

  /// The earlier same-type trip still holding this one closed.
  final OperatorTripToday blockedBy;

  /// 1-based position of the locked trip among its own collection type, for
  /// copy like "Trip 2 of 2".
  final int position;

  String get message {
    final time = blockedBy.scheduledTimeLabel;
    final label = blockedBy.assignmentTypeLabel.toLowerCase();
    if (time.isEmpty) {
      return 'Finish your current $label trip to unlock this one.';
    }
    return 'Finish your $time $label trip to unlock this one.';
  }
}

/// Map of assignment id → blocker, for every trip in [trips] that is locked.
/// Trips absent from the map are open for work.
///
/// [trips] is expected in run order (the backend serves them sorted by
/// scheduled time); ordering is by position in the list, so callers must not
/// re-sort into e.g. alphabetical order first.
Map<String, TripBlocker> tripBlockers(List<OperatorTripToday> trips) {
  final blockers = <String, TripBlocker>{};

  // Group by collection type: only same-type trips gate each other.
  final byType = <String, List<OperatorTripToday>>{};
  for (final trip in trips) {
    byType.putIfAbsent(trip.collectionType ?? '', () => []).add(trip);
  }

  for (final group in byType.values) {
    if (group.length < 2) continue;
    // The first unfinished trip in the group is the live one; everything after
    // it is locked and reports that same trip as its blocker — so trip 3 says
    // "finish your 06:30 trip", not "finish your 15:00 trip", which the driver
    // cannot act on yet either.
    OperatorTripToday? liveTrip;
    for (var i = 0; i < group.length; i++) {
      final trip = group[i];
      if (liveTrip == null) {
        if (!trip.isFinished) liveTrip = trip;
        continue;
      }
      blockers[trip.assignmentUniqueId] = TripBlocker(
        blockedBy: liveTrip,
        position: i + 1,
      );
    }
  }

  return blockers;
}

/// True when [trip] cannot be worked yet.
bool isTripLocked(List<OperatorTripToday> trips, OperatorTripToday? trip) {
  if (trip == null) return false;
  return tripBlockers(trips).containsKey(trip.assignmentUniqueId);
}

/// The first trip in [trips] the driver can actually work on — the earliest
/// unlocked, unfinished one, falling back to the first unlocked trip and then
/// to the first trip. Used to pick which card the carousel opens on.
OperatorTripToday? firstWorkableTrip(List<OperatorTripToday> trips) {
  if (trips.isEmpty) return null;
  final blockers = tripBlockers(trips);
  for (final trip in trips) {
    if (blockers.containsKey(trip.assignmentUniqueId)) continue;
    if (!trip.isFinished) return trip;
  }
  for (final trip in trips) {
    if (!blockers.containsKey(trip.assignmentUniqueId)) return trip;
  }
  return trips.first;
}
