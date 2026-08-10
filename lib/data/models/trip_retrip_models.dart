/// Data models for the supervisor's Re-Trip review flow.
///
/// Mirror `TripRetripRequestSerializer` on
/// `app/serializers/core_modules/daily_operations/trip_retrip_serializer.py`.
/// A Re-Trip request is raised when a driver ends a trip early with stops
/// still pending (see `trip_lifecycle_control.dart` on the driver side) —
/// distinct from a `VehicleBreakdownReport`, which is a different feature
/// entirely and never appears here.
///
/// Shape ported from the government app's identically-purposed
/// `SupervisorRetripRequest`/`SupervisorRetripStop`
/// (`module5_supervisor/data/supervisor_models.dart`).
library;

String _str(dynamic v) => v == null ? '' : v.toString().trim();

int _int(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

DateTime? _date(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse(v.toString());
}

/// One pending stop, live-recomputed server-side under `live_pending`
/// (falls back to the request-time `pending_snapshot` for older payloads).
class RetripPendingStop {
  const RetripPendingStop({
    required this.uniqueId,
    required this.name,
    required this.status,
    required this.sequence,
  });

  final String uniqueId;
  final String name;
  final String status;
  final int sequence;

  factory RetripPendingStop.fromJson(Map<String, dynamic> json) {
    final name = _str(json['name']);
    return RetripPendingStop(
      uniqueId: _str(json['unique_id']),
      name: name.isEmpty ? _str(json['unique_id']) : name,
      status: _str(json['status']),
      sequence: _int(json['sequence']),
    );
  }
}

class TripRetripRequest {
  const TripRetripRequest({
    required this.uniqueId,
    required this.assignmentUniqueId,
    required this.status,
    required this.reason,
    required this.pendingBinCount,
    required this.pendingHouseholdCount,
    required this.requestedByName,
    required this.areaName,
    required this.vehicleNo,
    required this.collectionType,
    required this.reviewRemarks,
    required this.tripDate,
    required this.scheduledTime,
    required this.livePendingBins,
    required this.livePendingHouseholds,
    this.createdAt,
  });

  final String uniqueId;
  final String assignmentUniqueId;
  final String status; // Pending | Approved | Rejected
  final String reason;
  // Snapshot counts taken when the request was raised — the audit record of
  // what was outstanding then, not necessarily what's outstanding now.
  final int pendingBinCount;
  final int pendingHouseholdCount;
  final String requestedByName;
  final String areaName;
  final String vehicleNo;
  final String? collectionType;
  final String reviewRemarks;
  final String tripDate;
  final String scheduledTime;
  // Live, server-recomputed on every fetch — a colleague may have collected
  // a stop since the driver raised the request, so approval must tick boxes
  // against reality, not history.
  final List<RetripPendingStop> livePendingBins;
  final List<RetripPendingStop> livePendingHouseholds;
  final DateTime? createdAt;

  bool get isPending => status == 'Pending';

  bool get isHousehold =>
      (collectionType ?? '').contains('household') ||
      (collectionType ?? '').contains('bulk');

  /// The stops relevant to this request's type — households for a
  /// household/bulk trip, collection points for a bin trip.
  List<RetripPendingStop> get liveStops =>
      isHousehold ? livePendingHouseholds : livePendingBins;

  int get snapshotPendingTotal => pendingBinCount + pendingHouseholdCount;

  int get livePendingTotal =>
      livePendingBins.length + livePendingHouseholds.length;

  /// Prefers the live count when available — a colleague may have collected
  /// a stop since the driver raised the request, so the live figure is more
  /// accurate whenever the server actually returned live stops.
  int get pendingTotal =>
      livePendingTotal > 0 ? livePendingTotal : snapshotPendingTotal;

  factory TripRetripRequest.fromJson(Map<String, dynamic> json) {
    final live = json['live_pending'] is Map
        ? Map<String, dynamic>.from(json['live_pending'] as Map)
        : (json['pending_snapshot'] is Map
            ? Map<String, dynamic>.from(json['pending_snapshot'] as Map)
            : const <String, dynamic>{});
    final bins = (live['collection_points'] as List? ?? [])
        .whereType<Map>()
        .map((e) => RetripPendingStop.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final households = (live['households'] as List? ?? [])
        .whereType<Map>()
        .map((e) => RetripPendingStop.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    return TripRetripRequest(
      uniqueId: _str(json['unique_id']),
      assignmentUniqueId: _str(json['assignment_unique_id']),
      status: _str(json['status']).isEmpty ? 'Pending' : _str(json['status']),
      reason: _str(json['reason']),
      pendingBinCount: _int(json['pending_bin_count']),
      pendingHouseholdCount: _int(json['pending_household_count']),
      requestedByName: _str(json['requested_by_name']),
      areaName: _str(json['area_name']),
      vehicleNo: _str(json['vehicle_no']),
      collectionType: json['collection_type']?.toString().toLowerCase(),
      reviewRemarks: _str(json['review_remarks']),
      tripDate: _str(json['trip_date']),
      scheduledTime: _str(json['scheduled_time']),
      livePendingBins: bins,
      livePendingHouseholds: households,
      createdAt: _date(json['created_at']),
    );
  }
}
