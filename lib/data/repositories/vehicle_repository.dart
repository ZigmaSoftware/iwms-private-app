import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart'; // For kDebugMode/print

// Layered imports
import '../models/vehicle_model.dart';
import '../../core/api_config.dart';

class VehicleRepository {
  final Dio dioClient;

  VehicleRepository({
    required this.dioClient,
  });

  // Fetch live GPS positions from the vehicle telemetry provider. The
  // government backend trip APIs know assignments/routes, but the all-vehicle
  // map needs actual live latitude/longitude rows from this feed.
  Future<List<VehicleModel>> fetchAllVehicleLocations() async {
    try {
      final Response response = await dioClient.get(ApiConfig.vehicleLiveApi);

      if (response.statusCode == 200 && response.data != null) {
        final decoded = response.data;
        final List<dynamic> dataList = decoded is List ? decoded : const [];

        return dataList
            .whereType<Map>()
            .map((json) => VehicleModel.fromJson(
                  Map<String, dynamic>.from(json),
                ))
            .where((vehicle) => _hasValidLocation(vehicle))
            .toList();
      } else {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
          error: "API returned status code: ${response.statusCode}",
        );
      }
    } on DioException catch (e) {
      if (kDebugMode) {
        print('Network Error fetching vehicles: ${e.message}');
      }
      throw Exception("Network Error: Could not connect to API.");
    } catch (e) {
      if (kDebugMode) {
        print('Parsing/Format Error: $e');
      }
      throw Exception(
          "Failed to process vehicle data. Check model keys and API format.");
    }
  }

  bool _hasValidLocation(VehicleModel vehicle) {
    final lat = vehicle.latitude;
    final lng = vehicle.longitude;
    return lat >= -90 &&
        lat <= 90 &&
        lng >= -180 &&
        lng <= 180 &&
        lat != 0 &&
        lng != 0;
  }
}
