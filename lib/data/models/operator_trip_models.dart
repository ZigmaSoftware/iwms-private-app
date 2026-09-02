/// Data models for the operator-mobile trip flow.
///
/// These mirror the backend `/api/v1/operator-mobile/...` payloads.
library;

class OperatorTripPanchayat {
  final String uniqueId;
  final String name;
  final double? latitude;
  final double? longitude;

  const OperatorTripPanchayat({
    required this.uniqueId,
    required this.name,
    this.latitude,
    this.longitude,
  });

  factory OperatorTripPanchayat.fromJson(Map<String, dynamic> json) {
    return OperatorTripPanchayat(
      uniqueId: json['unique_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      latitude: _parseDouble(json['latitude']),
      longitude: _parseDouble(json['longitude']),
    );
  }
}

class OperatorTripWasteType {
  final String uniqueId;
  final String name;

  const OperatorTripWasteType({required this.uniqueId, required this.name});

  factory OperatorTripWasteType.fromJson(Map<String, dynamic> json) {
    return OperatorTripWasteType(
      uniqueId: json['unique_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
    );
  }

  /// Resolves the trip's waste type from either the current backend shape —
  /// `waste_types` (a list, since a trip can now carry multiple types) — or the
  /// legacy singular `waste_type` (a map). Returns a non-null placeholder when
  /// neither is present, so callers never crash on a missing/typed-null field.
  ///
  /// When multiple types are present, the first is used as the primary label
  /// and [names] can be read for the full set.
  static OperatorTripWasteType resolve(Map<String, dynamic> json) {
    final list = json['waste_types'];
    if (list is List && list.isNotEmpty && list.first is Map) {
      return OperatorTripWasteType.fromJson(
        Map<String, dynamic>.from(list.first as Map),
      );
    }
    final single = json['waste_type'];
    if (single is Map) {
      return OperatorTripWasteType.fromJson(
        Map<String, dynamic>.from(single),
      );
    }
    return const OperatorTripWasteType(uniqueId: '', name: '');
  }

  /// All waste-type names for a trip (new plural shape), falling back to the
  /// single legacy type. Empty if none present.
  static List<String> names(Map<String, dynamic> json) {
    final list = json['waste_types'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) => e['name']?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .toList();
    }
    final single = json['waste_type'];
    if (single is Map) {
      final n = single['name']?.toString() ?? '';
      return n.isEmpty ? const [] : [n];
    }
    return const [];
  }

  bool get isWet => name.toLowerCase().contains('wet');
  bool get isDry => name.toLowerCase().contains('dry');
}

class OperatorTripVehicle {
  final String uniqueId;
  final String vehicleNo;
  final double? capacity;

  const OperatorTripVehicle({
    required this.uniqueId,
    required this.vehicleNo,
    this.capacity,
  });

  factory OperatorTripVehicle.fromJson(Map<String, dynamic> json) {
    return OperatorTripVehicle(
      uniqueId: json['unique_id']?.toString() ?? '',
      vehicleNo: json['vehicle_no']?.toString() ?? '',
      capacity: _parseDouble(json['capacity']),
    );
  }
}

class OperatorTripCollectionPointBrief {
  final String uniqueId;
  final String name;
  final double? latitude;
  final double? longitude;

  const OperatorTripCollectionPointBrief({
    required this.uniqueId,
    required this.name,
    this.latitude,
    this.longitude,
  });

  factory OperatorTripCollectionPointBrief.fromJson(Map<String, dynamic> json) {
    return OperatorTripCollectionPointBrief(
      uniqueId: json['unique_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      latitude: _parseDouble(json['latitude']),
      longitude: _parseDouble(json['longitude']),
    );
  }
}

class OperatorTripBinBrief {
  final String uniqueId;
  final String binName;
  // Scanner value used by the operator-mobile API. Server now sends the
  // bin's `unique_id` here (matches the QR payload's `id` field).
  final String binQr;
  final String? binQrImageUrl;
  final int binCapacity;
  final OperatorTripWasteType? wasteType;

  const OperatorTripBinBrief({
    required this.uniqueId,
    required this.binName,
    required this.binQr,
    required this.binCapacity,
    this.binQrImageUrl,
    this.wasteType,
  });

  /// What the operator scans / sends back. We prefer the explicit `bin_qr`
  /// field but fall back to the bin's unique_id (older payloads).
  String get scanValue => binQr.isNotEmpty ? binQr : uniqueId;

  factory OperatorTripBinBrief.fromJson(Map<String, dynamic> json) {
    return OperatorTripBinBrief(
      uniqueId: json['unique_id']?.toString() ?? '',
      binName: json['bin_name']?.toString() ?? '',
      binQr: json['bin_qr']?.toString() ?? '',
      binQrImageUrl: json['bin_qr_image_url']?.toString(),
      binCapacity: _parseInt(json['bin_capacity']) ?? 0,
      wasteType: json['waste_type'] is Map<String, dynamic>
          ? OperatorTripWasteType.fromJson(
              json['waste_type'] as Map<String, dynamic>,
            )
          : null,
    );
  }
}

class OperatorTripCollectionPoint {
  final String uniqueId;
  final int sequence;
  final bool isCollected;
  final String status;
  final String? statusReason;
  final DateTime? collectedAt;
  final double? collectedWeightKg;
  final OperatorTripCollectionPointBrief collectionPoint;
  final OperatorTripBinBrief bin;

