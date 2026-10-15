import 'package:dio/dio.dart';

import 'package:iwms_private_app/core/api_config.dart';
import 'package:iwms_private_app/core/network/authorized_dio.dart';
import 'package:iwms_private_app/data/models/citizen_pickup_model.dart';

/// Today's household pickup for the logged-in citizen. The backend scopes
/// both calls to the citizen in the token.
class CitizenPickupRepository {
  CitizenServiceNotice? lastServiceNotice;

  Future<CitizenPickupToday?> fetchToday() async {
    final dio = await authorizedDio();
    final resp = await dio.get(ApiConfig.citizenPickupToday);
    final data = Map<String, dynamic>.from(resp.data as Map);
    lastServiceNotice = CitizenServiceNotice.fromResponse(data);
    return CitizenPickupToday.fromResponse(data);
  }

  /// Tells the crew the citizen is home. Throws [CitizenPickupException] with
  /// the server's explanation when it isn't allowed (e.g. the trip ended).
  Future<CitizenPickupToday?> sayImHome({String? note}) async {
    final dio = await authorizedDio();
    try {
      final resp = await dio.post(ApiConfig.citizenPickupImHome, data: {
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      });
      final data = Map<String, dynamic>.from(resp.data as Map);
      lastServiceNotice = CitizenServiceNotice.fromResponse(data);
      return CitizenPickupToday.fromResponse(data);
    } on DioException catch (e) {
      final data = e.response?.data;
      final detail = data is Map ? data['detail']?.toString() : null;
      throw CitizenPickupException(
          detail ?? 'Could not reach the server. Please try again.');
    }
  }
}

class CitizenPickupException implements Exception {
  const CitizenPickupException(this.message);
  final String message;
  @override
  String toString() => message;
}
