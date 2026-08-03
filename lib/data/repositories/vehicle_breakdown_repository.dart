import 'dart:io';

import 'package:dio/dio.dart';

import 'package:iwms_citizen_app/core/api_config.dart';
import 'package:iwms_citizen_app/core/network/authorized_dio.dart';
import 'package:iwms_citizen_app/data/models/vehicle_breakdown_models.dart';

class VehicleBreakdownException implements Exception {
  VehicleBreakdownException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// "Vehicle breakdown" report/approve/reject flow — shared between the
/// driver app (report a breakdown) and the supervisor app (approve/reject).
class VehicleBreakdownRepository {
  static const String driverRole = 'govt_panchayat_driver';
  static const String operatorRole = 'govt_panchayat_operator';

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
    String role,
  ) async {
    try {
      final dio = await authorizedDio();
      final res = await dio.get(
        ApiConfig.vehicleBreakdownAvailableStaff,
        queryParameters: {'date': _fmtDate(date), 'role': role},
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
        if (breakdownLat != null) 'breakdown_lat': breakdownLat,
        if (breakdownLng != null) 'breakdown_lng': breakdownLng,
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
  }) async {
    try {
      final dio = await authorizedDio();
      final res = await dio.get(
        ApiConfig.vehicleBreakdowns,
        queryParameters: {
          if (approvalStatus != null) 'approval_status': approvalStatus,
        },
      );
      return _rawList(res.data)
          .map(VehicleBreakdownReport.fromJson)
          .toList();
    } on DioException catch (e) {
      throw VehicleBreakdownException(_message(e));
    } catch (e) {
      throw VehicleBreakdownException(e.toString());
    }
  }

  Future<void> approve(
    String uniqueId, {
    String? remarks,
    required String replacementVehicleId,
    required String replacementDriverId,
    required String replacementOperatorId,
  }) async {
    try {
      final dio = await authorizedDio();
      await dio.patch(
        '${ApiConfig.vehicleBreakdowns}$uniqueId/verify/',
        data: {
          if (remarks != null && remarks.trim().isNotEmpty) 'remarks': remarks,
          'replacement_vehicle_id': replacementVehicleId,
          'replacement_driver_id': replacementDriverId,
          'replacement_operator_id': replacementOperatorId,
        },
      );
    } on DioException catch (e) {
      throw VehicleBreakdownException(_message(e));
    } catch (e) {
      throw VehicleBreakdownException(e.toString());
    }
  }

  Future<void> reject(String uniqueId, {required String rejectionRemarks}) async {
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
    if (data is Map && data['detail'] != null) return data['detail'].toString();
    if (data is Map && data['error'] != null) return data['error'].toString();
    return e.message ?? 'Network error';
  }
}
