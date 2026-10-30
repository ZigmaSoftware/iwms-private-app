// Supervisor module data models. These mirror the backend payloads from
// `/api/v1/staff-creations/supervisor-zone-map/me/` (never wired — see SupervisorRepository.fetchMyZoneScope) and
// `/api/v1/schedule-operations/daily-trip-assignments/`.

import 'package:iwms_private_app/data/models/operator_trip_models.dart'
    show OperatorTripCrew, OperatorTripCrewMember;

class SupervisorServiceNotice {
  const SupervisorServiceNotice({
    required this.uniqueId,
    required this.reasonCode,
    required this.reasonLabel,
    required this.reasonText,
    required this.staffRecipientCount,
    required this.customerRecipientCount,
  });

  final String uniqueId;
  final String reasonCode;
  final String reasonLabel;
  final String reasonText;
  final int staffRecipientCount;
  final int customerRecipientCount;

  String get explanation =>
      reasonText.trim().isNotEmpty ? reasonText.trim() : reasonLabel;

  factory SupervisorServiceNotice.fromJson(Map<String, dynamic> json) =>
      SupervisorServiceNotice(
        uniqueId: json['unique_id']?.toString() ?? '',
        reasonCode: json['reason_code']?.toString() ?? '',
        reasonLabel: json['reason_label']?.toString() ?? 'Operational issue',
        reasonText: json['reason_text']?.toString() ?? '',
        staffRecipientCount:
            int.tryParse('${json['staff_recipient_count'] ?? 0}') ?? 0,
        customerRecipientCount:
            int.tryParse('${json['customer_recipient_count'] ?? 0}') ?? 0,
      );
}

class SupervisorPlanOption {
  const SupervisorPlanOption({
    required this.tripPlanId,
    required this.displayCode,
    required this.collectionType,
    required this.scheduledTime,
    required this.state,
    required this.vehicleNo,
    required this.teamCode,
    required this.driverName,
    required this.operatorName,
    required this.areaName,
    this.assignmentId,
    this.blockingReason,
    this.notice,
    this.teamMembers = const [],
  });

  final String tripPlanId;
  final String displayCode;
  final String collectionType;
  final String scheduledTime;
  final String state;
  final String vehicleNo;
  final String teamCode;
  final String driverName;
  final String operatorName;
  final String areaName;
  final String? assignmentId;
  final String? blockingReason;
  final SupervisorServiceNotice? notice;

  /// Driver, operator and extra operators of the plan's team, with photos.
  final List<OperatorTripCrewMember> teamMembers;

  bool get needsAssignment => state == 'NEEDS_ASSIGNMENT';
  bool get noCollection => state == 'NO_COLLECTION';
  bool get blocked => state == 'BLOCKED' || state == 'NOT_SCHEDULED';
  bool get canDeclareNoCollection =>
      !noCollection &&
      state != 'NOT_SCHEDULED' &&
      state.toLowerCase() != 'in progress' &&
      state.toLowerCase() != 'completed';
  String get collectionLabel {
    if (collectionType == 'household_collection') return 'Household';
    if (collectionType == 'bin_collection') return 'Bin collection';
    if (collectionType == 'bulk_waste_collection') return 'Bulk waste';
    return 'Collection';
  }

