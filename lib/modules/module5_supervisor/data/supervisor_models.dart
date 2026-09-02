// Supervisor module data models. These mirror the backend payloads from
// `/api/v1/user-creations/supervisor-zone-map/me/` and
// `/api/v1/schedule-masters/daily-trip-assignments/`.

import 'package:iwms_private_app/data/models/operator_trip_models.dart'
    show OperatorTripCrew;

/// The zone scope a supervisor is authorised to operate in.
class SupervisorZoneScope {
  const SupervisorZoneScope({
    required this.supervisorId,
    required this.zoneIds,
    required this.zoneNames,
    this.districtId,
    this.cityId,
  });

  final String supervisorId;
  final List<String> zoneIds;
  final List<String> zoneNames;
  final String? districtId;
  final String? cityId;

  bool get isEmpty => zoneIds.isEmpty;

  factory SupervisorZoneScope.fromMeJson(Map<String, dynamic> json) {
    final zoneIds = (json['zone_ids'] as List?)
            ?.map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList() ??
        <String>[];

    final maps = (json['maps'] as List?) ?? const [];
    String? districtId;
    String? cityId;
    if (maps.isNotEmpty && maps.first is Map) {
      final first = maps.first as Map;
      districtId = first['district_id']?.toString();
      cityId = first['city_id']?.toString();
    }

    return SupervisorZoneScope(
      supervisorId: json['supervisor_id']?.toString() ?? '',
      zoneIds: zoneIds,
      zoneNames: const [],
      districtId: districtId,
      cityId: cityId,
    );
  }

  static const SupervisorZoneScope empty = SupervisorZoneScope(
    supervisorId: '',
    zoneIds: [],
    zoneNames: [],
  );
}

/// A single daily trip assignment as the supervisor sees it.
/// A single stop on an assignment's route — a bin collection point or a
/// household — unified so the detail sheet can render one Amazon-style
/// timeline regardless of collection type.
class SupervisorStop {
  const SupervisorStop({
    required this.uniqueId,
    required this.sequence,
    required this.isHousehold,
    required this.name,
    required this.isCollected,
    required this.status,
    this.entityId,
    this.binId,
    this.qrImageUrl,
    this.subtitle,
    this.statusReason,
    this.collectedAt,
    this.collectedWeightKg,
    this.imageUrl,
  });

  final String uniqueId;
  final int sequence;
  final bool isHousehold;
  final String name; // bin name, or household/customer name
  final String? entityId;
  final String? binId;
  final String? qrImageUrl;
  final String? subtitle; // household address; null for bins
  final bool isCollected;
  final String
      status; // Pending / Collected / Not Available / Collect Later / Skipped
  final String? statusReason;
  final DateTime? collectedAt;
  final double? collectedWeightKg;
  // Proof photo captured during collection. Bin collection points never carry
  // one today (the feature is bin-side planned, not yet implemented); a
  // household stop carries one only if the driver's weighment attached a
  // photo. Null in both cases means "no photo", never an error state.
  final String? imageUrl;

  bool get isSkippedOrDeferred =>
      !isCollected &&
      const {'not available', 'collect later', 'skipped'}
          .contains(status.trim().toLowerCase());

  factory SupervisorStop.fromBinJson(Map<String, dynamic> json) {
    final bin = (json['bin'] as Map?) ?? const {};
    return SupervisorStop(
      uniqueId: json['unique_id']?.toString() ?? '',
      sequence: _parseInt(json['sequence']) ?? 0,
      isHousehold: false,
      name: bin['bin_name']?.toString() ?? 'Collection point',
      entityId: json['collection_point_id']?.toString(),
      binId: json['bin_id']?.toString(),
      qrImageUrl: bin['bin_qr']?.toString(),
      isCollected: json['is_collected'] == true,
      status: json['status']?.toString() ?? 'Pending',
      statusReason: json['status_reason']?.toString(),
      collectedAt: _parseDate(json['collected_at']),
      collectedWeightKg: _parseDouble(json['collected_weight_kg']),
      imageUrl: json['image']?.toString(),
    );
  }

  factory SupervisorStop.fromHouseholdJson(Map<String, dynamic> json) {
    final customer = (json['customer'] as Map?) ?? const {};
    final addressParts = [customer['building_no'], customer['street']]
        .whereType<String>()
        .where((p) => p.trim().isNotEmpty)
        .join(', ');
    return SupervisorStop(
      uniqueId: json['unique_id']?.toString() ?? '',
      sequence: _parseInt(json['sequence']) ?? 0,
      isHousehold: true,
      name: customer['customer_name']?.toString() ?? 'Household',
      entityId: json['customer_id']?.toString(),
      qrImageUrl: customer['qr_code']?.toString(),
      subtitle: addressParts.isNotEmpty ? addressParts : null,
      isCollected: json['is_collected'] == true,
      status: json['status']?.toString() ?? 'Pending',
      statusReason: json['status_reason']?.toString(),
      collectedAt: _parseDate(json['collected_at']),
      collectedWeightKg: _parseDouble(json['collected_weight_kg']),
      imageUrl: json['image']?.toString(),
    );
  }