  const OperatorTripCollectionPoint({
    required this.uniqueId,
    required this.sequence,
    required this.isCollected,
    required this.status,
    required this.collectionPoint,
    required this.bin,
    this.statusReason,
    this.collectedAt,
    this.collectedWeightKg,
  });

  OperatorTripCollectionPoint copyWith({int? sequence}) =>
      OperatorTripCollectionPoint(
        uniqueId: uniqueId,
        sequence: sequence ?? this.sequence,
        isCollected: isCollected,
        status: status,
        collectionPoint: collectionPoint,
        bin: bin,
        statusReason: statusReason,
        collectedAt: collectedAt,
        collectedWeightKg: collectedWeightKg,
      );

  factory OperatorTripCollectionPoint.fromJson(Map<String, dynamic> json) {
    return OperatorTripCollectionPoint(
      uniqueId: json['unique_id']?.toString() ?? '',
      sequence: _parseInt(json['sequence']) ?? 0,
      isCollected: json['is_collected'] == true,
      status: json['status']?.toString() ?? 'Pending',
      statusReason: json['status_reason']?.toString(),
      collectedAt: _parseDate(json['collected_at']),
      collectedWeightKg: _parseDouble(json['collected_weight_kg']),
      collectionPoint: OperatorTripCollectionPointBrief.fromJson(
        Map<String, dynamic>.from(json['collection_point'] as Map),
      ),
      bin: OperatorTripBinBrief.fromJson(
        Map<String, dynamic>.from(json['bin'] as Map),
      ),
    );
  }
}

/// A household stop (customer) on a household / bulk-waste trip. The driver
/// collects each household directly (weight capture) instead of scanning a bin.
/// One waste stream saved against a customer in Customer Creation, as served by
/// `waste/get-waste-types/?customer_id=…`. This is what the household *should*
/// be handing over, so the driver can check the segregation before collecting.
class CustomerWasteType {
  final String id;
  final String name;

  const CustomerWasteType({required this.id, required this.name});

  factory CustomerWasteType.fromJson(Map<String, dynamic> json) =>
      CustomerWasteType(
        id: json['id']?.toString() ?? '',
        name: json['waste_type_name']?.toString().trim() ?? '',
      );

  /// Lower-cased name, for the wet/dry/sanitary/mixed matching the UI does when
  /// picking a colour and icon.
  String get key => name.toLowerCase();
}

/// One waste-type row in a household stop's collection breakdown — e.g.
/// "Wet Waste, 3.5 kg". Shown in the "eye" floating window on a collected
/// household tile.
class WasteBreakdownEntry {
  final String wasteType;
  final double weightKg;

  const WasteBreakdownEntry({required this.wasteType, required this.weightKg});

  factory WasteBreakdownEntry.fromJson(Map<String, dynamic> json) {
    return WasteBreakdownEntry(
      wasteType: json['waste_type']?.toString() ?? 'Waste',
      weightKg: _parseDouble(json['weight_kg']) ?? 0,
    );
  }
}

class OperatorTripHouseholdStop {
  final String uniqueId;
  final int sequence;
  final bool isCollected;
  final String status;
  final String? statusReason;
  final DateTime? collectedAt;
  final double? collectedWeightKg;
  final String customerUniqueId;
  final String customerName;
  final String? contactNo;
  final String? address;
  final double? latitude;
  final double? longitude;

  /// Per-waste-type split of [collectedWeightKg] — empty until collected,
  /// and possibly still empty even once collected (a legacy row that never
  /// went through the waste-type-split flow). See the "eye" button on
  /// [_HouseholdTile] in captain_home_tab.dart.
  final List<WasteBreakdownEntry> wasteBreakdown;

  const OperatorTripHouseholdStop({
    required this.uniqueId,
    required this.sequence,
    required this.isCollected,
    required this.status,
    required this.customerUniqueId,
    required this.customerName,
    this.statusReason,
    this.collectedAt,
    this.collectedWeightKg,
    this.contactNo,
    this.address,
    this.latitude,
    this.longitude,
    this.wasteBreakdown = const [],
  });

  factory OperatorTripHouseholdStop.fromJson(Map<String, dynamic> json) {
    final customer = json['customer'] is Map
        ? Map<String, dynamic>.from(json['customer'] as Map)
        : const <String, dynamic>{};
    return OperatorTripHouseholdStop(
      uniqueId: json['unique_id']?.toString() ?? '',
      sequence: _parseInt(json['sequence']) ?? 0,
      isCollected: json['is_collected'] == true,
      status: json['status']?.toString() ?? 'Pending',
      statusReason: json['status_reason']?.toString(),
      collectedAt: _parseDate(json['collected_at']),
      collectedWeightKg: _parseDouble(json['collected_weight_kg']),
      customerUniqueId: customer['unique_id']?.toString() ?? '',
      customerName: customer['name']?.toString() ?? 'Household',
      contactNo: customer['contact_no']?.toString(),
      address: customer['address']?.toString(),
      latitude: _parseDouble(customer['latitude']),
      longitude: _parseDouble(customer['longitude']),
      wasteBreakdown: (json['waste_breakdown'] as List? ?? const [])
          .map((e) => WasteBreakdownEntry.fromJson(
                Map<String, dynamic>.from(e as Map),
              ))
          .toList(),
    );
  }
}

class OperatorTripProgress {
  final int collected;
  final int total;
  final int resolved;

