import 'dart:io';

import 'package:dio/dio.dart';

import 'package:iwms_private_app/core/api_config.dart';
import 'package:iwms_private_app/core/network/authorized_dio.dart';
import 'package:iwms_private_app/data/models/vehicle_breakdown_models.dart';

class VehicleBreakdownException implements Exception {
  VehicleBreakdownException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The report is accessible, but the server cannot preview this replacement.
class VehicleBreakdownPreviewUnavailable extends VehicleBreakdownException {
  VehicleBreakdownPreviewUnavailable()
      : super('Other-trip preview is unavailable on this server.');
}

/// "Vehicle breakdown" report/approve/reject flow — shared between the
/// driver app (report a breakdown) and the supervisor app (approve/reject).
class VehicleBreakdownRepository {
  VehicleBreakdownRepository({Future<Dio> Function()? dioProvider})
      : _dioProvider = dioProvider ?? authorizedDio;

  final Future<Dio> Function() _dioProvider;

  static const String driverRole = 'Company Driver';
  static const String operatorRole = 'Company Operator';

  String _fmtDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  String _fmtTime(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}:'
      '${d.second.toString().padLeft(2, '0')}';

  Future<List<VehicleBreakdownOption>> fetchAvailableVehicles(
    DateTime date,
  ) async {
    try {
      final dio = await authorizedDio();
      final res = await dio.get(
        ApiConfig.vehicleBreakdownAvailableVehicles,
        queryParameters: {'date': _fmtDate(date)},
      );
      return _rawList(res.data)
          .map(VehicleBreakdownOption.vehicleFromJson)
          .toList();
    } on DioException catch (e) {
      throw VehicleBreakdownException(_message(e));
    } catch (e) {
      throw VehicleBreakdownException(e.toString());
    }
  }

  Future<List<VehicleBreakdownOption>> fetchAvailableStaff(
    DateTime date,
    String role, {
    String? breakdownId,
  }) async {
    try {
      final dio = await authorizedDio();
      final res = await dio.get(
        ApiConfig.vehicleBreakdownAvailableStaff,
        queryParameters: {
          'date': _fmtDate(date),
          'role': role,
          if (breakdownId != null && breakdownId.isNotEmpty)
            'breakdown_id': breakdownId,
        },
      );
      return _rawList(res.data)
          .map(VehicleBreakdownOption.staffFromJson)
          .toList();
    } on DioException catch (e) {
      throw VehicleBreakdownException(_message(e));
    } catch (e) {
      throw VehicleBreakdownException(e.toString());
    }
  }

  Future<void> createBreakdown({
    required String tripAssignmentId,
    required String breakdownVehicleId,
    required String breakdownReason,
    required DateTime breakdownTime,
    double? breakdownLat,
    double? breakdownLng,
    String? breakdownLocation,
    double? collectedWeightBeforeBreakdownKg,
    String? breakdownRemarks,
    List<File>? photos,
  }) async {
    try {
      final dio = await authorizedDio();
      final fields = <String, dynamic>{
        'trip_assignment_id': tripAssignmentId,
        'breakdown_vehicle_id': breakdownVehicleId,
        'breakdown_reason': breakdownReason,
        'breakdown_time': _fmtTime(breakdownTime),
        // The server stores 7 decimal places (10 digits); raw GPS has more.
        if (breakdownLat != null && breakdownLat.isFinite)
          'breakdown_lat': breakdownLat.toStringAsFixed(7),
        if (breakdownLng != null && breakdownLng.isFinite)
          'breakdown_lng': breakdownLng.toStringAsFixed(7),
        if (breakdownLocation != null && breakdownLocation.trim().isNotEmpty)
          'breakdown_location': breakdownLocation,
        if (collectedWeightBeforeBreakdownKg != null)
          'collected_weight_before_breakdown_kg':
              collectedWeightBeforeBreakdownKg,
        if (breakdownRemarks != null && breakdownRemarks.trim().isNotEmpty)
          'breakdown_remarks': breakdownRemarks,
      };

      if (photos != null && photos.isNotEmpty) {
        final formData = FormData.fromMap(fields);
        for (final photo in photos) {
          formData.files.add(MapEntry(
            'photos',
            await MultipartFile.fromFile(photo.path,
                filename: photo.uri.pathSegments.last),
          ));
        }
        await dio.post(ApiConfig.vehicleBreakdowns, data: formData);
      } else {
        await dio.post(ApiConfig.vehicleBreakdowns, data: fields);
      }
    } on DioException catch (e) {
      throw VehicleBreakdownException(_message(e));
    } catch (e) {
      throw VehicleBreakdownException(e.toString());
    }
  }