  static int? _parseInt(dynamic value) =>
      value == null ? null : int.tryParse(value.toString());

  static double? _parseDouble(dynamic value) =>
      value == null ? null : double.tryParse(value.toString());

  static DateTime? _parseDate(dynamic value) =>
      value == null ? null : DateTime.tryParse(value.toString());
}

class SupervisorAssignment {
  const SupervisorAssignment({
    required this.uniqueId,
    required this.areaName,
    required this.zoneId,
    required this.zoneName,
    required this.wardName,
    required this.tripCode,
    required this.wasteTypeName,
    required this.vehicleNo,
    required this.driverName,
    required this.operatorName,
    required this.status,
    required this.approvalStatus,
    required this.tripDate,
    required this.scheduledTime,
    required this.remarks,
    this.stops = const [],
    this.staffTemplateId,
    this.crew,
    this.hasBin = false,
    this.hasHousehold = false,
    this.hasBulk = false,
    this.tripCount = 1,
    this.totalTripTimeSeconds,
  });

  final String uniqueId;
  final String areaName;
  final String zoneId;
  final String zoneName;
  final String wardName;
  final String tripCode;
  final String wasteTypeName;
  final String vehicleNo;
  final String driverName;
  final String operatorName;
  final String status; // SCHEDULED / IN_PROGRESS / COMPLETED / CANCELLED
  final String approvalStatus; // PENDING / APPROVED / REJECTED
  final DateTime? tripDate;
  final String scheduledTime;
  final String remarks;
  // Bin + household stops, merged and sorted by route sequence.
  final List<SupervisorStop> stops;
  final bool hasBin;
  final bool hasHousehold;
  final bool hasBulk;
  // This assignment's 1-based position among today's assignments for the
  // same trip plan — 1 for the ordinary run, 2+ for a Re-Trip continuation.
  // Only populated from the daily-trip-assignments list (not trip logs).
  final int tripCount;
  // Wall-clock duration on the trip, in whole seconds — null until started.
  final int? totalTripTimeSeconds;

  /// "Bin Collection", "Household Collection", "Bulk Waste Collection", a
  /// combination, or "Collection" if none of the flags are set.
  String get collectionTypeLabel {
    final parts = <String>[
      if (hasBin) 'Bin',
      if (hasHousehold) 'Household',
      if (hasBulk) 'Bulk Waste',
    ];
    if (parts.isEmpty) return 'Collection';
    return '${parts.join(' + ')} Collection';
  }

  // The (possibly alternative/substitute) staff template running this trip —
  // matches `SupervisorTeam.uniqueId`, so the Teams screen can tell whether a
  // given team is on a trip right now.
  final String? staffTemplateId;
  // Driver + operator (+ extras), with photo and today's attendance — reused
  // from the mobile driver app's crew model so both surfaces stay in sync.
  final OperatorTripCrew? crew;

  /// Total collected weight across every stop (bin + household) on this
  /// assignment — used by the "Waste X kg" pill on the trip card.
  double get totalCollectedWeightKg => stops.fold(
        0.0,
        (sum, stop) => sum + (stop.collectedWeightKg ?? 0),
      );

  int get binsTotal => stops.where((s) => !s.isHousehold).length;
  int get binsCollected =>
      stops.where((s) => !s.isHousehold && s.isCollected).length;

  int get stopsTotal => stops.where((s) => s.isHousehold).length;
  int get stopsCollected =>
      stops.where((s) => s.isHousehold && s.isCollected).length;

  bool get isScheduled => status.toUpperCase() == 'SCHEDULED';
  bool get isInProgress => status.toUpperCase() == 'IN_PROGRESS';
  bool get isCompleted => status.toUpperCase() == 'COMPLETED';
  bool get isCancelled => status.toUpperCase() == 'CANCELLED';
  bool get isPendingApproval => approvalStatus.toUpperCase() == 'PENDING';

