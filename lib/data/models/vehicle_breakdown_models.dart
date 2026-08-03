String _str(dynamic v) => v == null ? '' : v.toString().trim();

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

  bool get isPending => approvalStatus.toUpperCase() == 'PENDING';

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
    );
  }
}
