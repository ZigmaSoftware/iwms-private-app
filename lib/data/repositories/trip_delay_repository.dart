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
    int? estimatedMinutes,
    double? latitude,
    double? longitude,
  }) async {
    final dio = await authorizedDio();
    try {
      await dio.post(
        ApiConfig.tripDelayReports,
        data: {
          'trip_assignment_id': assignmentId,
          'delay_reason': reason,
          'delay_remarks': remarks,
          if (estimatedMinutes != null)
            'estimated_delay_minutes': estimatedMinutes,
          if (latitude != null) 'delay_lat': latitude.toStringAsFixed(7),
          if (longitude != null) 'delay_lng': longitude.toStringAsFixed(7),
        },
      );
    } on DioException catch (e) {
      throw Exception(_message(e));
    }
  }

  String _message(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      // DRF field errors come back as {field: [msg]}; surface the first one
      // rather than a bare "400".
      for (final value in data.values) {
        if (value is List && value.isNotEmpty) return value.first.toString();
        if (value is String && value.isNotEmpty) return value;
      }
    }
    return 'Could not report the delay. Check your connection and try again.';
  }
}
