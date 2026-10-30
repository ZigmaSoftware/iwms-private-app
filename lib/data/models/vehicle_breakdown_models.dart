import 'package:iwms_private_app/data/models/trip_retrip_models.dart';

String _str(dynamic v) => v == null ? '' : v.toString().trim();

/// "HH:MM" from "HH:MM:SS"; empty stays empty.
String _hhmm(dynamic v) {
  final s = _str(v);
  return s.length > 5 ? s.substring(0, 5) : s;
}

List<String> _strList(dynamic v) =>
    v is List ? v.map(_str).where((s) => s.isNotEmpty).toList() : const [];

List<Map<String, dynamic>> _maps(dynamic v) => v is List
    ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : const [];

/// A driver/operator/vehicle dropdown option (unique id + display label),
/// used by the "vehicle breakdown" report form on both driver and supervisor
/// apps.
class VehicleBreakdownOption {
  const VehicleBreakdownOption({required this.uniqueId, required this.label});

  final String uniqueId;
  final String label;

  factory VehicleBreakdownOption.staffFromJson(Map<String, dynamic> j) {
    return VehicleBreakdownOption(
      uniqueId: _str(j['staff_unique_id']),
      label: _str(j['employee_name']),
    );
  }

  factory VehicleBreakdownOption.vehicleFromJson(Map<String, dynamic> j) {
    final capacity = j['capacity'];
    final label = capacity == null
        ? _str(j['vehicle_no'])
        : '${_str(j['vehicle_no'])} ($capacity kg)';
    return VehicleBreakdownOption(uniqueId: _str(j['unique_id']), label: label);
  }
}

/// A `VehicleBreakdown` report — driver-reported breakdown + replacement
/// plan, awaiting (or already given) supervisor approval.
class VehicleBreakdownReport {
  const VehicleBreakdownReport({
    required this.uniqueId,
    required this.tripAssignmentId,
    required this.breakdownVehicleNo,
    required this.replacementVehicleNo,
    required this.originalDriverName,
    required this.originalOperatorName,
    required this.replacementDriverName,
    required this.replacementOperatorName,
    required this.breakdownReason,
    required this.breakdownLocation,
    required this.breakdownTime,
    required this.status,
    required this.approvalStatus,
    required this.rejectionRemarks,
    required this.photoUrls,
    this.repairedAt = '',
    this.repairedByName = '',
    this.repairRemarks = '',
    this.breakdownVehicleOperationalStatus = '',
    this.pendingBins = const [],
    this.pendingHouseholdCount = 0,
  });

  final String uniqueId;
  final String tripAssignmentId;
  final String breakdownVehicleNo;
  final String replacementVehicleNo;
  final String originalDriverName;
  final String originalOperatorName;
  final String replacementDriverName;
  final String replacementOperatorName;
  final String breakdownReason;
  final String breakdownLocation;
  final String breakdownTime;
  final String status;
  final String approvalStatus;
  final String rejectionRemarks;
  final List<String> photoUrls;
  final String repairedAt;
  final String repairedByName;
  final String repairRemarks;

  /// The broken vehicle's current `operational_status` (`ACTIVE` /
  /// `BREAKDOWN`).
  final String breakdownVehicleOperationalStatus;

  /// Bin stops still outstanding on the broken trip — the supervisor picks
  /// which carry over at approval. Households always carry over.
  final List<RetripPendingStop> pendingBins;
  final int pendingHouseholdCount;

  bool get isPending => approvalStatus.toUpperCase() == 'PENDING';
  bool get isApproved => approvalStatus.toUpperCase() == 'APPROVED';
  bool get isRepaired => repairedAt.isNotEmpty;

  /// An approved breakdown keeps the vehicle in BREAKDOWN until a
  /// supervisor marks it repaired (`PATCH .../mark-repaired/`).
  bool get canMarkRepaired => isApproved && !isRepaired;

  static String _detailName(dynamic detail) {
    if (detail is Map) {
      return _str(detail['employee_name']).isNotEmpty
          ? _str(detail['employee_name'])
          : _str(detail['name']);
    }
    return '';
  }

  static String _detailVehicleNo(dynamic detail) {
    if (detail is Map) return _str(detail['vehicle_no']);
    return '';
  }

