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
    this.expiresAt,
    this.reminderSentAt,
    this.escalatedAt,
    this.reasonCodeLabel = '',
    this.panchayatName = '',
    this.zoneName = '',
    this.wardName = '',
  });

  final String uniqueId;
  final String assignmentUniqueId;
  final String status; // Pending | Approved | Rejected | Expired
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
  final DateTime? expiresAt;
  final DateTime? reminderSentAt;
  final DateTime? escalatedAt;

  /// The driver's reason category ("Vehicle full", "Other", …); empty on
  /// requests raised before categories existed.
  final String reasonCodeLabel;
  final String panchayatName;
  final String zoneName;

  /// Comma-joined when the trip covers several wards.
  final String wardName;

  /// "Panchayat · Zone · Ward", skipping levels the trip doesn't have.
  String get locationLabel => [panchayatName, zoneName, wardName]
      .where((part) => part.isNotEmpty)
      .join(' · ');

  bool get isPending => status == 'Pending';
  bool get isExpired => status == 'Expired';

  Duration? remaining([DateTime? now]) {
    if (!isPending || expiresAt == null) return null;
    final value = expiresAt!.difference(now ?? DateTime.now());
    return value.isNegative ? Duration.zero : value;
  }

  bool get isLocallyExpired =>
      isPending && expiresAt != null && !expiresAt!.isAfter(DateTime.now());

  String expiryLabel([DateTime? now]) {
    if (isExpired) return 'Expired';
    final value = remaining(now);
    if (value == null) return '';
    if (value == Duration.zero) return 'Expired';
    final minutes = (value.inSeconds / 60).ceil();
    return 'Expires in $minutes min';
  }

  bool get isHousehold =>
      (collectionType ?? '').contains('household') ||
      (collectionType ?? '').contains('bulk');

  /// Every pending stop, bins and households alike. A trip can hold both,
  /// and approval marks any pending stop left out of `collection_point_ids`
  /// as Missed, so the review must offer all of them.
  List<RetripPendingStop> get liveStops =>
      [...livePendingBins, ...livePendingHouseholds];

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
      expiresAt: _date(json['expires_at']),
      reminderSentAt: _date(json['reminder_sent_at']),
      escalatedAt: _date(json['escalated_at']),
      reasonCodeLabel: _str(json['reason_code_label']),
      panchayatName: _str(json['panchayat_name']),
      zoneName: _str(json['zone_name']),
      wardName: _str(json['ward_name']),
    );
  }
}