  factory SupervisorPlanOption.fromJson(Map<String, dynamic> json) {
    final wards = (json['ward_names'] as List? ?? const [])
        .map((e) => e.toString())
        .where((e) => e.trim().isNotEmpty)
        .toList();
    final noticeJson = json['notice'];
    return SupervisorPlanOption(
      tripPlanId: json['trip_plan_id']?.toString() ?? '',
      displayCode: json['display_code']?.toString() ?? 'Trip Plan',
      collectionType: json['collection_type']?.toString() ?? '',
      scheduledTime: json['scheduled_time']?.toString() ?? '',
      state: json['state']?.toString() ?? 'BLOCKED',
      assignmentId: json['assignment_id']?.toString(),
      blockingReason: json['blocking_reason']?.toString(),
      vehicleNo: json['vehicle_no']?.toString() ?? 'Vehicle not assigned',
      teamCode: json['team_code']?.toString() ?? 'Team not assigned',
      driverName: json['driver_name']?.toString() ?? '',
      operatorName: json['operator_name']?.toString() ?? '',
      areaName: wards.isNotEmpty
          ? wards
              .map((w) => w.toLowerCase().startsWith('ward') ? w : 'Ward $w')
              .join(', ')
          : (json['zone_name']?.toString() ?? 'Assigned service area'),
      notice: noticeJson is Map
          ? SupervisorServiceNotice.fromJson(
              Map<String, dynamic>.from(noticeJson))
          : null,
      teamMembers: (json['team_members'] as List? ?? const [])
          .whereType<Map>()
          .map((m) =>
              OperatorTripCrewMember.fromJson(Map<String, dynamic>.from(m)))
          .toList(),
    );
  }
}

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
enum TripAlertSeverity { critical, warning, info }

enum TripAlertKind {
  breakdown,
  vehicleBlocked,
  retrip,
  rejected,
  noDriver,
  noVehicle,
  startOverdue,
  delay,
  customersWaiting,
  awaitingClosure,
}

/// One open problem (or notice) on a trip, shown in the card's alerts row and
/// the alerts sheet.
class SupervisorTripAlert {
  const SupervisorTripAlert({
    required this.kind,
    required this.title,
    required this.short,
    this.detail = '',
    this.time,
    this.waitingStops = const [],
    this.refId,
    this.imageUrls = const [],
    this.date,
  });

  final TripAlertKind kind;
  final String title;

  /// Fits the card's one-line alerts row: "Vehicle breakdown".
  final String short;
  final String detail;

  /// "15:31" when the source records when it happened.
  final String? time;

  /// Only for [TripAlertKind.customersWaiting].
  final List<SupervisorStop> waitingStops;

  /// The breakdown / delay report this alert is about, so the sheet can open
  /// that exact record.
  final String? refId;

  /// Evidence photos the driver attached.
  final List<String> imageUrls;

  /// The trip's date, for alerts whose action depends on it (Change vehicle
  /// lists vehicles free on that date).
  final DateTime? date;

  /// Customers waiting count once per customer, everything else once.
  int get count => waitingStops.isEmpty ? 1 : waitingStops.length;

