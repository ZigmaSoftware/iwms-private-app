import 'dart:developer' as developer;

import 'package:dio/dio.dart';

import 'package:iwms_private_app/core/api_config.dart';
import 'package:iwms_private_app/core/network/authorized_dio.dart';
import 'package:iwms_private_app/data/models/operator_trip_models.dart';

/// One page of a trip's stops from `operator-mobile/trip-stops/`.
///
/// [items] is untyped here on purpose — `fetchTripStopsPage` is the one
/// generic method behind both `fetchCollectionPointsPage` (bin) and
/// `fetchHouseholdCollectionsPage` (household), so it can't know which model
/// to parse into. Those two methods do the actual `fromJson` mapping and
/// hand back a properly typed `TripStopsPage<OperatorTripCollectionPoint>`/
/// `TripStopsPage<OperatorTripHouseholdStop>`.
class TripStopsPage<T> {
  const TripStopsPage({
    required this.items,
    required this.page,
    required this.count,
    required this.hasNext,
  });

  final List<T> items;
  final int page;

  /// Total stops of this type on the trip — NOT `items.length`.
  final int count;
  final bool hasNext;
}

/// Thrown by the operator-trip repository for actionable, user-facing errors.
///
/// `code` matches the backend's error codes (NO_ACTIVE_TRIP, WRONG_WASTE_TYPE,
/// WRONG_PANCHAYAT, ALREADY_COLLECTED, BIN_NOT_FOUND, etc) so the UI can map
/// to localized messages without parsing strings.
class OperatorTripException implements Exception {
  final String code;
  final String message;
  final int? statusCode;

  OperatorTripException({
    required this.code,
    required this.message,
    this.statusCode,
  });

  @override
  String toString() => '[$code] $message';
}

class OperatorTripRepository {
  /// The waste streams saved against this customer in Customer Creation
  /// (`CustomerCreation.waste_types`), in the backend's display order — Wet,
  /// then Dry, then the rest alphabetically. Returns an empty list when the
  /// customer has none saved or the lookup fails, so the caller can simply
  /// omit the section rather than blocking the action sheet.
  Future<List<CustomerWasteType>> fetchCustomerWasteTypes(
    String customerId,
  ) async {
    if (customerId.trim().isEmpty) return const [];
    final dio = await authorizedDio();
    try {
      final resp = await dio.get(
        ApiConfig.customerWasteTypes,
        queryParameters: {'customer_id': customerId},
      );
      final data = resp.data;
      if (data is! Map || data['status'] != 'success') return const [];
      final rows = data['data'];
      if (rows is! List) return const [];
      return rows
          .whereType<Map>()
          .map((e) => CustomerWasteType.fromJson(
                Map<String, dynamic>.from(e),
              ))
          .where((w) => w.name.isNotEmpty)
          .toList();
    } on DioException catch (e) {
      developer.log('fetchCustomerWasteTypes failed: $e');
      return const [];
    }
  }

  Future<OperatorTripToday?> fetchMyTripToday() async {
    final dio = await authorizedDio();
    try {
      final resp = await dio.get(ApiConfig.operatorMyTripToday);
      final data = resp.data;
      if (data is! Map<String, dynamic>) {
        return null;
      }
      return OperatorTripToday.fromJson(data);
    } on DioException catch (e) {
      _throwDio(e);
    }
  }

  /// All of the operator's trips today (bin + household + bulk). Returns an
  /// empty list when there is no trip. Used by the header carousel.
  Future<List<OperatorTripToday>> fetchMyTripsToday() async {
    final dio = await authorizedDio();
    try {
      final resp = await dio.get(ApiConfig.operatorMyTripsToday);
      final data = resp.data;
      final results = data is Map && data['results'] is List
          ? data['results'] as List
          : const <dynamic>[];
      return results
          .map((e) => OperatorTripToday.fromJson(
                Map<String, dynamic>.from(e as Map),
              ))
          .toList();
    } on DioException catch (e) {
      _throwDio(e);
    }
  }

  /// Page [page] (1-based) of [assignmentId]'s bin stops, beyond whatever
  /// `my-trip-today`/`my-trips-today` already embedded (the first 20 — see
  /// `STOPS_PAGE_SIZE` on the backend). Always 20 per page.
  Future<TripStopsPage<OperatorTripCollectionPoint>> fetchCollectionPointsPage(
    String assignmentId,
    int page,
  ) =>
      _fetchTripStopsPage(
        assignmentId: assignmentId,
        type: 'bin',
        page: page,
        fromJson: OperatorTripCollectionPoint.fromJson,
      );

