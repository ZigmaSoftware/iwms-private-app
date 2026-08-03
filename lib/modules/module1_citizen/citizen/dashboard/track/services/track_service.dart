import 'dart:convert';

import 'package:iwms_citizen_app/core/api_config.dart';
import 'package:iwms_citizen_app/core/network/authorized_dio.dart';
import '../models/waste_period.dart';
import '../models/waste_reports.dart';
import '../models/waste_summary.dart';

class TrackService {
  TrackService({
    this.citizenSummaryEndpoint = ApiConfig.wasteSummaryEndpoint,
  });

  final String citizenSummaryEndpoint;

  Future<Map<String, WasteSummary>> fetchMonthlySummaries(
      DateTime reference) async {
    final summary = await fetchCitizenSummary(
      period: WastePeriod.monthly,
      referenceDate: reference,
    );
    if (summary == null) {
      return <String, WasteSummary>{};
    }
    return <String, WasteSummary>{_dateKey(summary.date): summary};
  }

  Future<List<WasteSummary>> fetchDateWiseSummaries(
    DateTime from,
    DateTime to,
  ) async {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    final results = <WasteSummary>[];

    for (var day = start;
        !day.isAfter(end);
        day = day.add(const Duration(days: 1))) {
      final summary = await fetchCitizenSummary(
        period: WastePeriod.daily,
        referenceDate: day,
      );
      if (summary != null) {
        results.add(summary);
      }
    }

    return results;
  }

  Future<List<DayWiseTicket>> fetchDayWiseTickets(DateTime date) async {
    final dayKey = _dateKey(date);
    final responseJson = await _getBackendJson(
      '${ApiConfig.desktopBase}reports/daily-waste-comparisons/',
      queryParameters: {'date': dayKey, 'source': 'all'},
    );
    final dataList = _mapList(responseJson, 'results');
    return dataList.map(_ticketFromGovernmentReport).toList(growable: false);
  }

  Future<List<VehicleWeightReport>> fetchVehicleWiseReport(
      DateTime date) async {
    final dayKey = _dateKey(date);
    final responseJson = await _getBackendJson(
      '${ApiConfig.desktopBase}reports/daily-waste-comparisons/',
      queryParameters: {'date': dayKey, 'source': 'all'},
    );
    final dataList = _mapList(responseJson, 'results');
    return dataList.map((raw) {
      final dateValue = DateTime.tryParse(
        raw['collection_date']?.toString() ?? dayKey,
      );
      final panchayat = raw['panchayat_name']?.toString() ?? 'Unknown';
      final wasteType = raw['waste_type']?.toString();
      return VehicleWeightReport(
        vehicleNo: wasteType == null ? panchayat : '$panchayat - $wasteType',
        totalWeight: _parseDouble(raw['actual_weight_kg']),
        date: dateValue,
      );
    }).toList(growable: false);
  }

  Future<Map<String, dynamic>> _getBackendJson(
    String url, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final dio = await authorizedDio();
    final response = await dio.get(url, queryParameters: queryParameters);
    if (response.statusCode != 200) {
      throw Exception(
          'Failed to fetch government data (${response.statusCode})');
    }
    final decoded =
        response.data is String ? jsonDecode(response.data) : response.data;
    if (decoded is Map<String, dynamic>) return decoded;
    throw Exception('Unexpected response format');
  }

  List<Map<String, dynamic>> _mapList(
    Map<String, dynamic> json, [
    String key = 'data',
  ]) {
    final data = json[key];
    if (data is List) {
      return data.whereType<Map<String, dynamic>>().toList(growable: false);
    }
    return const [];
  }

  DayWiseTicket _ticketFromGovernmentReport(Map<String, dynamic> json) {
    final dateValue = DateTime.tryParse(
      json['collection_date']?.toString() ?? '',
    );
    final wasteType = (json['waste_type'] ?? '').toString().toLowerCase();
    final actualWeight = _parseDouble(json['actual_weight_kg']);

    return DayWiseTicket(
      ticketNo: json['unique_id']?.toString() ?? 'NA',
      timestamp: dateValue ?? DateTime.now(),
      vehicleNo: json['panchayat_name']?.toString() ?? 'Government report',
      dryWeight: wasteType.contains('dry') ? actualWeight : 0,
      wetWeight: wasteType.contains('wet') ? actualWeight : 0,
      mixWeight: wasteType.contains('dry') || wasteType.contains('wet')
          ? 0
          : actualWeight,
      netWeight: actualWeight,
    );
  }

  double _parseDouble(dynamic raw) {
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '') ?? 0;
  }

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<WasteSummary?> fetchCitizenSummary({
    required WastePeriod period,
    required DateTime referenceDate,
  }) async {
    final normalized =
        DateTime(referenceDate.year, referenceDate.month, referenceDate.day);
    final uri = Uri.parse(citizenSummaryEndpoint).replace(
      queryParameters: {
        'period': period.name,
        'date': _dateKey(normalized),
      },
    );

    final dio = await authorizedDio();
    final response = await dio.getUri(uri);
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch waste summary (${response.statusCode})');
    }

    final responseData = response.data;
    final decoded =
        responseData is String ? jsonDecode(responseData) : responseData;
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Unexpected response payload');
    }
    if (decoded['status'] != 'success') {
      throw Exception('Backend returned error');
    }

    final data = decoded['data'];
    if (data is Map<String, dynamic>) {
      return WasteSummary.fromJson(data);
    }
    return null;
  }
}