  /// Stops explicitly postponed (Collect Later / Skipped), as opposed to
  /// collected or genuinely resolved-as-unavailable (Not Available).
  ///
  /// Server-computed because `collection_points`/`household_collections` are
  /// no longer the full list once a trip has more than one page of stops
  /// (see `STOPS_PAGE_SIZE` on the backend) — this field is what lets
  /// `TripCompletionNudge` tell "everything truly collected" apart from
  /// "resolved, but some carried over to a follow-up trip" without needing
  /// every stop downloaded.
  final int postponed;

  final bool completed;

  const OperatorTripProgress({
    required this.collected,
    required this.total,
    required this.resolved,
    required this.completed,
    this.postponed = 0,
  });

  factory OperatorTripProgress.fromJson(Map<String, dynamic> json) {
    return OperatorTripProgress(
      collected: _parseInt(json['collected']) ?? 0,
      total: _parseInt(json['total']) ?? 0,
      resolved:
          _parseInt(json['resolved']) ?? _parseInt(json['collected']) ?? 0,
      postponed: _parseInt(json['postponed']) ?? 0,
      completed: json['completed'] == true,
    );
  }

  double get fraction => total == 0 ? 0.0 : collected / total;

  double get resolvedFraction => total == 0 ? 0.0 : resolved / total;
}

class OperatorTripWard {
  final String uniqueId;
  final String name;

  const OperatorTripWard({required this.uniqueId, required this.name});

  factory OperatorTripWard.fromJson(Map<String, dynamic> json) {
    return OperatorTripWard(
      uniqueId: json['unique_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
    );
  }
}

/// A Re-Trip request raised by [OperatorTripToday.retripRequest] while it
/// awaits supervisor review — see `app/services/retrip_service.py` on the
/// backend. Only ever the *pending* one, if any; approved/rejected requests
/// don't come back here (the assignment itself reflects the outcome).
class OperatorTripRetripRequest {
  final String uniqueId;
  final String status;
  final String? reason;
  final int pendingBinCount;
  final int pendingHouseholdCount;
  final DateTime? createdAt;

  const OperatorTripRetripRequest({
    required this.uniqueId,
    required this.status,
    this.reason,
    this.pendingBinCount = 0,
    this.pendingHouseholdCount = 0,
    this.createdAt,
  });

  factory OperatorTripRetripRequest.fromJson(Map<String, dynamic> json) {
    return OperatorTripRetripRequest(
      uniqueId: json['unique_id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'Pending',
      reason: json['reason']?.toString(),
      pendingBinCount: _parseInt(json['pending_bin_count']) ?? 0,
      pendingHouseholdCount: _parseInt(json['pending_household_count']) ?? 0,
      createdAt: _parseDate(json['created_at']),
    );
  }
}

class OperatorTripToday {
  final String assignmentUniqueId;
  final DateTime tripDate;
  final String status;
  final String? scheduledTime;
  final String? actualStartTime;
  final String? actualEndTime;
  final DateTime? actualStartAt;
  final DateTime? actualEndAt;
  final OperatorTripRetripRequest? retripRequest;
  // A trip is either panchayat- or ward-based; exactly one is set.
  final OperatorTripPanchayat? panchayat;
  final OperatorTripWard? ward;
  final OperatorTripWasteType wasteType;
  final OperatorTripVehicle? vehicle;
  final OperatorTripPlanBrief? tripPlan;
  final OperatorTripProgress progress;
  final double distanceMeters;
  final double durationSeconds;
  final Map<String, dynamic>? routeGeojson;
  final List<double>? vehicleStart;
  final List<OperatorTripCollectionPoint> collectionPoints;
  // Everyone working this vehicle today (driver + operator + extras). The
  // merged driver app renders this read-only so the driver knows their crew.
  final OperatorTripCrew? crew;
  // bin_collection / household_collection / bulk_waste_collection — drives the
  // collection-type pill on the trip header.
  final String? collectionType;
  // Household stops (customers) for household/bulk trips. Empty for bin trips.
  final List<OperatorTripHouseholdStop> householdCollections;

  const OperatorTripToday({
    required this.assignmentUniqueId,
    required this.tripDate,
    required this.status,
    required this.wasteType,
    required this.progress,
    required this.collectionPoints,
    this.collectionType,
    this.householdCollections = const [],
    this.panchayat,
    this.ward,
    this.vehicle,
    this.tripPlan,
    this.distanceMeters = 0,
    this.durationSeconds = 0,
    this.routeGeojson,
    this.vehicleStart,
    this.scheduledTime,
    this.actualStartTime,
    this.actualEndTime,
    this.actualStartAt,
    this.actualEndAt,
    this.retripRequest,
    this.crew,
  });

