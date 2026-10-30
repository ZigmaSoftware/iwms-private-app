import 'package:dio/dio.dart';

import 'package:iwms_private_app/core/api_config.dart';
import 'package:iwms_private_app/core/network/authorized_dio.dart';
import 'package:iwms_private_app/data/models/trip_retrip_models.dart';

class TripRetripException implements Exception {
  TripRetripException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Supervisor review of Re-Trip requests — a driver asked to end a trip
/// early with stops still pending (see `app/services/retrip_service.py`).
/// Approve closes the old trip and opens a continuation with the selected
/// stops carried over; reject sends the driver back to finish the trip.
class TripRetripRepository {
  /// [mine] scopes to requests raised against a trip plan the caller
  /// supervises (`TripPlan.supervisor_id == caller`) — mirrors
  /// `OperatorTripRepository`/assignment fetches' own `mine=true`. Needed
  /// because a supervisor can own a trip plan outside their own home
  /// project; without this the backend's default company/project scoping
  /// would silently filter those requests out (see
  /// `trip_retrip_viewset.TripRetripRequestViewSet.filter_queryset`).
  Future<List<TripRetripRequest>> fetchRequests({
    String? status,
    bool mine = true,
  }) async {
    try {
      final dio = await authorizedDio();
      var res = await dio.get(
        ApiConfig.retripRequests,
        queryParameters: {
          if (status != null) 'status': status,
          if (mine) 'mine': 'true',
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
        final current = Uri.parse(ApiConfig.retripRequests);
        final url = current.resolve(next.toString());
        if (url.origin != current.origin) {
          throw const FormatException('Invalid reports page');
        }
        res = await dio.get(url.toString());
      }
      return rows.map(TripRetripRequest.fromJson).toList();
    } on DioException catch (e) {
      throw TripRetripException(_message(e));
    } catch (e) {
      throw TripRetripException(e.toString());
    }
  }

  Future<TripRetripRequest> fetchRequest(String uniqueId) async {
    try {
      final dio = await authorizedDio();
      final res = await dio.get('${ApiConfig.retripRequests}$uniqueId/');
      if (res.data is! Map) {
        throw const FormatException('Invalid Re-Trip request response');
      }
      return TripRetripRequest.fromJson(
        Map<String, dynamic>.from(res.data as Map),
      );
    } on DioException catch (e) {
      throw TripRetripException(_message(e));
    } catch (e) {
      throw TripRetripException(e.toString());
    }
  }

  /// Approve, carrying over only [collectionPointIds]. The list contains the
  /// selected pending stop ids; the supervisor starts with every stop selected
  /// and unticks anything to drop for today.
  /// Returns the new continuation trip's assignment id, if the backend sent
  /// one back.
  Future<String?> approve(
    String uniqueId, {
    List<String>? collectionPointIds,
    String? remarks,
  }) async {
    try {
      final dio = await authorizedDio();
      final res = await dio.post(
        '${ApiConfig.retripRequests}$uniqueId/approve/',
        data: {
          if (collectionPointIds != null)
            'collection_point_ids': collectionPointIds,
          if (remarks != null && remarks.trim().isNotEmpty)
            'remarks': remarks.trim(),
        },
      );
      final data = res.data;
      if (data is Map && data['new_assignment_id'] != null) {
        return data['new_assignment_id'].toString();
      }
      return null;
    } on DioException catch (e) {
      throw TripRetripException(_message(e));
    } catch (e) {
      throw TripRetripException(e.toString());
    }
  }

  Future<void> reject(String uniqueId, {String? remarks}) async {
    try {
      final dio = await authorizedDio();
      await dio.post(
        '${ApiConfig.retripRequests}$uniqueId/reject/',
        data: {
          if (remarks != null && remarks.trim().isNotEmpty) 'remarks': remarks,
        },
      );
    } on DioException catch (e) {
      throw TripRetripException(_message(e));
    } catch (e) {
      throw TripRetripException(e.toString());
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