  TripAlertSeverity get severity => switch (kind) {
        TripAlertKind.breakdown ||
        TripAlertKind.vehicleBlocked ||
        TripAlertKind.retrip ||
        TripAlertKind.rejected ||
        TripAlertKind.noDriver ||
        TripAlertKind.noVehicle =>
          TripAlertSeverity.critical,
        TripAlertKind.startOverdue ||
        TripAlertKind.delay =>
          TripAlertSeverity.warning,
        TripAlertKind.customersWaiting ||
        TripAlertKind.awaitingClosure =>
          TripAlertSeverity.info,
      };
}

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
    this.customerAvailableAt,
    this.customerAvailableNote,
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

  /// Household only: when the customer tapped "I'm home now" in the citizen
  /// app after the stop was marked Collect Later.
  final DateTime? customerAvailableAt;
  final String? customerAvailableNote;

  /// The customer says they're home and the crew hasn't resolved it yet.
  bool get customerWaiting =>
      customerAvailableAt != null &&
      !isCollected &&
      const {'collect later', 'skipped', 'pending'}
          .contains(status.trim().toLowerCase());

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
      customerAvailableAt: _parseDate(json['customer_available_at']),
      customerAvailableNote: json['customer_available_note']?.toString(),
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
    this.areaIsWard = false,
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
    this.actualStartAt,
    this.actualEndAt,
    this.actualStartTime = '',
    this.actualEndTime = '',
    this.breakdownInfo = const {},
    this.retripInfo = const {},
    this.tripLogSummary = const {},
    this.staffSource = '',
    this.tripEvents = const [],
    this.tripPlanId = '',
    this.vehicleUnderBreakdown = false,
  });

  final String uniqueId;
  final String areaName;
  final String zoneId;
  final String zoneName;
  final String wardName;

  /// True when [wardName] came from the trip's ward — false when it fell
  /// back to the panchayat / location name — so the UI only says "Ward"
  /// when it really is one.
  final bool areaIsWard;
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
  final DateTime? actualStartAt;
  final DateTime? actualEndAt;
  final String actualStartTime;
  final String actualEndTime;
  final Map<String, dynamic> breakdownInfo;
  final Map<String, dynamic> retripInfo;
  final Map<String, dynamic> tripLogSummary;
  final String staffSource;
  final List<Map<String, dynamic>> tripEvents;

  /// The Trip Plan this daily trip was generated from.
  final String tripPlanId;

  /// Not started and its vehicle is under breakdown, so the driver can't
  /// start it until the trip moves to another vehicle or the vehicle is
  /// marked repaired (backend `vehicle_under_breakdown`).
  final bool vehicleUnderBreakdown;

  bool get isRemaining => !isCompleted && !isCancelled;
  int get collectedCount => stops.where((s) => s.isCollected).length;
  int get unavailableCount => stops
      .where((s) =>
          !s.isCollected &&
          {'missed', 'not available'}.contains(s.status.toLowerCase()))
      .length;
  int get deferredCount => stops
      .where((s) =>
          !s.isCollected &&
          {'skipped', 'collect later'}.contains(s.status.toLowerCase()))
      .length;
  int get unresolvedCount => stops.length - collectedCount - unavailableCount;

  /// Households whose customer tapped "I'm home now" and is still waiting.
  int get customersWaitingCount => stops.where((s) => s.customerWaiting).length;
  bool get awaitingClosure =>
      isInProgress && stops.isNotEmpty && unresolvedCount == 0;
  bool get hasPendingBreakdown =>
      breakdownInfo['approval_status']?.toString().toUpperCase() == 'PENDING';
  bool get hasPendingRetrip =>
      retripInfo['status']?.toString().toUpperCase() == 'PENDING';

  /// Titles of everything on this trip that needs a look — the Trips tab's
  /// "Needs attention" filter only checks whether this is empty.
  List<String> attentionLabels(DateTime serverNow) =>
      alerts(serverNow).map((a) => a.title).toList();

  /// Every open alert on this trip, most severe first. Customers waiting
  /// collapse into one alert carrying the stops, so a route with 300
  /// "I'm home now" taps is still one row.
  ///
  /// Uses the server's local wall clock, never the device's date or timezone.
  List<SupervisorTripAlert> alerts(DateTime serverNow) {
    if (!isRemaining) return const [];
    final alerts = <SupervisorTripAlert>[];
    if (hasPendingBreakdown) {
      alerts.add(SupervisorTripAlert(
        kind: TripAlertKind.breakdown,
        title: 'Vehicle breakdown needs review',
        short: 'Vehicle breakdown',
        detail: [
          breakdownInfo['breakdown_reason'],
          breakdownInfo['breakdown_vehicle_no'] ?? vehicleNo,
        ].where((v) => v != null && v.toString().trim().isNotEmpty).join(' · '),
        time: _clock(breakdownInfo['breakdown_time']),
        refId: breakdownInfo['unique_id']?.toString(),
        imageUrls: (breakdownInfo['photos'] as List? ?? const [])
            .map((u) => u.toString())
            .where((u) => u.isNotEmpty)
            .toList(),
      ));
    }
    // A pending breakdown on this trip already has its own Review action;
    // this one is for trips blocked by a breakdown reported elsewhere, or
    // left on the broken vehicle at approval.
    if (vehicleUnderBreakdown && !hasPendingBreakdown) {
      alerts.add(SupervisorTripAlert(
        kind: TripAlertKind.vehicleBlocked,
        title: 'Vehicle under breakdown',
        short: 'Vehicle under breakdown',
        detail: '${vehicleNo.isEmpty ? 'The vehicle' : vehicleNo} can\'t '
            'start this trip. Change the vehicle, or mark it repaired.',
        refId: uniqueId,
        date: tripDate,
      ));
    }
    if (hasPendingRetrip) {
      alerts.add(const SupervisorTripAlert(
        kind: TripAlertKind.retrip,
        title: 'Re-Trip decision needed',
        short: 'Re-Trip decision',
        detail: 'The driver asked to continue this route on another trip',
      ));
    }
    if (approvalStatus.toUpperCase() == 'REJECTED') {
      alerts.add(const SupervisorTripAlert(
        kind: TripAlertKind.rejected,
        title: 'Assignment rejected',
        short: 'Assignment rejected',
        detail: 'Resolve it before the driver can start',
      ));
    }
    if (driverName.isEmpty) {
      alerts.add(const SupervisorTripAlert(
        kind: TripAlertKind.noDriver,
        title: 'No driver assigned',
        short: 'No driver',
        detail: 'Assign a driver before the trip can start',
      ));
    }
    if (vehicleNo.isEmpty) {
      alerts.add(const SupervisorTripAlert(
        kind: TripAlertKind.noVehicle,
        title: 'No vehicle assigned',
        short: 'No vehicle',
        detail: 'Assign a vehicle before the trip can start',
      ));
    }
    if (isScheduled && tripDate != null && scheduledTime.isNotEmpty) {
      final parts = scheduledTime.split(':');
      final hour = int.tryParse(parts.first);
      final minute = parts.length > 1 ? int.tryParse(parts[1]) : null;
      if (hour != null && minute != null) {
        final scheduled = DateTime(
            tripDate!.year, tripDate!.month, tripDate!.day, hour, minute);
        final wallNow = DateTime(serverNow.year, serverNow.month, serverNow.day,
            serverNow.hour, serverNow.minute);
        final late = wallNow.difference(scheduled).inMinutes;
        if (late > 0) {
          final lateText =
              late >= 60 ? '${late ~/ 60}h ${late % 60}m' : '${late}m';
          final time = scheduledTime.length > 5
              ? scheduledTime.substring(0, 5)
              : scheduledTime;
          alerts.add(SupervisorTripAlert(
            kind: TripAlertKind.startOverdue,
            title: 'Start overdue · $lateText',
            short: 'Start overdue · $lateText',
            detail: driverName.isEmpty
                ? 'The $time trip has not started'
                : '$driverName has not started the $time trip',
          ));
        }
      }
    }
    for (final e in tripEvents) {
      final label = e['label']?.toString() ?? '';
      if (!label.startsWith('Delay:') ||
          e['status']?.toString().toUpperCase() == 'RESOLVED') {
        continue;
      }
      final reason = label.substring('Delay:'.length).trim();
      alerts.add(SupervisorTripAlert(
        kind: TripAlertKind.delay,
        title: 'Driver reported a delay',
        short: 'Driver delay',
        detail: [reason, e['detail']]
            .where((v) => v != null && v.toString().trim().isNotEmpty)
            .join(' · '),
        time: _clock(e['at']),
        refId: e['unique_id']?.toString(),
        imageUrls: [
          if ((e['image']?.toString() ?? '').isNotEmpty) e['image'].toString(),
        ],
      ));
    }
    final waiting = stops.where((s) => s.customerWaiting).toList();
    if (waiting.isNotEmpty) {
      alerts.add(SupervisorTripAlert(
        kind: TripAlertKind.customersWaiting,
        title: waiting.length == 1
            ? 'Customer waiting for pickup'
            : 'Customers waiting for pickup',
        short: 'Customers waiting',
        detail: 'Pressed \u201cI\u2019m home now\u201d',
        waitingStops: waiting,
      ));
    }
    if (awaitingClosure) {
      alerts.add(const SupervisorTripAlert(
        kind: TripAlertKind.awaitingClosure,
        title: 'All stops resolved, awaiting trip closure',
        short: 'Awaiting closure',
        detail: 'The driver closes the trip from the driver app',
      ));
    }
    alerts.sort((a, b) => a.severity.index.compareTo(b.severity.index));
    return alerts;
  }

  /// "15:31" from an ISO timestamp or a bare "15:31:07" time.
  static String? _clock(dynamic value) {
    if (value == null) return null;
    final raw = value.toString();
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) {
      final local = parsed.isUtc ? parsed.toLocal() : parsed;
      return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }
    final m = RegExp(r'^(\d{2}):(\d{2})').firstMatch(raw);
    return m == null ? null : '${m[1]}:${m[2]}';
  }

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
    final wardsDetail =
        (json['wards_detail'] as List?) ?? (json['wards'] as List?) ?? const [];
    final ward = wardsDetail.isNotEmpty && wardsDetail.first is Map
        ? wardsDetail.first as Map
        : const {};
    final panchayat = (json['panchayat'] as Map?) ?? const {};
    final wasteType = (json['waste_type'] as Map?) ?? const {};
    final vehicle = (json['vehicle'] as Map?) ?? const {};
    final staff = (json['effective_staff'] as Map?) ?? const {};
    final log = (json['trip_log_summary'] as Map?) ?? const {};
    final closed = {'COMPLETED', 'CANCELLED'}
        .contains(_normStatus(json['status'], fallback: 'SCHEDULED'));

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
      areaIsWard: (ward['ward_name']?.toString() ?? '').isNotEmpty,
      tripCode: tripPlan['display_code']?.toString() ??
          json['unique_id']?.toString() ??
          '',
      wasteTypeName: wasteType['waste_type_name']?.toString() ??
          tripPlan['waste_type_name']?.toString() ??
          '',
      vehicleNo: (closed ? log['vehicle_no'] : null)?.toString() ??
          vehicle['vehicle_no']?.toString() ??
          tripPlan['vehicle_no']?.toString() ??
          '',
      driverName: (closed ? log['driver'] : null)?.toString() ??
          staff['driver']?.toString() ??
          '',
      operatorName: (closed ? log['operator'] : null)?.toString() ??
          staff['operator']?.toString() ??
          '',
      status: _normStatus(json['status'], fallback: 'SCHEDULED'),
      approvalStatus: json['approval_status']?.toString() ?? 'PENDING',
      vehicleUnderBreakdown: json['vehicle_under_breakdown'] == true,
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
      actualStartAt: _parseDate(json['actual_start_at']),
      actualEndAt: _parseDate(json['actual_end_at']),
      actualStartTime: json['actual_start_time']?.toString() ?? '',
      actualEndTime: json['actual_end_time']?.toString() ?? '',
      breakdownInfo:
          Map<String, dynamic>.from(json['breakdown_info'] as Map? ?? const {}),
      retripInfo:
          Map<String, dynamic>.from(json['retrip_info'] as Map? ?? const {}),
      tripLogSummary: Map<String, dynamic>.from(
          json['trip_log_summary'] as Map? ?? const {}),
      staffSource: staff['source']?.toString() ?? '',
      tripPlanId: json['trip_plan_id']?.toString() ??
          tripPlan['unique_id']?.toString() ??
          '',
      tripEvents: (json['trip_events'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
    );
  }

  /// Adapts a `schedule-operations/daily-trip-logs/` payload (actuals) into the
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
      areaIsWard: (ward['ward_name']?.toString() ?? '').isNotEmpty,
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