  /// Returns a copy of this trip with a different set of collection points
  /// (used to apply a route-order re-sequence shared by the list and the map).
  OperatorTripToday withCollectionPoints(
          List<OperatorTripCollectionPoint> points) =>
      OperatorTripToday(
        assignmentUniqueId: assignmentUniqueId,
        tripDate: tripDate,
        status: status,
        wasteType: wasteType,
        progress: progress,
        collectionPoints: points,
        collectionType: collectionType,
        householdCollections: householdCollections,
        panchayat: panchayat,
        ward: ward,
        vehicle: vehicle,
        tripPlan: tripPlan,
        distanceMeters: distanceMeters,
        durationSeconds: durationSeconds,
        routeGeojson: routeGeojson,
        vehicleStart: vehicleStart,
        scheduledTime: scheduledTime,
        actualStartTime: actualStartTime,
        actualEndTime: actualEndTime,
        actualStartAt: actualStartAt,
        actualEndAt: actualEndAt,
        retripRequest: retripRequest,
        crew: crew,
      );

  /// Display name for the trip's service area (ward, falling back to
  /// panchayat for older trips created before ward assignment existed).
  String get areaName => ward?.name ?? panchayat?.name ?? '—';

  /// True for household / bulk-waste trips, which collect customers directly
  /// (no bins). Drives the adaptive list on the driver home.
  bool get isHousehold =>
      collectionType == 'household_collection' ||
      collectionType == 'bulk_waste_collection';

  /// No work left on this trip: every stop resolved (collected or not
  /// available), or the backend already marked the assignment Completed.
  ///
  /// This is what sequences a crew's same-type trips — the next bin trip only
  /// unlocks once this one reports done. Mirrors `assignment_is_finished` on
  /// the backend, so the app's lock and the scan endpoint agree.
  bool get isFinished =>
      status.toLowerCase() == 'completed' || progress.completed;

  /// The backend has CLOSED this assignment — it belongs in history, not on
  /// today's carousel.
  ///
  /// Also true for a trip closed by an approved Re-Trip: `approve_retrip`
  /// calls `mark_ended()` on the source assignment, so "Re-Trip assigned" and
  /// "Completed" are the same end state as far as the app can see. Whatever
  /// carried over arrives as a separate continuation assignment, which shows
  /// up as its own (open) card.
  ///
  /// Deliberately NOT [isFinished]: that is also true when every stop is
  /// resolved but the driver has not pressed "End Trip" yet, and such a trip
  /// MUST stay on the carousel — hiding it would strip the driver of the only
  /// control that can close it.
  bool get isClosed => status.toLowerCase() == 'completed';

  /// True once the driver has explicitly pressed "Start Trip" — mirrors the
  /// backend's `require_trip_started` gate (which checks `actual_start_at`,
  /// not the legacy wall-clock-only `actual_start_time`).
  bool get isStarted => actualStartAt != null;

  /// True while a Re-Trip request raised from this trip is awaiting
  /// supervisor review — the driver can keep collecting, but End Trip is
  /// already spoken for.
  bool get hasPendingRetrip => retripRequest != null;

  /// `HH:mm` for the header/lock copy ("Finish your 06:30 trip first").
  String get scheduledTimeLabel {
    final raw = scheduledTime;
    if (raw == null || raw.isEmpty) return '';
    final parts = raw.split(':');
    if (parts.length < 2) return raw;
    return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
  }

  String get assignmentTypeLabel {
    switch (collectionType) {
      case 'household_collection':
        return 'Household';
      case 'bulk_waste_collection':
        return 'Bulk Waste';
      case 'bin_collection':
        return 'Bin';
      default:
        return '';
    }
  }

  /// Total weight collected so far, summed from the per-collection-point
  /// weights in today's payload. `my-trip-today` doesn't ship an aggregate
  /// total, but each collected CP carries `collected_weight_kg`, so we derive
  /// it here to match the history summary shape.
  double get totalCollectedWeightKg => collectionPoints.fold<double>(
        0.0,
        (sum, cp) => sum + (cp.collectedWeightKg ?? 0.0),
      );

  /// Adapt today's single-trip payload into the history *summary* shape the
  /// driver/operator screens already render. `my-trip-today` and trip-history
  /// describe the same DailyTripAssignment, so the overlapping fields map
  /// directly; history-only fields (staff block, plan, remarks) aren't part of
  /// this endpoint and stay null. Total weight is derived from the CPs.
  OperatorTripHistorySummary toHistorySummary() {
    return OperatorTripHistorySummary(
      assignmentUniqueId: assignmentUniqueId,
      tripDate: tripDate,
      status: status,
      scheduledTime: scheduledTime,
      actualStartTime: actualStartTime,
      actualEndTime: actualEndTime,
      panchayat: panchayat,
      ward: ward,
      wasteType: wasteType,
      vehicle: vehicle,
      tripPlan: tripPlan,
      progress: progress,
      totalWeightKg: totalCollectedWeightKg,
      collectionType: collectionType,
    );
  }

  /// Adapt today's single-trip payload into the history *detail* shape. The
  /// collection points carry through directly; `events` is empty because
  /// `my-trip-today` doesn't embed the per-bin event log (the history detail
  /// endpoint does).
  OperatorTripHistoryDetail toHistoryDetail() {
    return OperatorTripHistoryDetail(
      summary: toHistorySummary(),
      collectionPoints: collectionPoints,
      events: const [],
    );
  }