  Future<List<VehicleBreakdownReport>> fetchBreakdowns({
    String? approvalStatus,
    bool mine = false,
  }) async {
    try {
      final dio = await authorizedDio();
      var res = await dio.get(
        ApiConfig.vehicleBreakdowns,
        queryParameters: {
          if (mine) 'mine': 'true',
          if (approvalStatus != null) 'approval_status': approvalStatus,
        },
      );
      final rows = <Map<String, dynamic>>[];
      final seenPages = <String>{};
      while (true) {
        if (res.data is! List &&
            (res.data is! Map ||
                (res.data['results'] is! List && res.data['data'] is! List))) {
          throw const FormatException('Invalid reports response');
        }
        rows.addAll(_rawList(res.data));
        final next = res.data is Map ? res.data['next'] : null;
        if (next == null || next == '') break;
        if (!seenPages.add(next.toString())) {
          throw const FormatException('Repeated reports page');
        }
        final current = Uri.parse(ApiConfig.vehicleBreakdowns);
        final url = current.resolve(next.toString());
        if (url.origin != current.origin) {
          throw const FormatException('Invalid reports page');
        }
        res = await dio.get(url.toString());
      }
      return rows.map(VehicleBreakdownReport.fromJson).toList();
    } on DioException catch (e) {
      throw VehicleBreakdownException(_message(e));
    } catch (e) {
      throw VehicleBreakdownException(e.toString());
    }
  }

  /// The broken vehicle's other trips and trip plans, with the work the
  /// chosen replacement already has then — what approval can move.
  Future<BreakdownVerifyPreview> fetchVerifyPreview(
    String uniqueId, {
    required String replacementVehicleId,
  }) async {
    try {
      final dio = await _dioProvider();
      final Response<dynamic> res;
      try {
        res = await dio.get(
          '${ApiConfig.vehicleBreakdowns}$uniqueId/verify-preview/',
          queryParameters: {'replacement_vehicle_id': replacementVehicleId},
        );
      } on DioException catch (e) {
        if (e.response?.statusCode != 404) rethrow;
        // Some servers apply replacement_vehicle_id as a model filter even
        // on this detail action. Pending reports have no replacement yet,
        // so the filter hides the report. Confirm it is still accessible
        // before treating this as an optional preview compatibility issue.
        final report = await dio.get(
          '${ApiConfig.vehicleBreakdowns}$uniqueId/',
        );
        if (report.data is! Map || report.data['unique_id'] != uniqueId) {
          rethrow;
        }
        throw VehicleBreakdownPreviewUnavailable();
      }
      return BreakdownVerifyPreview.fromJson(
        Map<String, dynamic>.from(res.data as Map),
      );
    } on VehicleBreakdownPreviewUnavailable {
      rethrow;
    } on DioException catch (e) {
      throw VehicleBreakdownException(_message(e));
    } catch (e) {
      throw VehicleBreakdownException(e.toString());
    }
  }