  factory VehicleBreakdownReport.fromJson(Map<String, dynamic> j) {
    final rawPhotos = j['photos'];
    final photoUrls = rawPhotos is List
        ? rawPhotos
            .whereType<Map>()
            .map((p) => _str(p['photo']))
            .where((url) => url.isNotEmpty)
            .toList()
        : <String>[];
    return VehicleBreakdownReport(
      uniqueId: _str(j['unique_id']),
      tripAssignmentId: _str(j['trip_assignment_id']),
      breakdownVehicleNo: _detailVehicleNo(j['breakdown_vehicle_detail']),
      replacementVehicleNo: _detailVehicleNo(j['replacement_vehicle_detail']),
      originalDriverName: _detailName(j['original_driver_detail']),
      originalOperatorName: _detailName(j['original_operator_detail']),
      replacementDriverName: _detailName(j['replacement_driver_detail']),
      replacementOperatorName: _detailName(j['replacement_operator_detail']),
      breakdownReason: _str(j['breakdown_reason']),
      breakdownLocation: _str(j['breakdown_location']),
      breakdownTime: _str(j['breakdown_time']),
      status: _str(j['status']),
      approvalStatus: _str(j['approval_status']),
      rejectionRemarks: _str(j['rejection_remarks']),
      photoUrls: photoUrls,
      repairedAt: _str(j['repaired_at']),
      repairedByName: _detailName(j['repaired_by_detail']),
      repairRemarks: _str(j['repair_remarks']),
      breakdownVehicleOperationalStatus:
          _str(j['breakdown_vehicle_operational_status']),
      pendingBins: _maps(
        j['pending_stops'] is Map
            ? (j['pending_stops'] as Map)['collection_points']
            : null,
      ).map(RetripPendingStop.fromJson).toList(),
      pendingHouseholdCount: j['pending_stops'] is Map &&
              (j['pending_stops'] as Map)['households'] is List
          ? ((j['pending_stops'] as Map)['households'] as List).length
          : 0,
    );
  }
}

/// One of the broken vehicle's not-started trips, offered at approval
/// (`verify-preview` `upcoming_trips`).
class BreakdownUpcomingTrip {
  const BreakdownUpcomingTrip({
    required this.uniqueId,
    required this.tripDate,
    required this.scheduledTime,
    required this.planCode,
    required this.replacementBusyTimes,
    required this.defaultMove,
  });

  final String uniqueId;
  final String tripDate;
  final String scheduledTime;
  final String planCode;

  /// The replacement's other trips that day ("11:30"); a non-empty list is
  /// why [defaultMove] is false.
  final List<String> replacementBusyTimes;
  final bool defaultMove;

  factory BreakdownUpcomingTrip.fromJson(Map<String, dynamic> j) {
    return BreakdownUpcomingTrip(
      uniqueId: _str(j['unique_id']),
      tripDate: _str(j['trip_date']),
      scheduledTime: _hhmm(j['scheduled_time']),
      planCode: _str(j['trip_plan_display_code']),
      replacementBusyTimes: _maps(j['replacement_busy'])
          .map((b) => [_str(b['unique_id']), _hhmm(b['scheduled_time'])]
              .where((s) => s.isNotEmpty)
              .join(' at '))
          .toList(),
      defaultMove: j['default_move'] == true,
    );
  }
}

/// One of the broken vehicle's trip plans that could run on the replacement
/// from the next day until the repair (`verify-preview` `plans`).
class BreakdownPlanOption {
  const BreakdownPlanOption({
    required this.tripPlanId,
    required this.displayCode,
    required this.scheduledTime,
    required this.days,
    required this.clashes,
    required this.defaultSubstitute,
  });

  final String tripPlanId;
  final String displayCode;
  final String scheduledTime;
  final List<String> days;

  /// "Runs its own plan X at 06:00 on Mon, Wed" — the replacement's regular
  /// work on the same weekdays.
  final List<String> clashes;
  final bool defaultSubstitute;

  factory BreakdownPlanOption.fromJson(Map<String, dynamic> j) {
    return BreakdownPlanOption(
      tripPlanId: _str(j['trip_plan_id']),
      displayCode: _str(j['display_code']),
      scheduledTime: _hhmm(j['scheduled_time']),
      days: _strList(j['days']),
      clashes: _maps(j['clashes']).map((c) {
        final verb = _str(c['kind']) == 'substitution'
            ? 'Stands in for plan'
            : 'Runs its own plan';
        final time = _hhmm(c['scheduled_time']);
        final days = _strList(c['days']).join(', ');
        return [
          '$verb ${_str(c['display_code'])}',
          if (time.isNotEmpty) 'at $time',
          if (days.isNotEmpty) 'on $days',
        ].join(' ');
      }).toList(),
      defaultSubstitute: j['default_substitute'] == true,
    );
  }
}

/// What "Verify & Approve" offers for a chosen replacement vehicle
/// (`GET vehicle-breakdowns/{id}/verify-preview/`).
class BreakdownVerifyPreview {
  const BreakdownVerifyPreview({
    required this.upcomingTrips,
    required this.plans,
    required this.substituteFromDate,
  });

  final List<BreakdownUpcomingTrip> upcomingTrips;
  final List<BreakdownPlanOption> plans;
  final String substituteFromDate;

  factory BreakdownVerifyPreview.fromJson(Map<String, dynamic> j) {
    return BreakdownVerifyPreview(
      upcomingTrips:
          _maps(j['upcoming_trips']).map(BreakdownUpcomingTrip.fromJson).toList(),
      plans: _maps(j['plans']).map(BreakdownPlanOption.fromJson).toList(),
      substituteFromDate: _str(j['substitute_from_date']),
    );
  }
}