  factory OperatorTripToday.fromJson(Map<String, dynamic> json) {
    return OperatorTripToday(
      assignmentUniqueId: json['assignment_unique_id']?.toString() ?? '',
      tripDate: DateTime.parse(json['trip_date'].toString()),
      status: json['status']?.toString() ?? '',
      collectionType: json['collection_type']?.toString(),
      householdCollections: (json['household_collections'] as List? ?? [])
          .whereType<Map>()
          .map((e) => OperatorTripHouseholdStop.fromJson(
                Map<String, dynamic>.from(e),
              ))
          .toList(),
      scheduledTime: json['scheduled_time']?.toString(),
      actualStartTime: json['actual_start_time']?.toString(),
      actualEndTime: json['actual_end_time']?.toString(),
      actualStartAt: _parseDate(json['actual_start_at']),
      actualEndAt: _parseDate(json['actual_end_at']),
      retripRequest: json['retrip_request'] is Map
          ? OperatorTripRetripRequest.fromJson(
              Map<String, dynamic>.from(json['retrip_request'] as Map),
            )
          : null,
      panchayat: json['panchayat'] is Map
          ? OperatorTripPanchayat.fromJson(
              Map<String, dynamic>.from(json['panchayat'] as Map),
            )
          : null,
      ward: json['ward'] is Map
          ? OperatorTripWard.fromJson(
              Map<String, dynamic>.from(json['ward'] as Map),
            )
          : null,
      // Backend now sends `waste_types` (plural list); resolve handles both
      // that and the legacy singular `waste_type`, never crashing on null.
      wasteType: OperatorTripWasteType.resolve(json),
      vehicle: json['vehicle'] is Map<String, dynamic>
          ? OperatorTripVehicle.fromJson(
              Map<String, dynamic>.from(json['vehicle'] as Map),
            )
          : null,
      tripPlan: json['trip_plan'] is Map
          ? OperatorTripPlanBrief.fromJson(
              Map<String, dynamic>.from(json['trip_plan'] as Map),
            )
          : null,
      progress: OperatorTripProgress.fromJson(
        Map<String, dynamic>.from(json['progress'] as Map),
      ),
      distanceMeters: _parseDouble(json['distance_meters']) ?? 0,
      durationSeconds: _parseDouble(json['duration_seconds']) ?? 0,
      routeGeojson: json['route_geojson'] is Map
          ? Map<String, dynamic>.from(json['route_geojson'] as Map)
          : null,
      vehicleStart: _parseCoordinatePair(json['vehicle_start']),
      collectionPoints: (json['collection_points'] as List? ?? [])
          .map((e) => OperatorTripCollectionPoint.fromJson(
                Map<String, dynamic>.from(e as Map),
              ))
          .toList(),
      crew: json['crew'] is Map
          ? OperatorTripCrew.fromJson(
              Map<String, dynamic>.from(json['crew'] as Map),
            )
          : null,
    );
  }
}

/// One crew member on today's trip (driver / operator / extra operator),
/// as served by the `crew` block on `/operator-mobile/my-trip-today/`.
class OperatorTripCrewMember {
  final String uniqueId;
  final String? name;
  final String? empId;
  final String? role;
  final String? phone;
  final String? photoUrl;
  final bool isPresent;
  final String? attendanceStatus;

  const OperatorTripCrewMember({
    required this.uniqueId,
    this.name,
    this.empId,
    this.role,
    this.phone,
    this.photoUrl,
    this.isPresent = false,
    this.attendanceStatus,
  });

  String get displayName => (name?.trim().isNotEmpty == true) ? name! : '—';

  /// "Company Operator" → "Operator", "company_driver" → "Driver".
  String get roleLabel {
    final raw = (role ?? '').replaceAll('_', ' ').trim();
    if (raw.isEmpty) return '';
    final cleaned =
        raw.toLowerCase().startsWith('company ') ? raw.substring(8) : raw;
    if (cleaned.isEmpty) return '';
    return cleaned[0].toUpperCase() + cleaned.substring(1).toLowerCase();
  }