  /// Approves the breakdown. Omitted driver/operator = the same crew carries
  /// on. Omitted [collectionPointIds] = every pending bin carries over;
  /// omitted [moveAssignmentIds] = no other trip moves; omitted
  /// [substitutePlanIds] = every plan the replacement has no clash for.
  ///
  /// Returns the backend's `skipped_moves` reasons: trips that couldn't move
  /// because the replacement already has a trip at that date and time.
  Future<List<String>> approve(
    String uniqueId, {
    String? remarks,
    required String replacementVehicleId,
    String? replacementDriverId,
    String? replacementOperatorId,
    List<String>? collectionPointIds,
    List<String>? moveAssignmentIds,
    List<String>? substitutePlanIds,
  }) async {
    try {
      final dio = await authorizedDio();
      final res = await dio.patch(
        '${ApiConfig.vehicleBreakdowns}$uniqueId/verify/',
        data: {
          if (remarks != null && remarks.trim().isNotEmpty) 'remarks': remarks,
          'replacement_vehicle_id': replacementVehicleId,
          if (replacementDriverId != null)
            'replacement_driver_id': replacementDriverId,
          if (replacementOperatorId != null)
            'replacement_operator_id': replacementOperatorId,
          if (collectionPointIds != null)
            'collection_point_ids': collectionPointIds,
          if (moveAssignmentIds != null)
            'move_assignment_ids': moveAssignmentIds,
          if (substitutePlanIds != null)
            'substitute_plan_ids': substitutePlanIds,
        },
      );
      final skipped = res.data is Map ? res.data['skipped_moves'] : null;
      return skipped is List
          ? skipped
              .whereType<Map>()
              .map((s) => (s['reason'] ?? s['trip_id'] ?? '').toString())
              .where((s) => s.isNotEmpty)
              .toList()
          : const [];
    } on DioException catch (e) {
      throw VehicleBreakdownException(_message(e));
    } catch (e) {
      throw VehicleBreakdownException(e.toString());
    }
  }

  Future<void> reject(String uniqueId,
      {required String rejectionRemarks}) async {
    try {
      final dio = await authorizedDio();
      await dio.patch(
        '${ApiConfig.vehicleBreakdowns}$uniqueId/reject/',
        data: {'rejection_remarks': rejectionRemarks},
      );
    } on DioException catch (e) {
      throw VehicleBreakdownException(_message(e));
    } catch (e) {
      throw VehicleBreakdownException(e.toString());
    }
  }

  /// Closes an approved breakdown: the vehicle goes from BREAKDOWN back to
  /// ACTIVE, so its blocked trips can start again.
  Future<void> markRepaired(String uniqueId, {String? repairRemarks}) async {
    try {
      final dio = await authorizedDio();
      await dio.patch(
        '${ApiConfig.vehicleBreakdowns}$uniqueId/mark-repaired/',
        data: {
          if (repairRemarks != null && repairRemarks.trim().isNotEmpty)
            'repair_remarks': repairRemarks.trim(),
        },
      );
    } on DioException catch (e) {
      throw VehicleBreakdownException(_message(e));
    } catch (e) {
      throw VehicleBreakdownException(e.toString());
    }
  }

  List<Map<String, dynamic>> _rawList(dynamic data) {
    final List raw;
    if (data is List) {
      raw = data;
    } else if (data is Map && data['results'] is List) {
      raw = data['results'] as List;
    } else if (data is Map && data['data'] is List) {
      raw = data['data'] as List;
    } else {
      raw = const [];
    }
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  String _message(DioException e) {
    final data = e.response?.data;
    final serverMessage = _validationMessage(data);
    if (serverMessage != null && serverMessage.isNotEmpty) return serverMessage;
    return e.message ?? 'Network error';
  }

  String? _validationMessage(dynamic value, [String? field]) {
    if (value == null) return null;
    if (value is String) {
      final label = field
          ?.replaceAll('_', ' ')
          .split(' ')
          .where((part) => part.isNotEmpty)
          .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
          .join(' ');
      return label == null ? value : '$label: $value';
    }
    if (value is List) {
      final messages = value
          .map((item) => _validationMessage(item, field))
          .whereType<String>()
          .where((message) => message.isNotEmpty)
          .toList();
      return messages.isEmpty ? null : messages.join('\n');
    }
    if (value is Map) {
      for (final key in const ['detail', 'error', 'message']) {
        if (value[key] != null) return _validationMessage(value[key]);
      }
      final messages = <String>[];
      for (final entry in value.entries) {
        final message = _validationMessage(entry.value, entry.key.toString());
        if (message != null && message.isNotEmpty) messages.add(message);
      }
      return messages.isEmpty ? null : messages.join('\n');
    }
    return value.toString();
  }
}