/// A staff member (from `staff-creations/staffcreation/`), used by the Staffs
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

  factory SupervisorStaffAttendanceSummary.fromStaffList(
    List<SupervisorStaff> staff,
  ) {
    final present = <SupervisorStaff>[];
    final absent = <SupervisorStaff>[];
    final leave = <SupervisorStaff>[];

    for (final member in staff) {
      final status = member.attendanceStatus.trim().toLowerCase();
      if (status.contains('leave')) {
        leave.add(member);
      } else if (status.contains('present') || status.contains('pending')) {
        present.add(member);
      } else {
        absent.add(member);
      }
    }

    return SupervisorStaffAttendanceSummary(
      presentCount: present.length,
      absentCount: absent.length,
      leaveCount: leave.length,
      presentStaff: present,
      absentStaff: absent,
      leaveStaff: leave,
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

/// A staff template (from `schedule-setup/staff-templates/`) — the "Teams"
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
    final driverId = _staffRef(j['driver_id']);
    final operatorId = _staffRef(j['operator_id']);
    final driverName = _staffName(j['driver_id'], fallback: j['driver_name']);
    final operatorName =
        _staffName(j['operator_id'], fallback: j['operator_name']);
    return SupervisorTeam(
      uniqueId: _str(j['unique_id']),
      driverId: driverId,
      operatorId: operatorId,
      driverName: driverName,
      operatorName: operatorName,
      extraOperatorIds: extraIds,
      extraCount: extraIds.length,
      status: _str(j['status']),
      approvalStatus: _str(j['approval_status']),
    );
  }

  SupervisorTeam withCrewFallback(SupervisorAssignment? assignment) {
    if (assignment == null) return this;
    final driver = assignment.crew?.driver;
    final operator = assignment.crew?.operator;
    final extraIds = extraOperatorIds.isNotEmpty
        ? extraOperatorIds
        : assignment.crew?.extraOperators
                .map((member) => member.uniqueId)
                .where((id) => id.isNotEmpty)
                .toList() ??
            const <String>[];
    return SupervisorTeam(
      uniqueId: uniqueId,
      driverId: driverId.isNotEmpty ? driverId : driver?.uniqueId ?? '',
      operatorId: operatorId.isNotEmpty ? operatorId : operator?.uniqueId ?? '',
      driverName: driverName.isNotEmpty
          ? driverName
          : (driver?.displayName.isNotEmpty == true
              ? driver!.displayName
              : assignment.driverName),
      operatorName: operatorName.isNotEmpty
          ? operatorName
          : (operator?.displayName.isNotEmpty == true
              ? operator!.displayName
              : assignment.operatorName),
      extraOperatorIds: extraIds,
      extraCount: extraIds.length,
      status: status,
      approvalStatus: approvalStatus,
    );
  }
}