  /// Household counterpart to [fetchCollectionPointsPage].
  Future<TripStopsPage<OperatorTripHouseholdStop>> fetchHouseholdCollectionsPage(
    String assignmentId,
    int page,
  ) =>
      _fetchTripStopsPage(
        assignmentId: assignmentId,
        type: 'household',
        page: page,
        fromJson: OperatorTripHouseholdStop.fromJson,
      );

  Future<TripStopsPage<T>> _fetchTripStopsPage<T>({
    required String assignmentId,
    required String type,
    required int page,
    required T Function(Map<String, dynamic>) fromJson,
  }) async {
    final dio = await authorizedDio();
    try {
      final resp = await dio.get(
        ApiConfig.operatorTripStops,
        queryParameters: {
          'assignment_id': assignmentId,
          'type': type,
          'page': page,
        },
      );
      final data = Map<String, dynamic>.from(resp.data as Map);
      final results = (data['results'] as List? ?? const [])
          .map((e) => fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      return TripStopsPage<T>(
        items: results,
        page: (data['page'] as num?)?.toInt() ?? page,
        count: (data['count'] as num?)?.toInt() ?? results.length,
        hasNext: data['has_next'] == true,
      );
    } on DioException catch (e) {
      _throwDio(e);
    }
  }

  /// Mark a household stop "collect later" (skipped) or "not available"
  /// (missed) for a specific trip assignment. Scoped to [assignmentId] so the
  /// status lands on the correct household trip (a driver may hold a bin trip
  /// AND a household trip today).
  Future<void> markHouseholdStatus({
    required String customerId,
    required String status, // 'collect_later' | 'not_available'
    required String reason,
    required String assignmentId,
    String? latitude,
    String? longitude,
  }) async {
    final dio = await authorizedDio();
    try {
      await dio.post(
        ApiConfig.householdCollectionMarkStatus,
        data: {
          'customer_id': customerId,
          'status': status,
          'reason': reason,
          'assignment_id': assignmentId,
          if (latitude != null && latitude.isNotEmpty) 'latitude': latitude,
          if (longitude != null && longitude.isNotEmpty) 'longitude': longitude,
        },
      );
    } on DioException catch (e) {
      _throwDio(e);
    }
  }

  Future<BinScanValidateResult> validateBinQr(String binQr) async {
    final dio = await authorizedDio();
    try {
      final resp = await dio.post(
        ApiConfig.operatorValidateBinQr,
        data: {'bin_qr': binQr},
      );
      return BinScanValidateResult.fromJson(
        Map<String, dynamic>.from(resp.data as Map),
      );
    } on DioException catch (e) {
      _throwDio(e);
    }
  }

  Future<BinScanSubmitResult> scanBin({
    required String binQr,
    double? weightKg,
    String action = 'collect',
    double? latitude,
    double? longitude,
    String? notes,
    String? statusReason,
  }) async {
    final dio = await authorizedDio();
    try {
      final resp = await dio.post(
        ApiConfig.operatorScanBin,
        data: {
          'bin_qr': binQr,
          'action': action,
          if (weightKg != null) 'weight_kg': weightKg.toStringAsFixed(2),
          if (latitude != null) 'latitude': latitude.toStringAsFixed(6),
          if (longitude != null) 'longitude': longitude.toStringAsFixed(6),
          if (notes != null && notes.isNotEmpty) 'notes': notes,
          if (statusReason != null && statusReason.isNotEmpty)
            'status_reason': statusReason,
        },
      );
      return BinScanSubmitResult.fromJson(
        Map<String, dynamic>.from(resp.data as Map),
      );
    } on DioException catch (e) {
      _throwDio(e);
    }
  }

  /// Explicit "Start Trip" — idempotent on the backend (re-starting an
  /// already-running trip succeeds instead of erroring, so a flaky network
  /// can't strand the driver mid-tap).
  Future<OperatorTripToday> startTrip(String assignmentId) async {
    final dio = await authorizedDio();
    try {
      final resp = await dio.post(ApiConfig.operatorTripStart(assignmentId));
      final data = resp.data;
      final tripJson = data is Map && data['trip'] is Map
          ? Map<String, dynamic>.from(data['trip'] as Map)
          : Map<String, dynamic>.from(data as Map);
      return OperatorTripToday.fromJson(tripJson);
    } on DioException catch (e) {
      _throwDio(e);
    }
  }

  /// Explicit "End Trip". If stops remain, this does NOT close the trip —
  /// the backend raises a Re-Trip request for a supervisor to decide, and
  /// [OperatorTripEndResult.retripRequested] comes back true rather than an
  /// exception. A stops-remain-and-no-[reason] response is likewise not an
  /// exception — it comes back as [OperatorTripEndResult.reasonRequired] so
  /// the caller can prompt for a reason and call this again.
  Future<OperatorTripEndResult> endTrip(
    String assignmentId, {
    String? reason,
  }) async {
    final dio = await authorizedDio();
    try {
      final resp = await dio.post(
        ApiConfig.operatorTripEnd(assignmentId),
        data: {
          if (reason != null && reason.isNotEmpty) 'reason': reason,
        },
      );
      return OperatorTripEndResult.fromJson(
        Map<String, dynamic>.from(resp.data as Map),
      );
    } on DioException catch (e) {
      final data = e.response?.data;
      if (e.response?.statusCode == 400 &&
          data is Map &&
          data['code'] == 'REASON_REQUIRED') {
        return OperatorTripEndResult.reasonRequired(
          pendingBinCount: (data['pending_bin_count'] as num?)?.toInt() ?? 0,
          pendingHouseholdCount:
              (data['pending_household_count'] as num?)?.toInt() ?? 0,
        );
      }
      _throwDio(e);
    }
  }

  Future<List<OperatorTripHistorySummary>> fetchHistory({
    DateTime? from,
    DateTime? to,
  }) async {
    final dio = await authorizedDio();
    try {
      final resp = await dio.get(
        ApiConfig.operatorTripHistory,
        queryParameters: {
          if (from != null) 'from': _formatDate(from),
          if (to != null) 'to': _formatDate(to),
        },
      );
      final data = resp.data;
      final results = data is Map && data['results'] is List
          ? data['results'] as List
          : const <dynamic>[];
      return results
          .map((e) => OperatorTripHistorySummary.fromJson(
                Map<String, dynamic>.from(e as Map),
              ))
          .toList();
    } on DioException catch (e) {
      _throwDio(e);
    }
  }

  Future<OperatorTripHistoryDetail> fetchHistoryDetail(String tripId) async {
    final dio = await authorizedDio();
    try {
      final resp = await dio.get('${ApiConfig.operatorTripHistory}$tripId/');
      return OperatorTripHistoryDetail.fromJson(
        Map<String, dynamic>.from(resp.data as Map),
      );
    } on DioException catch (e) {
      _throwDio(e);
    }
  }

  // ---------------------------------------------------------------------------
  /// Converts a Dio failure into an `OperatorTripException` so the UI gets a
  /// consistent shape regardless of whether the error is a network problem,
  /// a 4xx with a JSON body, or a 5xx without one.
  Never _throwDio(DioException e) {
    final resp = e.response;
    final status = resp?.statusCode;
    final data = resp?.data;

    developer.log(
      'operator-trip Dio failure: type=${e.type} url=${e.requestOptions.uri} '
      'status=$status body=$data',
      name: 'OperatorTripRepository',
      error: e,
    );

    if (data is Map && data['code'] is String) {
      throw OperatorTripException(
        code: data['code'] as String,
        message: (data['detail'] ?? data['message'] ?? '').toString(),
        statusCode: status,
      );
    }

    // Network / connection-level failures (no HTTP response from server).
    if (resp == null) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          throw OperatorTripException(
            code: 'NETWORK_TIMEOUT',
            message:
                'Server did not respond. Check your connection and try again.',
          );
        case DioExceptionType.connectionError:
          throw OperatorTripException(
            code: 'NETWORK_UNREACHABLE',
            message:
                'Could not reach the IWMS server at ${e.requestOptions.uri.host}. Check Wi-Fi / VPN.',
          );
        case DioExceptionType.cancel:
          throw OperatorTripException(
            code: 'REQUEST_CANCELLED',
            message: 'Request was cancelled.',
          );
        case DioExceptionType.badCertificate:
          throw OperatorTripException(
            code: 'BAD_CERTIFICATE',
            message: 'Server certificate is not trusted.',
          );
        default:
          throw OperatorTripException(
            code: 'NETWORK_ERROR',
            message: 'Network error: ${e.message ?? e.type.name}',
          );
      }
    }

    // HTTP error without our expected JSON shape.
    if (status == 401 || status == 403) {
      throw OperatorTripException(
        code: 'UNAUTHORIZED',
        message:
            'Your session is not authorised for this action. Please log in again.',
        statusCode: status,
      );
    }
    if (status != null && status >= 500) {
      throw OperatorTripException(
        code: 'SERVER_ERROR',
        message: 'Server error ($status). Please try again shortly.',
        statusCode: status,
      );
    }
    throw OperatorTripException(
      code: 'HTTP_$status',
      message: data is String && data.isNotEmpty
          ? data
          : 'Request failed with status $status.',
      statusCode: status,
    );
  }

  String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