  String get initials {
    final parts = displayName
        .split(RegExp(r'[\s_]+'))
        .where((p) => p.trim().isNotEmpty)
        .toList();
    if (parts.isEmpty || parts.first == '—') return '?';
    if (parts.length == 1) {
      final word = parts.first;
      return word.length >= 2
          ? word.substring(0, 2).toUpperCase()
          : word.toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  factory OperatorTripCrewMember.fromJson(Map<String, dynamic> json) {
    return OperatorTripCrewMember(
      uniqueId: json['unique_id']?.toString() ?? '',
      name: json['name']?.toString(),
      empId: json['emp_id']?.toString(),
      role: json['role']?.toString(),
      phone: json['phone']?.toString(),
      photoUrl: json['photo_url']?.toString(),
      isPresent: json['is_present'] == true,
      attendanceStatus: json['attendance_status']?.toString(),
    );
  }
}

/// The full crew block: driver + primary operator + extra operators.
class OperatorTripCrew {
  final OperatorTripCrewMember? driver;
  final OperatorTripCrewMember? operator;
  final List<OperatorTripCrewMember> extraOperators;
  final bool isAltActive;
  final String? templateCode;
  final String? altTemplateCode;

  const OperatorTripCrew({
    this.driver,
    this.operator,
    this.extraOperators = const [],
    this.isAltActive = false,
    this.templateCode,
    this.altTemplateCode,
  });

  /// All operators on the vehicle (primary + extras).
  List<OperatorTripCrewMember> get operators => [
        if (operator != null) operator!,
        ...extraOperators,
      ];

  factory OperatorTripCrew.fromJson(Map<String, dynamic> json) {
    return OperatorTripCrew(
      driver: json['driver'] is Map
          ? OperatorTripCrewMember.fromJson(
              Map<String, dynamic>.from(json['driver'] as Map),
            )
          : null,
      operator: json['operator'] is Map
          ? OperatorTripCrewMember.fromJson(
              Map<String, dynamic>.from(json['operator'] as Map),
            )
          : null,
      extraOperators: (json['extra_operators'] as List? ?? [])
          .whereType<Map>()
          .map((e) =>
              OperatorTripCrewMember.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      isAltActive: json['is_alt_active'] == true,
      templateCode: json['template_code']?.toString(),
      altTemplateCode: json['alt_template_code']?.toString(),
    );
  }
}

class BinScanValidateResult {
  final OperatorTripBinBrief bin;
  final OperatorTripCollectionPointBrief collectionPoint;
  final OperatorTripCollectionPoint? tripCollectionPoint;
  final Map<String, dynamic> assignment;
  final OperatorTripProgress progress;

  const BinScanValidateResult({
    required this.bin,
    required this.collectionPoint,
    required this.assignment,
    required this.progress,
    this.tripCollectionPoint,
  });

  factory BinScanValidateResult.fromJson(Map<String, dynamic> json) {
    return BinScanValidateResult(
      bin: OperatorTripBinBrief.fromJson(
        Map<String, dynamic>.from(json['bin'] as Map),
      ),
      collectionPoint: OperatorTripCollectionPointBrief.fromJson(
        Map<String, dynamic>.from(json['collection_point'] as Map),
      ),
      tripCollectionPoint: json['trip_collection_point'] is Map
          ? OperatorTripCollectionPoint.fromJson({
              ...Map<String, dynamic>.from(
                  json['trip_collection_point'] as Map),
              'collection_point': json['collection_point'],
              'bin': json['bin'],
            })
          : null,
      assignment: Map<String, dynamic>.from(json['assignment'] as Map),
      progress: OperatorTripProgress.fromJson(
        Map<String, dynamic>.from(json['trip_progress'] as Map),
      ),
    );
  }
}

class BinScanSubmitResult {
  final BinScanValidateResult context;
  final String eventUniqueId;
  final DateTime eventAt;
  final String eventType;
  final double collectedWeightKg;
  final String? statusReason;

  const BinScanSubmitResult({
    required this.context,
    required this.eventUniqueId,
    required this.eventAt,
    required this.eventType,
    required this.collectedWeightKg,
    this.statusReason,
  });

  factory BinScanSubmitResult.fromJson(Map<String, dynamic> json) {
    final event = Map<String, dynamic>.from(json['event'] as Map);
    return BinScanSubmitResult(
      context: BinScanValidateResult.fromJson(json),
      eventUniqueId: event['unique_id']?.toString() ?? '',
      eventAt: _parseDate(event['event_at']) ??
          _parseDate(event['created_at']) ??
          DateTime.now(),
      eventType: event['event_type']?.toString() ?? 'Collected',
      collectedWeightKg: _parseDouble(event['collected_weight_kg']) ?? 0.0,
      statusReason: event['status_reason']?.toString(),
    );
  }

  bool get tripCompleted => context.progress.completed;
}

/// Result of `POST .../trip-lifecycle/{id}/end/`. Three outcomes, not two:
/// the trip closed outright ([ended]), it stayed open behind a new Re-Trip
/// request ([retripRequested]), or the backend refused because stops remain
/// and no [reason] was given yet ([reasonRequired]) — the caller re-prompts
/// for a reason and calls end again, rather than treating this as a hard
/// failure.
class OperatorTripEndResult {
  final bool ended;
  final bool retripRequested;
  final bool reasonRequired;
  final int pendingBinCount;
  final int pendingHouseholdCount;
  final OperatorTripRetripRequest? retripRequest;
  final OperatorTripToday? trip;

  const OperatorTripEndResult({
    required this.ended,
    required this.retripRequested,
    required this.reasonRequired,
    this.pendingBinCount = 0,
    this.pendingHouseholdCount = 0,
    this.retripRequest,
    this.trip,
  });

  factory OperatorTripEndResult.reasonRequired({
    required int pendingBinCount,
    required int pendingHouseholdCount,
  }) =>
      OperatorTripEndResult(
        ended: false,
        retripRequested: false,
        reasonRequired: true,
        pendingBinCount: pendingBinCount,
        pendingHouseholdCount: pendingHouseholdCount,
      );

  factory OperatorTripEndResult.fromJson(Map<String, dynamic> json) {
    final retripJson = json['retrip_request'];
    final tripJson = json['trip'];
    return OperatorTripEndResult(
      ended: json['ended'] == true,
      retripRequested: json['retrip_requested'] == true,
      reasonRequired: false,
      retripRequest: retripJson is Map
          ? OperatorTripRetripRequest.fromJson(
              Map<String, dynamic>.from(retripJson),
            )
          : null,
      trip: tripJson is Map
          ? OperatorTripToday.fromJson(Map<String, dynamic>.from(tripJson))
          : null,
    );
  }
}

/// One person (driver or operator) — used in trip history detail.
class OperatorTripStaffBrief {
  final String uniqueId;
  final String? username;
  final String? name;
  final String? phone;

  const OperatorTripStaffBrief({
    required this.uniqueId,
    this.username,
    this.name,
    this.phone,
  });

  String get displayName =>
      (name?.isNotEmpty == true ? name! : (username ?? '—'));

  factory OperatorTripStaffBrief.fromJson(Map<String, dynamic> json) {
    return OperatorTripStaffBrief(
      uniqueId: json['unique_id']?.toString() ?? '',
      username: json['username']?.toString(),
      name: json['name']?.toString(),
      phone: json['phone']?.toString(),
    );
  }
}

/// Driver + operator block on a trip, with substitution status.
class OperatorTripStaffBlock {
  final OperatorTripStaffBrief? driver;
  final OperatorTripStaffBrief? operator;
  final bool isAltActive;
  final String? templateCode;
  final String? altTemplateCode;

  const OperatorTripStaffBlock({
    this.driver,
    this.operator,
    this.isAltActive = false,
    this.templateCode,
    this.altTemplateCode,
  });

  factory OperatorTripStaffBlock.fromJson(Map<String, dynamic> json) {
    return OperatorTripStaffBlock(
      driver: json['driver'] is Map
          ? OperatorTripStaffBrief.fromJson(
              Map<String, dynamic>.from(json['driver'] as Map),
            )
          : null,
      operator: json['operator'] is Map
          ? OperatorTripStaffBrief.fromJson(
              Map<String, dynamic>.from(json['operator'] as Map),
            )
          : null,
      isAltActive: json['is_alt_active'] == true,
      templateCode: json['template_code']?.toString(),
      altTemplateCode: json['alt_template_code']?.toString(),
    );
  }
}

class OperatorTripPlanBrief {
  final String uniqueId;
  final String displayCode;

  const OperatorTripPlanBrief({
    required this.uniqueId,
    required this.displayCode,
  });

  factory OperatorTripPlanBrief.fromJson(Map<String, dynamic> json) {
    return OperatorTripPlanBrief(
      uniqueId: json['unique_id']?.toString() ?? '',
      displayCode: json['display_code']?.toString() ?? '',
    );
  }
}

class OperatorTripHistorySummary {
  final String assignmentUniqueId;
  final DateTime tripDate;
  final String status;
  final String? approvalStatus;
  final String? collectionType;
  final String? scheduledTime;
  final String? actualStartTime;
  final String? actualEndTime;
  final OperatorTripPanchayat? panchayat;
  final OperatorTripWard? ward;
  final OperatorTripWasteType wasteType;
  final OperatorTripVehicle? vehicle;
  final OperatorTripStaffBlock? staff;
  final OperatorTripPlanBrief? tripPlan;
  final OperatorTripProgress progress;
  final double totalWeightKg;
  final String? remarks;

  const OperatorTripHistorySummary({
    required this.assignmentUniqueId,
    required this.tripDate,
    required this.status,
    required this.wasteType,
    required this.progress,
    required this.totalWeightKg,
    this.collectionType,
    this.approvalStatus,
    this.scheduledTime,
    this.actualStartTime,
    this.actualEndTime,
    this.panchayat,
    this.ward,
    this.vehicle,
    this.staff,
    this.tripPlan,
    this.remarks,
  });

  /// Display name for the trip's service area (ward, falling back to
  /// panchayat for older trips created before ward assignment existed).
  String get areaName => ward?.name ?? panchayat?.name ?? '—';

  bool get isCompleted => status.toLowerCase() == 'completed';
  bool get isInProgress => status.toLowerCase() == 'in progress';
  bool get isScheduled => status.toLowerCase() == 'scheduled';
  bool get isCancelled => status.toLowerCase() == 'cancelled';
  bool get isHouseholdCollection =>
      collectionType == 'household_collection' ||
      collectionType == 'bulk_waste_collection';
  bool get isBinCollection => collectionType == 'bin_collection';

  String get assignmentTypeLabel {
    switch (collectionType) {
      case 'household_collection':
        return 'Household';
      case 'bulk_waste_collection':
        return 'Bulk Waste';
      case 'bin_collection':
        return 'Bin';
      default:
        return '';
    }
  }

  /// Estimated duration if both start + end are known.
  Duration? get duration {
    final start = _timeToToday(actualStartTime, tripDate);
    final end = _timeToToday(actualEndTime, tripDate);
    if (start == null || end == null) return null;
    final diff = end.difference(start);
    return diff.isNegative ? null : diff;
  }

  factory OperatorTripHistorySummary.fromJson(Map<String, dynamic> json) {
    return OperatorTripHistorySummary(
      assignmentUniqueId: json['assignment_unique_id']?.toString() ?? '',
      tripDate: DateTime.parse(json['trip_date'].toString()),
      status: json['status']?.toString() ?? '',
      approvalStatus: json['approval_status']?.toString(),
      collectionType: json['collection_type']?.toString(),
      scheduledTime: json['scheduled_time']?.toString(),
      actualStartTime: json['actual_start_time']?.toString(),
      actualEndTime: json['actual_end_time']?.toString(),
      panchayat: json['panchayat'] is Map
          ? OperatorTripPanchayat.fromJson(
              Map<String, dynamic>.from(json['panchayat'] as Map),
            )
          : null,
      ward: json['ward'] is Map
          ? OperatorTripWard.fromJson(
              Map<String, dynamic>.from(json['ward'] as Map),
            )
          : null,
      vehicle: json['vehicle'] is Map
          ? OperatorTripVehicle.fromJson(
              Map<String, dynamic>.from(json['vehicle'] as Map),
            )
          : null,
      staff: json['staff'] is Map
          ? OperatorTripStaffBlock.fromJson(
              Map<String, dynamic>.from(json['staff'] as Map),
            )
          : null,
      tripPlan: json['trip_plan'] is Map
          ? OperatorTripPlanBrief.fromJson(
              Map<String, dynamic>.from(json['trip_plan'] as Map),
            )
          : null,
      remarks: json['remarks']?.toString(),
      // Backend now sends `waste_types` (plural list); resolve handles both
      // that and the legacy singular `waste_type`, never crashing on null.
      wasteType: OperatorTripWasteType.resolve(json),
      progress: OperatorTripProgress.fromJson(
        Map<String, dynamic>.from(json['progress'] as Map),
      ),
      totalWeightKg: _parseDouble(json['total_weight_kg']) ?? 0.0,
    );
  }
}

class BinCollectionEventEntry {
  final String uniqueId;
  final DateTime eventAt;
  final double collectedWeightKg;
  final String scannedQr;
  final String binName;
  final String cpName;
  final double? latitude;
  final double? longitude;
  final String? notes;
  final String eventType;
  final String? statusReason;

  const BinCollectionEventEntry({
    required this.uniqueId,
    required this.eventAt,
    required this.collectedWeightKg,
    required this.scannedQr,
    required this.binName,
    required this.cpName,
    required this.eventType,
    this.latitude,
    this.longitude,
    this.notes,
    this.statusReason,
  });

  factory BinCollectionEventEntry.fromJson(Map<String, dynamic> json) {
    final bin = json['bin'] is Map
        ? Map<String, dynamic>.from(json['bin'] as Map)
        : const <String, dynamic>{};
    final cp = json['collection_point'] is Map
        ? Map<String, dynamic>.from(json['collection_point'] as Map)
        : const <String, dynamic>{};
    return BinCollectionEventEntry(
      uniqueId: json['unique_id']?.toString() ?? '',
      eventAt: _parseDate(json['event_at']) ??
          _parseDate(json['created_at']) ??
          DateTime.now(),
      collectedWeightKg: _parseDouble(json['collected_weight_kg']) ?? 0.0,
      scannedQr:
          json['scanned_qr']?.toString() ?? bin['unique_id']?.toString() ?? '',
      binName: bin['bin_name']?.toString() ?? '',
      cpName: cp['name']?.toString() ?? '',
      eventType: json['event_type']?.toString() ?? 'Collected',
      latitude: _parseDouble(json['latitude']),
      longitude: _parseDouble(json['longitude']),
      notes: json['notes']?.toString(),
      statusReason: json['status_reason']?.toString(),
    );
  }
}

class OperatorTripHistoryDetail {
  final OperatorTripHistorySummary summary;
  final List<OperatorTripCollectionPoint> collectionPoints;
  final List<BinCollectionEventEntry> events;

  const OperatorTripHistoryDetail({
    required this.summary,
    required this.collectionPoints,
    required this.events,
  });

  factory OperatorTripHistoryDetail.fromJson(Map<String, dynamic> json) {
    return OperatorTripHistoryDetail(
      summary: OperatorTripHistorySummary.fromJson(json),
      collectionPoints: (json['collection_points'] as List? ?? [])
          .map((e) => OperatorTripCollectionPoint.fromJson(
                Map<String, dynamic>.from(e as Map),
              ))
          .toList(),
      events: (json['events'] as List? ?? [])
          .map((e) => BinCollectionEventEntry.fromJson(
                Map<String, dynamic>.from(e as Map),
              ))
          .toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

double? _parseDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

int? _parseInt(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

List<double>? _parseCoordinatePair(dynamic value) {
  if (value is! List || value.length < 2) return null;
  final first = _parseDouble(value[0]);
  final second = _parseDouble(value[1]);
  if (first == null || second == null) return null;
  return [first, second];
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

/// Combine an `HH:mm[:ss[.ffff]]` time string with a base date so we can
/// compute durations across `actual_start_time` / `actual_end_time`.
DateTime? _timeToToday(String? raw, DateTime baseDate) {
  if (raw == null || raw.isEmpty) return null;
  final parts = raw.split(':');
  if (parts.length < 2) return null;
  final hh = int.tryParse(parts[0]);
  final mm = int.tryParse(parts[1]);
  if (hh == null || mm == null) return null;
  int ss = 0;
  if (parts.length >= 3) {
    final secPart = parts[2].split('.').first;
    ss = int.tryParse(secPart) ?? 0;
  }
  return DateTime(baseDate.year, baseDate.month, baseDate.day, hh, mm, ss);
}