String _staffRef(dynamic raw) {
  if (raw is Map) {
    return _str(raw['staff_unique_id']).isNotEmpty
        ? _str(raw['staff_unique_id'])
        : _str(raw['unique_id']);
  }
  return _str(raw);
}

String _staffName(dynamic raw, {dynamic fallback}) {
  if (raw is Map) {
    for (final key in ['employee_name', 'name', 'username']) {
      final value = _str(raw[key]);
      if (value.isNotEmpty) return value;
    }
  }
  return _str(fallback);
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
    required this.customerId,
    required this.name,
    required this.contactNo,
    required this.buildingNo,
    required this.street,
    required this.area,
    required this.zoneName,
    required this.wardName,
    required this.qrCodeUrl,
    required this.isActive,
    required this.latitude,
    required this.longitude,
    required this.companyName,
    required this.projectName,
    required this.projectLogoUrl,
    required this.apartmentName,
    required this.industryName,
    required this.blockNo,
    required this.flatNo,
    required this.villaNo,
  });

  final String uniqueId;
  final String customerId;
  final String name;
  final String contactNo;
  final String buildingNo;
  final String street;
  final String area;
  final String zoneName;
  final String wardName;
  final String qrCodeUrl;
  final bool isActive;
  final String latitude;
  final String longitude;

  // Everything below is only needed to reproduce the web door-sticker
  // template (see customerQrStickerPdf.ts) on the QR card in this app —
  // the rest of the Households screen never reads it.
  final String companyName;
  final String projectName;
  final String projectLogoUrl;
  final String apartmentName;
  final String industryName;
  final String blockNo;
  final String flatNo;
  final String villaNo;

  String get address {
    final parts = [buildingNo, street, area]
        .where((part) => part.trim().isNotEmpty)
        .toList();
    return parts.isEmpty ? 'Address not available' : parts.join(', ');
  }

  /// This project has no panchayat/municipality hierarchy — households are
  /// scoped by Zone/Ward, so that is what the list/card header shows.
  String get scopeLabel {
    for (final value in [wardName, zoneName]) {
      if (value.trim().isNotEmpty) return value;
    }
    return 'Unassigned area';
  }

  /// Building/society line for the QR card — mirrors
  /// `customerQrStickerPdf.ts`'s `stickerBuilding`. Deliberately excludes
  /// street/sub-property type when an apartment or industry name is
  /// present, same precedence as the web template.
  String get stickerBuildingLine {
    for (final value in [apartmentName, industryName, area, street]) {
      if (value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  /// Unit/house designation — mirrors `stickerUnit`.
  String get stickerUnitLine {
    final flat = [blockNo, flatNo]
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .join('-');
    if (flat.isNotEmpty) return 'Flat No: $flat';
    if (villaNo.trim().isNotEmpty) return 'No. ${villaNo.trim()}';
    if (buildingNo.trim().isNotEmpty) return 'No. ${buildingNo.trim()}';
    return customerId.isNotEmpty ? customerId : uniqueId;
  }

  /// "Zone 2 · GNO (Ward No 18)" — mirrors `stickerWardHeadline`.
  String get wardHeadline {
    var wardLabel = wardName.trim();
    final match =
        RegExp(r'^(.*?)\s*ward\s*(?:no\.?\s*)?(\S+)$', caseSensitive: false)
            .firstMatch(wardLabel);
    if (match != null) {
      final prefix = (match.group(1) ?? '').trim();
      final number = match.group(2) ?? '';
      wardLabel =
          prefix.isNotEmpty ? '$prefix (Ward No $number)' : 'Ward No $number';
    }
    final zone = zoneName.trim();
    final zoneIsRedundant =
        zone.isNotEmpty && wardLabel.toLowerCase().contains(zone.toLowerCase());
    return [if (!zoneIsRedundant) zone, wardLabel]
        .where((part) => part.isNotEmpty)
        .join(' · ');
  }

  factory SupervisorHousehold.fromJson(Map<String, dynamic> j) {
    return SupervisorHousehold(
      uniqueId: _str(j['unique_id']),
      customerId: _str(j['customer_id']),
      name: _str(j['customer_name']).isNotEmpty
          ? _str(j['customer_name'])
          : 'Household',
      contactNo: _str(j['contact_no']),
      buildingNo: _str(j['building_no']),
      street: _str(j['street']),
      area: _str(j['area']),
      zoneName: _str(j['zone_name']),
      wardName: _str(j['ward_name']),
      qrCodeUrl: _str(j['qr_code']),
      isActive: j['is_active'] == true,
      latitude: _str(j['latitude']),
      longitude: _str(j['longitude']),
      companyName: _str(j['company_name']),
      projectName: _str(j['project_name']),
      projectLogoUrl: _str(j['project_logo']),
      apartmentName: _str(j['apartment_name']),
      industryName: _str(j['industry_name']),
      blockNo: _str(j['block_no']),
      flatNo: _str(j['flat_no']),
      villaNo: _str(j['villa_no']),
    );
  }
}
