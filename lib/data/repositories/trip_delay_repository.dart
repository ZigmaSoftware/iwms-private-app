import 'dart:io';

import 'package:dio/dio.dart';

import 'package:iwms_private_app/core/api_config.dart';
import 'package:iwms_private_app/core/network/authorized_dio.dart';

/// Reporting a delay that is NOT a breakdown — a puncture, a minor repair, a
/// blocked road. The vehicle is still serviceable and the trip continues, so
/// this only files a record and pings the supervisor; nothing about the
/// assignment changes.
class TripDelayRepository {
  /// The reason codes the backend accepts, paired with driver-facing labels.
  ///
  /// Kept in the same order the backend declares them so the chips read
  /// most-likely-first for a driver (puncture and minor repair are the cases
  /// this feature was actually built for).
  static const List<({String code, String label})> reasons = [
    (code: 'PUNCTURE', label: 'Puncture / Tyre'),
    (code: 'MINOR_REPAIR', label: 'Minor repair'),
    (code: 'TRAFFIC', label: 'Traffic'),
    (code: 'ROAD_BLOCKED', label: 'Road blocked'),
    (code: 'FUEL', label: 'Refuelling'),
    (code: 'WEATHER', label: 'Weather'),
    (code: 'PUBLIC_OBSTRUCTION', label: 'Public obstruction'),
    (code: 'WAITING_AT_PLANT', label: 'Waiting at plant'),
    (code: 'OTHER', label: 'Other'),
  ];

  /// File a delay against [assignmentId].
  ///
  /// [remarks] is required by the backend — a delay with no explanation tells
  /// the supervisor nothing.
  Future<void> reportDelay({
    required String assignmentId,
    required String reason,
    required String remarks,
    required File evidenceImage,
    required double latitude,
    required double longitude,
    int? estimatedMinutes,
  }) async {
    final dio = await authorizedDio();
    try {
      await dio.post(
        ApiConfig.tripDelayReports,
        data: FormData.fromMap({
          'trip_assignment_id': assignmentId,
          'delay_reason': reason,
          'delay_remarks': remarks,
          'evidence_image': await MultipartFile.fromFile(evidenceImage.path),
          if (estimatedMinutes != null)
            'estimated_delay_minutes': estimatedMinutes,
          'delay_lat': latitude.toStringAsFixed(7),
          'delay_lng': longitude.toStringAsFixed(7),
        }),
      );
    } on DioException catch (e) {
      throw Exception(_message(e));
    }
  }

  /// One delay report, for the supervisor's review screen.
  Future<TripDelayReport> fetchReport(String uniqueId) async {
    final dio = await authorizedDio();
    try {
      final res = await dio.get('${ApiConfig.tripDelayReports}$uniqueId/');
      return TripDelayReport.fromJson(
          Map<String, dynamic>.from(res.data as Map));
    } on DioException catch (e) {
      throw Exception(_message(e, 'Could not load the delay report.'));
    }
  }

  /// Supervisor has seen the delay; the trip carries on.
  Future<TripDelayReport> acknowledge(String uniqueId, {String? remarks}) =>
      _review(uniqueId, 'acknowledge', remarks);

  /// The delay is over (repaired, road cleared…).
  Future<TripDelayReport> resolve(String uniqueId, {String? remarks}) =>
      _review(uniqueId, 'resolve', remarks);

  Future<TripDelayReport> _review(
      String uniqueId, String action, String? remarks) async {
    final dio = await authorizedDio();
    try {
      final res = await dio.patch(
        '${ApiConfig.tripDelayReports}$uniqueId/$action/',
        data: {
          if (remarks != null && remarks.trim().isNotEmpty)
            'supervisor_remarks': remarks.trim(),
        },
      );
      return TripDelayReport.fromJson(
          Map<String, dynamic>.from(res.data as Map));
    } on DioException catch (e) {
      throw Exception(_message(e, 'Could not update the delay report.'));
    }
  }

  String _message(DioException e, [String? fallback]) {
    final data = e.response?.data;
    if (data is Map) {
      // DRF field errors come back as {field: [msg]}; surface the first one
      // rather than a bare "400".
      for (final value in data.values) {
        if (value is List && value.isNotEmpty) return value.first.toString();
        if (value is String && value.isNotEmpty) return value;
      }
    }
    return fallback ??
        'Could not report the delay. Check your connection and try again.';
  }
}

/// A driver's delay report as the supervisor sees it.
class TripDelayReport {
  const TripDelayReport({
    required this.uniqueId,
    required this.reason,
    required this.remarks,
    required this.status,
    this.statusLabel = '',
    this.reportedBy = '',
    this.vehicleNo = '',
    this.location = '',
    this.estimatedMinutes,
    this.imageUrl,
    this.reportedAt,
    this.supervisorRemarks = '',
  });

  final String uniqueId;
  final String reason;
  final String remarks;

  /// REPORTED → ACKNOWLEDGED → RESOLVED.
  final String status;
  final String statusLabel;
  final String reportedBy;
  final String vehicleNo;
  final String location;
  final int? estimatedMinutes;
  final String? imageUrl;
  final DateTime? reportedAt;
  final String supervisorRemarks;

  bool get isReported => status.toUpperCase() == 'REPORTED';
  bool get isResolved => status.toUpperCase() == 'RESOLVED';

  factory TripDelayReport.fromJson(Map<String, dynamic> json) {
    String str(String key) => json[key]?.toString().trim() ?? '';
    return TripDelayReport(
      uniqueId: str('unique_id'),
      reason: str('delay_reason_display').isNotEmpty
          ? str('delay_reason_display')
          : str('delay_reason'),
      remarks: str('delay_remarks'),
      status: str('status'),
      statusLabel: str('status_display'),
      reportedBy: str('reported_by_name'),
      vehicleNo: str('vehicle_no'),
      location: str('delay_location'),
      estimatedMinutes: int.tryParse(str('estimated_delay_minutes')),
      imageUrl:
          str('evidence_image_url').isEmpty ? null : str('evidence_image_url'),
      reportedAt: DateTime.tryParse(str('created_at'))?.toLocal(),
      supervisorRemarks: str('supervisor_remarks'),
    );
  }
}