  /// Human-readable status: "In Progress" instead of "IN_PROGRESS".
  String get statusLabel => status
      .split('_')
      .map((w) => w.isEmpty
          ? ''
          : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
      .join(' ');

  factory SupervisorAssignment.fromJson(Map<String, dynamic> json) {
    final tripPlan = (json['trip_plan'] as Map?) ?? const {};
    final zone = (json['zone'] as Map?) ?? const {};
    // The daily-trip-assignments endpoint returns a trip's wards as a list
    // (`wards_detail`) — a trip can technically cover more than one ward —
    // so use the first one for the single-line assignment card display.
    final wardsDetail = (json['wards_detail'] as List?) ?? const [];
    final ward = wardsDetail.isNotEmpty && wardsDetail.first is Map
        ? wardsDetail.first as Map
        : const {};
    final panchayat = (json['panchayat'] as Map?) ?? const {};
    final wasteType = (json['waste_type'] as Map?) ?? const {};
    final vehicle = (json['vehicle'] as Map?) ?? const {};
    final staff = (json['effective_staff'] as Map?) ?? const {};

    final wardName = ward['ward_name']?.toString() ??
        panchayat['panchayat_name']?.toString() ??
        '';
    final zoneName =
        zone['zone_name']?.toString() ?? ward['zone_name']?.toString() ?? '';

    final binStops = ((json['collection_points'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => SupervisorStop.fromBinJson(Map<String, dynamic>.from(m)));
    final householdStops =
        ((json['household_collection_points'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) =>
                SupervisorStop.fromHouseholdJson(Map<String, dynamic>.from(m)));
    final stops = [...binStops, ...householdStops]
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
    final collectionTypes = (json['collection_types'] as Map?) ?? const {};

    return SupervisorAssignment(
      uniqueId: json['unique_id']?.toString() ?? '',
      areaName: wardName.isNotEmpty
          ? wardName
          : (zoneName.isNotEmpty ? zoneName : 'Unassigned area'),
      zoneId:
          zone['unique_id']?.toString() ?? ward['zone_id']?.toString() ?? '',
      zoneName: zoneName,
      wardName: wardName,
      tripCode: tripPlan['display_code']?.toString() ??
          json['unique_id']?.toString() ??
          '',
      wasteTypeName: wasteType['waste_type_name']?.toString() ??
          tripPlan['waste_type_name']?.toString() ??
          '',
      vehicleNo: vehicle['vehicle_no']?.toString() ??
          tripPlan['vehicle_no']?.toString() ??
          '',
      driverName: staff['driver']?.toString() ?? '',
      operatorName: staff['operator']?.toString() ?? '',
      status: _normStatus(json['status'], fallback: 'SCHEDULED'),
      approvalStatus: json['approval_status']?.toString() ?? 'PENDING',
      tripDate: _parseDate(json['trip_date']),
      stops: stops,
      scheduledTime: json['scheduled_time']?.toString() ?? '',
      remarks: json['remarks']?.toString() ?? '',
      staffTemplateId: staff['unique_id']?.toString(),
      crew: json['crew'] is Map
          ? OperatorTripCrew.fromJson(
              Map<String, dynamic>.from(json['crew'] as Map),
            )
          : null,
      hasBin: collectionTypes['has_bin'] == true,
      hasHousehold: collectionTypes['has_household'] == true,
      hasBulk: collectionTypes['has_bulk'] == true,
      tripCount: int.tryParse(json['trip_count']?.toString() ?? '') ?? 1,
      totalTripTimeSeconds:
          int.tryParse(json['total_trip_time_seconds']?.toString() ?? ''),
    );
  }

  /// Adapts a `schedule-masters/daily-trip-logs/` payload (actuals) into the
  /// same shape as an assignment, so the History screen can reuse
  /// [SupervisorAssignmentCard] unmodified ("matching UI").
  factory SupervisorAssignment.fromTripLogJson(Map<String, dynamic> json) {
    final tripAssignment = (json['trip_assignment'] as Map?) ?? const {};
    final zone = (tripAssignment['zone'] as Map?) ?? const {};
    // daily-trip-logs returns the trip's wards as `wards_detail` (a list, same
    // shape as daily-trip-assignments) and has no nested `panchayat` map of
    // its own — the local-body/panchayat display name lives in the flat
    // `location_name` field instead (see DailyTripLogSerializer).
    final wards = (json['wards_detail'] as List?) ?? const [];
    final ward =
        wards.isNotEmpty && wards.first is Map ? wards.first as Map : const {};
    final locationName = json['location_name']?.toString() ?? '';
    final wasteType = (json['waste_type'] as Map?) ?? const {};
    final vehicle = (json['vehicle'] as Map?) ?? const {};
    final driver = (json['driver'] as Map?) ?? const {};
    final operator = (json['operator'] as Map?) ?? const {};

    final wardName = ward['ward_name']?.toString() ?? locationName;
    final zoneName = zone['zone_name']?.toString() ?? '';

    final status = _normStatus(
      tripAssignment['status'] ?? json['collection_status'],
      fallback: 'SCHEDULED',
    );

    return SupervisorAssignment(
      uniqueId: tripAssignment['unique_id']?.toString() ??
          json['unique_id']?.toString() ??
          '',
      areaName: wardName.isNotEmpty
          ? wardName
          : (zoneName.isNotEmpty ? zoneName : 'Unassigned area'),
      zoneId: zone['unique_id']?.toString() ?? '',
      zoneName: zoneName,
      wardName: wardName,
      tripCode: tripAssignment['display_code']?.toString() ??
          json['unique_id']?.toString() ??
          '',
      wasteTypeName: wasteType['waste_type_name']?.toString() ?? '',
      vehicleNo: vehicle['vehicle_no']?.toString() ?? '',
      driverName: driver['employee_name']?.toString() ?? '',
      operatorName: operator['employee_name']?.toString() ?? '',
      status: status,
      approvalStatus:
          tripAssignment['approval_status']?.toString() ?? 'APPROVED',
      tripDate: _parseDate(json['trip_date']),
      scheduledTime: tripAssignment['scheduled_time']?.toString() ??
          json['actual_start_time']?.toString() ??
          '',
      remarks: json['remarks']?.toString() ?? '',
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}

class SupervisorVehicle {
  const SupervisorVehicle({
    required this.uniqueId,
    required this.vehicleNo,
    required this.vehicleTypeName,
    required this.fuelTypeName,
    required this.capacity,
    required this.isActive,
    this.stateName,
    this.districtName,
    this.corporationName,
    this.municipalityName,
    this.townPanchayatName,
    this.panchayatUnionName,
    this.panchayatName,
  });

  final String uniqueId;
  final String vehicleNo;
  final String vehicleTypeName;
  final String fuelTypeName;
  final double? capacity;
  final bool isActive;
  final String? stateName;
  final String? districtName;
  final String? corporationName;
  final String? municipalityName;
  final String? townPanchayatName;
  final String? panchayatUnionName;
  final String? panchayatName;

  String get locationLabel {
    for (final value in [
      panchayatName,
      townPanchayatName,
      municipalityName,
      corporationName,
      panchayatUnionName,
      districtName,
      stateName,
    ]) {
      final text = value?.trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  factory SupervisorVehicle.fromJson(Map<String, dynamic> json) {
    return SupervisorVehicle(
      uniqueId: json['unique_id']?.toString() ?? '',
      vehicleNo: json['vehicle_no']?.toString() ?? '',
      vehicleTypeName: json['vehicle_type_name']?.toString() ?? '',
      fuelTypeName: json['fuel_type_name']?.toString() ?? '',
      capacity: _parseDouble(json['capacity']),
      isActive: json['is_active'] == true,
      stateName: json['state_name']?.toString(),
      districtName: json['district_name']?.toString(),
      corporationName: json['corporation_name']?.toString(),
      municipalityName: json['municipality_name']?.toString(),
      townPanchayatName: json['town_panchayat_name']?.toString(),
      panchayatUnionName: json['panchayat_union_name']?.toString(),
      panchayatName: json['panchayat_name']?.toString(),
    );
  }

  static double? _parseDouble(dynamic value) =>
      value == null ? null : double.tryParse(value.toString());
}

/// Dashboard KPI rollup derived from the day's assignments.
class SupervisorKpis {
  const SupervisorKpis({
    required this.total,
    required this.inProgress,
    required this.completed,
    required this.scheduled,
    required this.pendingReview,
  });

  final int total;
  final int inProgress;
  final int completed;
  final int scheduled;
  final int pendingReview;

  factory SupervisorKpis.fromAssignments(List<SupervisorAssignment> items) {
    return SupervisorKpis(
      total: items.length,
      inProgress: items.where((a) => a.isInProgress).length,
      completed: items.where((a) => a.isCompleted).length,
      scheduled: items.where((a) => a.isScheduled).length,
      pendingReview: items.where((a) => a.isPendingApproval).length,
    );
  }

  static const SupervisorKpis empty = SupervisorKpis(
    total: 0,
    inProgress: 0,
    completed: 0,
    scheduled: 0,
    pendingReview: 0,
  );
}

enum SupervisorAlertSeverity { info, warning, danger }

/// A single row in the dashboard activity / alerts feed.
class SupervisorAlert {
  const SupervisorAlert({
    required this.title,
    required this.subtitle,
    required this.severity,
  });

  final String title;
  final String subtitle;
  final SupervisorAlertSeverity severity;

  /// Derive a lightweight alert feed from the day's assignments.
  static List<SupervisorAlert> fromAssignments(
    List<SupervisorAssignment> items,
  ) {
    final alerts = <SupervisorAlert>[];

    final pending = items.where((a) => a.isPendingApproval).toList();
    if (pending.isNotEmpty) {
      alerts.add(SupervisorAlert(
        title: '${pending.length} assignment(s) awaiting review',
        subtitle: pending.map((a) => a.areaName).take(3).join(', '),
        severity: SupervisorAlertSeverity.warning,
      ));
    }

    final notStarted = items.where((a) => a.isScheduled).toList();
    if (notStarted.isNotEmpty) {
      alerts.add(SupervisorAlert(
        title: '${notStarted.length} trip(s) not started yet',
        subtitle: notStarted.map((a) => a.areaName).take(3).join(', '),
        severity: SupervisorAlertSeverity.info,
      ));
    }

    final cancelled = items.where((a) => a.isCancelled).toList();
    if (cancelled.isNotEmpty) {
      alerts.add(SupervisorAlert(
        title: '${cancelled.length} trip(s) cancelled today',
        subtitle: cancelled.map((a) => a.areaName).take(3).join(', '),
        severity: SupervisorAlertSeverity.danger,
      ));
    }

    return alerts;
  }
}

String _str(dynamic v) => v == null ? '' : v.toString().trim();

/// Normalise a backend status label to the UPPER_SNAKE form the UI compares
/// against. The API returns human strings ("In Progress"), but the widgets
/// test `status.toUpperCase() == 'IN_PROGRESS'` — so spaces/hyphens become
/// underscores here.
String _normStatus(dynamic v, {String fallback = ''}) {
  final s = v?.toString().trim() ?? '';
  if (s.isEmpty) return fallback;
  return s.toUpperCase().replaceAll(RegExp(r'[\s\-]+'), '_');
}

double _numKg(dynamic v) {
  if (v == null) return 0;
  return double.tryParse(v.toString()) ?? 0;
}

/// A single day's collected-waste totals (kg), bucketed by the actual waste
/// stream — Wet vs Dry — sourced from each collected bin's own waste type
/// (`BinCollectionEvent.waste_type` / `Bins.wastetype_id`), not from the
/// bin-vs-household *stop kind* the daily trip log tracks. Multiple events
/// can share a date; the chart sums them.
class SupervisorWastePoint {
  const SupervisorWastePoint({
    required this.date,
    required this.wetKg,
    required this.dryKg,
    required this.otherKg,
  });

  final DateTime date;
  final double wetKg;
  final double dryKg;
  // Anything collected under a waste type that is neither Wet nor Dry
  // (e.g. Sanitary, Bio-medical, Mixed) — kept out of the two named cards
  // but still counted in the total so the ring/total figure stays accurate.
  final double otherKg;

  double get totalKg => wetKg + dryKg + otherKg;

  factory SupervisorWastePoint.fromEventJson(Map<String, dynamic> j) {
    final date = DateTime.tryParse(_str(j['collection_date'])) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final weight = _numKg(j['collected_weight_kg']);
    final wasteType = j['waste_type'];
    final name = wasteType is Map
        ? _str(wasteType['waste_type_name']).toLowerCase()
        : '';

    return SupervisorWastePoint(
      date: date,
      wetKg: name.contains('wet') ? weight : 0,
      dryKg: name.contains('dry') ? weight : 0,
      otherKg: (name.contains('wet') || name.contains('dry')) ? 0 : weight,
    );
  }

  bool get hasValidDate => date.millisecondsSinceEpoch > 0;
}

/// One `BinCollectionEvent` row, kept in full (not just summed into
/// [SupervisorWastePoint]) so the waste-summary cards' tap-through detail
/// view can group collections by vehicle and list each one's collection
/// points/status without a second network round trip.
/// Which collection stream an event came from.
///
/// The two feeds are already fetched separately in
/// `SupervisorRepository.fetchWasteEvents` (bin-collection events vs household
/// waste collections) but the distinction used to be dropped on the floor, so
/// the summary could only ever split by waste TYPE. Tagging it at construction
/// lets the Bin / Household KPI cards aggregate without a backend change.
enum SupervisorWasteSource { bin, household }

class SupervisorWasteEvent {
  const SupervisorWasteEvent({
    required this.date,
    required this.weightKg,
    required this.wasteTypeName,
    required this.source,
    this.vehicleUniqueId,
    this.vehicleNo,
    this.collectionPointName,
    this.tripAssignmentId,
    this.status,
  });

  final DateTime date;
  final double weightKg;
  final String wasteTypeName;
  final SupervisorWasteSource source;
  final String? vehicleUniqueId;
  final String? vehicleNo;
  final String? collectionPointName;
  final String? tripAssignmentId;
  final String? status;

  bool get isWet => wasteTypeName.toLowerCase().contains('wet');
  bool get isDry => wasteTypeName.toLowerCase().contains('dry');
  bool get isBin => source == SupervisorWasteSource.bin;
  bool get isHousehold => source == SupervisorWasteSource.household;

  /// Display label for the waste stream, never blank — an unnamed type would
  /// otherwise collapse into an empty row in the breakdown list.
  String get displayTypeName =>
      wasteTypeName.trim().isEmpty ? 'Unspecified' : wasteTypeName.trim();
  bool get hasValidDate => date.millisecondsSinceEpoch > 0;

  factory SupervisorWasteEvent.fromJson(Map<String, dynamic> j) {
    final date = DateTime.tryParse(_str(j['collection_date'])) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final wasteType = j['waste_type'];
    final vehicle = j['vehicle'];
    final cp = j['collection_point'];
    return SupervisorWasteEvent(
      date: date,
      weightKg: _numKg(j['collected_weight_kg']),
      wasteTypeName: wasteType is Map ? _str(wasteType['waste_type_name']) : '',
      source: SupervisorWasteSource.bin,
      vehicleUniqueId: vehicle is Map ? _str(vehicle['unique_id']) : null,
      vehicleNo: vehicle is Map ? _str(vehicle['vehicle_no']) : null,
      collectionPointName: cp is Map ? _str(cp['cp_name']) : null,
      tripAssignmentId: _str(j['trip_assignment_id']),
      status: _str(j['status']),
    );
  }

  /// One `WasteCollection` (household) row into up to 4 synthetic events —
  /// one per non-zero waste-type bucket (`wet_waste`/`dry_waste`/
  /// `mixed_waste`/`sanitary_waste`). Unlike `BinCollectionEvent`, a
  /// household row carries all four weights on one record rather than one
  /// waste type per row, so it can't map 1:1 onto [SupervisorWasteEvent] —
  /// this fans it out to match the shape the waste-summary cards expect.
  ///
  /// There's no collection-point/vehicle on a household stop, and status is
  /// always effectively "Collected" (a WasteCollection row only exists once
  /// collected — Not Available/Collect Later never create one, see
  /// DailyTripHouseholdCollection.mark_status).
  static List<SupervisorWasteEvent> fromHouseholdCollectionJson(
    Map<String, dynamic> j,
  ) {
    final date = DateTime.tryParse(_str(j['collection_date'])) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final tripAssignmentId = _str(j['trip_assignment_id']);
    final customerName = _str(j['customer_name']);

    final buckets = <String, double>{
      'Wet Waste': _numKg(j['wet_waste']),
      'Dry Waste': _numKg(j['dry_waste']),
      'Mixed Waste': _numKg(j['mixed_waste']),
      'Sanitary Waste': _numKg(j['sanitary_waste']),
    };

    return [
      for (final entry in buckets.entries)
        if (entry.value > 0)
          SupervisorWasteEvent(
            date: date,
            weightKg: entry.value,
            wasteTypeName: entry.key,
            source: SupervisorWasteSource.household,
            collectionPointName: customerName.isEmpty ? null : customerName,
            tripAssignmentId: tripAssignmentId,
            status: 'Collected',
          ),
    ];
  }
}

/// A staff member (from `user-creations/staffcreation/`), used by the Staffs
/// list which groups people by designation.
class SupervisorStaff {
  const SupervisorStaff({
    required this.uniqueId,
    required this.empId,
    required this.name,
    required this.role,
    required this.designation,
    required this.department,
    required this.site,
    required this.mobile,
    this.attendanceStatus = '',
  });

  final String uniqueId;
  final String empId;
  final String name;
  final String role;
  final String designation;
  final String department;
  final String site;
  final String mobile;
  final String attendanceStatus;

  /// Heading this staff member is listed under in the Staffs screen.
  ///
  /// Role first ("Company Driver", "Company Supervisor") because it is always
  /// populated, then designation as a fallback for records that carry one but
  /// no role. Only when both are blank does the row land in "Unspecified".
  String get groupLabel {
    if (role.trim().isNotEmpty) return role.trim();
    if (designation.trim().isNotEmpty) return designation.trim();
    return 'Unspecified';
  }

  factory SupervisorStaff.fromJson(Map<String, dynamic> j) {
    final name = _str(j['employee_name']).isNotEmpty
        ? _str(j['employee_name'])
        : _str(j['username']);
    final designation = [
      _str(j['designation_name']),
      _str(j['designation_group']),
      _str(j['designation']),
    ].firstWhere((v) => v.isNotEmpty, orElse: () => '');
    return SupervisorStaff(
      uniqueId: _str(j['unique_id']).isNotEmpty
          ? _str(j['unique_id'])
          : _str(j['staff_unique_id']),
      empId: _str(j['emp_id']),
      name: name.isNotEmpty ? name : 'Unnamed',
      role: _str(j['staffusertype_name']),
      designation: designation,
      department: _str(j['department_name']),
      site: _str(j['site_name']),
      mobile: _str(j['contact_mobile']),
      attendanceStatus: _str(j['attendance_status']),
    );
  }
}

class SupervisorStaffAttendanceSummary {
  const SupervisorStaffAttendanceSummary({
    required this.presentCount,
    required this.absentCount,
    required this.leaveCount,
    required this.presentStaff,
    required this.absentStaff,
    required this.leaveStaff,
  });

  final int presentCount;
  final int absentCount;
  final int leaveCount;
  final List<SupervisorStaff> presentStaff;
  final List<SupervisorStaff> absentStaff;
  final List<SupervisorStaff> leaveStaff;

  List<SupervisorStaff> listFor(String filter) {
    switch (filter) {
      case 'present':
        return presentStaff;
      case 'absent':
        return absentStaff;
      case 'leave':
        return leaveStaff;
      default:
        return [...presentStaff, ...absentStaff, ...leaveStaff];
    }
  }

  factory SupervisorStaffAttendanceSummary.fromJson(Map<String, dynamic> json) {
    List<SupervisorStaff> parseList(dynamic raw) => (raw as List? ?? const [])
        .whereType<Map>()
        .map((e) => SupervisorStaff.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    return SupervisorStaffAttendanceSummary(
      presentCount: int.tryParse(json['present_count']?.toString() ?? '') ?? 0,
      absentCount: int.tryParse(json['absent_count']?.toString() ?? '') ?? 0,
      leaveCount: int.tryParse(json['leave_count']?.toString() ?? '') ?? 0,
      presentStaff: parseList(json['present_staff']),
      absentStaff: parseList(json['absent_staff']),
      leaveStaff: parseList(json['leave_staff']),
    );
  }

  static const empty = SupervisorStaffAttendanceSummary(
    presentCount: 0,
    absentCount: 0,
    leaveCount: 0,
    presentStaff: [],
    absentStaff: [],
    leaveStaff: [],
  );
}

/// A staff template (from `schedule-masters/staff-templates/`) — the "Teams"
/// list: a driver + operator (+ extra operators) grouping.
class SupervisorTeam {
  const SupervisorTeam({
    required this.uniqueId,
    required this.driverId,
    required this.operatorId,
    required this.driverName,
    required this.operatorName,
    required this.extraOperatorIds,
    required this.extraCount,
    required this.status,
    required this.approvalStatus,
  });

  final String uniqueId;
  final String driverId;
  final String operatorId;
  final String driverName;
  final String operatorName;
  final List<String> extraOperatorIds;
  final int extraCount;
  final String status;
  final String approvalStatus;

  String get label {
    final crew = [driverName, operatorName]
        .where((value) => value.trim().isNotEmpty)
        .join(' / ');
    return crew.isNotEmpty ? crew : uniqueId;
  }

  factory SupervisorTeam.fromJson(Map<String, dynamic> j) {
    final extra = j['extra_operator_id'];
    final extraIds = extra is List
        ? extra
            .map((item) => item?.toString() ?? '')
            .where((item) => item.isNotEmpty)
            .toList()
        : const <String>[];
    return SupervisorTeam(
      uniqueId: _str(j['unique_id']),
      driverId: _str(j['driver_id']),
      operatorId: _str(j['operator_id']),
      driverName: _str(j['driver_name']),
      operatorName: _str(j['operator_name']),
      extraOperatorIds: extraIds,
      extraCount: extraIds.length,
      status: _str(j['status']),
      approvalStatus: _str(j['approval_status']),
    );
  }
}

/// A driver/operator dropdown option (`staff_unique_id` + display name),
/// used by the "Substitute staff" / "Form ALT" / "Add team" forms.
class SupervisorCrewOption {
  const SupervisorCrewOption({required this.uniqueId, required this.name});

  final String uniqueId;
  final String name;

  factory SupervisorCrewOption.fromJson(Map<String, dynamic> j) {
    final uid = _str(j['staff_unique_id']).isNotEmpty
        ? _str(j['staff_unique_id'])
        : _str(j['unique_id']);
    final name = _str(j['employee_name']).isNotEmpty
        ? _str(j['employee_name'])
        : _str(j['username']);
    return SupervisorCrewOption(uniqueId: uid, name: name.isEmpty ? uid : name);
  }
}

/// An `AlternativeStaffTemplate` — a staff substitution already created under
/// the supervisor's hierarchy, selectable to apply onto a trip assignment.
class SupervisorAltStaffTemplate {
  const SupervisorAltStaffTemplate({
    required this.uniqueId,
    required this.displayCode,
    required this.staffTemplateId,
    required this.driverName,
    required this.operatorName,
    required this.fromDate,
    required this.toDate,
    required this.changeReason,
    required this.approvalStatus,
  });

  final String uniqueId;
  final String displayCode;
  final String staffTemplateId;
  final String driverName;
  final String operatorName;
  final String fromDate;
  final String toDate;
  final String changeReason;
  final String approvalStatus;

  String get label {
    final range = [fromDate, toDate].where((v) => v.isNotEmpty).join(' → ');
    final crew =
        [driverName, operatorName].where((v) => v.isNotEmpty).join(' / ');
    final parts = [displayCode, crew, range].where((v) => v.isNotEmpty);
    return parts.isEmpty ? uniqueId : parts.join(' · ');
  }

  factory SupervisorAltStaffTemplate.fromJson(Map<String, dynamic> j) {
    return SupervisorAltStaffTemplate(
      uniqueId: _str(j['unique_id']),
      displayCode: _str(j['display_code']),
      staffTemplateId: _str(j['staff_template']),
      driverName: _str(j['driver_name']),
      operatorName: _str(j['operator_name']),
      fromDate: _str(j['from_date']),
      toDate: _str(j['to_date']),
      changeReason: _str(j['change_reason']),
      approvalStatus: _str(j['approval_status']),
    );
  }
}

class SupervisorCollectionPoint {
  const SupervisorCollectionPoint({
    required this.uniqueId,
    required this.name,
    required this.collectionType,
    required this.panchayatName,
    required this.municipalityName,
    required this.areaTypeName,
    required this.latitude,
    required this.longitude,
    required this.binCount,
    required this.binQrUrl,
    required this.isActive,
  });

  final String uniqueId;
  final String name;
  final String collectionType;
  final String panchayatName;
  final String municipalityName;
  final String areaTypeName;
  final String latitude;
  final String longitude;
  final int binCount;
  final String binQrUrl;
  final bool isActive;

  String get scopeLabel {
    for (final value in [panchayatName, municipalityName, areaTypeName]) {
      if (value.trim().isNotEmpty) return value;
    }
    return 'Unassigned area';
  }

  factory SupervisorCollectionPoint.fromJson(Map<String, dynamic> j) {
    final bins = j['bins_detail'];
    final firstBin = bins is List && bins.isNotEmpty && bins.first is Map
        ? Map<String, dynamic>.from(bins.first as Map)
        : const <String, dynamic>{};
    return SupervisorCollectionPoint(
      uniqueId: _str(j['unique_id']),
      name: _str(j['cp_name']).isNotEmpty
          ? _str(j['cp_name'])
          : 'Collection point',
      collectionType: _str(j['collection_type']),
      panchayatName: _str(j['panchayat_name']),
      municipalityName: _str(j['municipality_name']),
      areaTypeName: _str(j['area_type_name']),
      latitude: _str(j['latitude']),
      longitude: _str(j['longitude']),
      binCount: bins is List ? bins.length : 0,
      binQrUrl: _str(firstBin['bin_qr']),
      isActive: j['is_active'] == true,
    );
  }
}

class SupervisorHousehold {
  const SupervisorHousehold({
    required this.uniqueId,
    required this.name,
    required this.contactNo,
    required this.buildingNo,
    required this.street,
    required this.area,
    required this.panchayatName,
    required this.municipalityName,
    required this.areaTypeName,
    required this.qrCodeUrl,
    required this.isActive,
    required this.latitude,
    required this.longitude,
  });

  final String uniqueId;
  final String name;
  final String contactNo;
  final String buildingNo;
  final String street;
  final String area;
  final String panchayatName;
  final String municipalityName;
  final String areaTypeName;
  final String qrCodeUrl;
  final bool isActive;
  final String latitude;
  final String longitude;

  String get address {
    final parts = [buildingNo, street, area]
        .where((part) => part.trim().isNotEmpty)
        .toList();
    return parts.isEmpty ? 'Address not available' : parts.join(', ');
  }

  String get scopeLabel {
    for (final value in [panchayatName, municipalityName, areaTypeName]) {
      if (value.trim().isNotEmpty) return value;
    }
    return 'Unassigned area';
  }

  factory SupervisorHousehold.fromJson(Map<String, dynamic> j) {
    return SupervisorHousehold(
      uniqueId: _str(j['unique_id']),
      name: _str(j['customer_name']).isNotEmpty
          ? _str(j['customer_name'])
          : 'Household',
      contactNo: _str(j['contact_no']),
      buildingNo: _str(j['building_no']),
      street: _str(j['street']),
      area: _str(j['area']),
      panchayatName: _str(j['panchayat_name']),
      municipalityName: _str(j['municipality_name']),
      areaTypeName: _str(j['area_type_name']),
      qrCodeUrl: _str(j['qr_code']),
      isActive: j['is_active'] == true,
      latitude: _str(j['latitude']),
      longitude: _str(j['longitude']),
    );
  }
}
