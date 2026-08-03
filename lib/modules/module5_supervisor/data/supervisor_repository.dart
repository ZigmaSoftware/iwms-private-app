import 'package:dio/dio.dart';

import 'package:iwms_citizen_app/core/api_config.dart';
import 'package:iwms_citizen_app/core/network/authorized_dio.dart';
import 'package:iwms_citizen_app/data/models/user_model.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/data/supervisor_models.dart';

/// Raised when a supervisor data fetch fails. Carries an optional [code] so
/// callers can branch (e.g. NO_ZONE_SCOPE → empty state instead of error).
class SupervisorException implements Exception {
  SupervisorException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => 'SupervisorException($code): $message';
}

/// Data access for the supervisor module. Wraps [authorizedDio] and the
/// existing backend endpoints (zone map + daily trip assignments). Read-only
/// for this phase — assignment approval is intentionally not wired yet.
class SupervisorRepository {
  static const String _assignments =
      '${ApiConfig.desktopBase}schedule-operations/daily-trip-assignments/';
  static const String _staff =
      '${ApiConfig.desktopBase}user-creations/staffcreation/';
  static const String _staffTemplates =
      '${ApiConfig.desktopBase}schedule-setup/staff-templates/';
  static const String _tripLogs =
      '${ApiConfig.desktopBase}schedule-operations/daily-trip-logs/';
  static const String _attendanceRecords =
      '${ApiConfig.attendanceBase}records/';
  static const String _collectionPoints =
      '${ApiConfig.desktopBase}schedule-setup/collection-points/';
  static const String _households = ApiConfig.customerList;
  static const String _alternativeStaffTemplates =
      '${ApiConfig.desktopBase}schedule-setup/alternative-staff-templates/';

  /// Fetch the requesting supervisor's authorised zone scope.
  ///
  /// The government backend has no zone-map concept (it's hierarchy/ward
  /// based, not zone-based) — `user-creations/supervisor-zone-map/me/` was
  /// removed there well before ward support was added, so this always
  /// resolves to an empty scope without a network round trip. Assignment
  /// loading proceeds via `mine=true` regardless (see [fetchAssignments]).
  Future<SupervisorZoneScope> fetchMyZoneScope() async {
    return SupervisorZoneScope.empty;
  }

  /// Fetch today's (or [date]'s) assignments, optionally scoped to [zoneIds].
  /// When the supervisor has multiple zones we fetch per-zone and merge, since
  /// the backend filter accepts a single `zone_id`.
  Future<List<SupervisorAssignment>> fetchAssignments({
    DateTime? date,
    List<String> zoneIds = const [],
    String? status,
    bool mine = false,
  }) async {
    final dio = await authorizedDio();
    final dateStr = date == null ? null : _formatDate(date);

    Future<List<SupervisorAssignment>> fetchFor(String? zoneId) async {
      final query = <String, dynamic>{};
      if (dateStr != null) query['date'] = dateStr;
      // `mine=true` scopes to assignments whose trip plan this supervisor owns
      // (TripPlan.supervisor_id == me), replacing zone-based scoping.
      if (mine) query['mine'] = 'true';
      if (zoneId != null && zoneId.isNotEmpty) query['zone_id'] = zoneId;
      if (status != null && status.isNotEmpty) query['status'] = status;

      final res = await dio.get(_assignments, queryParameters: query);
      return _parseList(res.data);
    }

    try {
      // Supervisor-scoped or unscoped fetches are a single call; only
      // zone-scoped fan-out needs the per-zone merge.
      if (mine || zoneIds.isEmpty) {
        return await fetchFor(null);
      }

      final results = await Future.wait(zoneIds.map(fetchFor));
      // De-duplicate by uniqueId (a trip could surface under overlapping
      // zone/ward filters).
      final seen = <String>{};
      final merged = <SupervisorAssignment>[];
      for (final list in results) {
        for (final a in list) {
          if (seen.add(a.uniqueId)) merged.add(a);
        }
      }
      return merged;
    } on DioException catch (e) {
      throw SupervisorException(_message(e));
    } catch (e) {
      throw SupervisorException(e.toString());
    }
  }

  /// This supervisor's trip history, sourced from the daily trip log
  /// (actuals recorded during/after each trip), newest first. Adapted into
  /// the same [SupervisorAssignment] shape as `fetchAssignments` so the UI
  /// (`SupervisorAssignmentCard`) matches exactly.
  Future<List<SupervisorAssignment>> fetchAssignmentHistory() async {
    try {
      final dio = await authorizedDio();
      final res = await dio.get(_tripLogs, queryParameters: {'mine': 'true'});
      final list = _rawList(res.data)
          .map((e) => SupervisorAssignment.fromTripLogJson(e))
          .toList();
      list.sort((a, b) {
        final ad = a.tripDate, bd = b.tripDate;
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return bd.compareTo(ad);
      });
      return list;
    } on DioException catch (e) {
      throw SupervisorException(_message(e));
    } catch (e) {
      throw SupervisorException(e.toString());
    }
  }

  /// The supervisor's collected-waste time series (one entry per trip log),
  /// sourced from the daily trip log's bin + household weights. Bucketing by
  /// day/week/month is done in the chart widget.
  Future<List<SupervisorWastePoint>> fetchWasteSeries() async {
    try {
      final dio = await authorizedDio();
      final res = await dio.get(
        _tripLogs,
        queryParameters: {'mine': 'true', 'limit': '1000'},
      );
      return _rawList(res.data)
          .map((e) => SupervisorWastePoint.fromLogJson(e))
          .where((p) => p.hasValidDate)
          .toList();
    } on DioException catch (e) {
      throw SupervisorException(_message(e));
    } catch (e) {
      throw SupervisorException(e.toString());
    }
  }

  /// Staff list (company-scoped by the backend), used by the Staffs screen
  /// which groups by designation.
  Future<List<SupervisorStaff>> fetchStaff() async {
    try {
      final dio = await authorizedDio();
      final res = await dio.get(_staff);
      return _rawList(res.data)
          .map((e) => SupervisorStaff.fromJson(e))
          .toList();
    } on DioException catch (e) {
      throw SupervisorException(_message(e));
    } catch (e) {
      throw SupervisorException(e.toString());
    }
  }

  Future<SupervisorStaffAttendanceSummary> fetchStaffAttendanceSummary({
    DateTime? date,
  }) async {
    try {
      final dio = await authorizedDio();
      final target = date ?? DateTime.now();
      final dateStr = _formatDate(target);
      final res = await dio.get(
        _attendanceRecords,
        queryParameters: {
          'from_date': dateStr,
          'to_date': dateStr,
        },
      );
      final data = res.data;
      if (data is Map<String, dynamic> && data['staff_summary'] is Map) {
        return SupervisorStaffAttendanceSummary.fromJson(
          Map<String, dynamic>.from(data['staff_summary'] as Map),
        );
      }
      return SupervisorStaffAttendanceSummary.empty;
    } on DioException catch (e) {
      throw SupervisorException(_message(e));
    } catch (e) {
      throw SupervisorException(e.toString());
    }
  }

  /// Staff templates (the "Teams" list).
  Future<List<SupervisorTeam>> fetchTeams() async {
    try {
      final dio = await authorizedDio();
      final res = await dio.get(_staffTemplates);
      return _rawList(res.data).map((e) => SupervisorTeam.fromJson(e)).toList();
    } on DioException catch (e) {
      throw SupervisorException(_message(e));
    } catch (e) {
      throw SupervisorException(e.toString());
    }
  }

  Future<List<SupervisorVehicle>> fetchVehicles() async {
    try {
      final dio = await authorizedDio();
      final res = await dio.get(ApiConfig.vehicles);
      return _rawList(res.data)
          .map((e) => SupervisorVehicle.fromJson(e))
          .toList();
    } on DioException catch (e) {
      throw SupervisorException(_message(e));
    } catch (e) {
      throw SupervisorException(e.toString());
    }
  }

  Future<List<SupervisorCollectionPoint>> fetchCollectionPoints() async {
    try {
      final dio = await authorizedDio();
      final res = await dio.get(_collectionPoints);
      return _rawList(res.data)
          .map((e) => SupervisorCollectionPoint.fromJson(e))
          .toList();
    } on DioException catch (e) {
      throw SupervisorException(_message(e));
    } catch (e) {
      throw SupervisorException(e.toString());
    }
  }

  Future<List<SupervisorHousehold>> fetchHouseholds() async {
    try {
      final dio = await authorizedDio();
      final res = await dio.get(_households);
      return _rawList(res.data)
          .map((e) => SupervisorHousehold.fromJson(e))
          .toList();
    } on DioException catch (e) {
      throw SupervisorException(_message(e));
    } catch (e) {
      throw SupervisorException(e.toString());
    }
  }

  Future<List<SupervisorCrewOption>> fetchDrivers() =>
      _fetchStaffByRole('driver');

  Future<List<SupervisorCrewOption>> fetchOperators() =>
      _fetchStaffByRole('operator');

  /// Edits an existing staff template's driver/operator/extra operators. The
  /// backend notifies (push + in-app) whichever staff are added/removed, and
  /// any live trip already resolves the new crew (DailyTripAssignment reads
  /// the current driver/operator off the template live).
  Future<void> updateStaffTemplate({
    required String uniqueId,
    required String driverId,
    required String operatorId,
    List<String> extraOperatorIds = const [],
  }) async {
    try {
      final dio = await authorizedDio();
      await dio.patch('$_staffTemplates$uniqueId/', data: {
        'driver_id': driverId,
        'operator_id': operatorId,
        'extra_operator_id': extraOperatorIds,
      });
    } on DioException catch (e) {
      throw SupervisorException(_message(e));
    } catch (e) {
      throw SupervisorException(e.toString());
    }
  }

  /// Drivers/operators NOT already on another active team — used by the "Add
  /// team" form so a staff member can't be double-booked onto two teams at
  /// once. [excludeTemplateId] keeps an edit showing that template's own
  /// current driver/operator as still available.
  Future<List<SupervisorCrewOption>> fetchAvailableDrivers({
    String? excludeTemplateId,
  }) =>
      _fetchAvailableStaffByRole('driver', excludeTemplateId: excludeTemplateId);

  Future<List<SupervisorCrewOption>> fetchAvailableOperators({
    String? excludeTemplateId,
  }) =>
      _fetchAvailableStaffByRole('operator', excludeTemplateId: excludeTemplateId);

  Future<List<SupervisorCrewOption>> _fetchAvailableStaffByRole(
    String role, {
    String? excludeTemplateId,
  }) async {
    try {
      final dio = await authorizedDio();
      final res = await dio.get(
        ApiConfig.staffTemplateAvailableStaff,
        queryParameters: {
          'role': role,
          if (excludeTemplateId != null && excludeTemplateId.isNotEmpty)
            'exclude_id': excludeTemplateId,
        },
      );
      return _rawList(res.data)
          .map((j) => SupervisorCrewOption(
                uniqueId: j['staff_unique_id']?.toString() ?? '',
                name: j['employee_name']?.toString() ?? '',
              ))
          .where((option) => option.uniqueId.isNotEmpty)
          .toList();
    } on DioException catch (e) {
      throw SupervisorException(_message(e));
    } catch (e) {
      throw SupervisorException(e.toString());
    }
  }

  /// Government staff carry their role on `governmentusertype_name` (e.g.
  /// `govt_panchayat_driver`), not `staffusertype_name` — filter client-side
  /// like the web admin's staff dropdowns do.
  Future<List<SupervisorCrewOption>> _fetchStaffByRole(
    String roleKeyword,
  ) async {
    try {
      final dio = await authorizedDio();
      final res = await dio.get(_staff);
      final options = <SupervisorCrewOption>[];
      for (final j in _rawList(res.data)) {
        final role = [
          j['governmentusertype_name'],
          j['staffusertype_name'],
        ].where((v) => v != null).join(' ').toLowerCase();
        if (!role.contains(roleKeyword)) continue;
        final option = SupervisorCrewOption.fromJson(j);
        if (option.uniqueId.isNotEmpty) options.add(option);
      }
      return options;
    } on DioException catch (e) {
      throw SupervisorException(_message(e));
    } catch (e) {
      throw SupervisorException(e.toString());
    }
  }

  /// Alternative staff templates already created under this supervisor's
  /// hierarchy (backend scopes the list automatically).
  Future<List<SupervisorAltStaffTemplate>> fetchAlternativeStaffTemplates() async {
    try {
      final dio = await authorizedDio();
      final res = await dio.get(_alternativeStaffTemplates);
      return _rawList(res.data)
          .map((e) => SupervisorAltStaffTemplate.fromJson(e))
          .toList();
    } on DioException catch (e) {
      throw SupervisorException(_message(e));
    } catch (e) {
      throw SupervisorException(e.toString());
    }
  }

  /// Creates a new alternative staff template ("Form ALT"). Geo hierarchy is
  /// inherited server-side from [staffTemplateId] when not explicit, so it
  /// doesn't need to be sent from here.
  Future<void> createAlternativeStaffTemplate({
    required String staffTemplateId,
    required String driverId,
    required String operatorId,
    List<String> extraOperatorIds = const [],
    required String fromDate,
    required String toDate,
    required String changeReason,
    String? changeRemarks,
  }) async {
    try {
      final dio = await authorizedDio();
      await dio.post(_alternativeStaffTemplates, data: {
        'staff_template': staffTemplateId,
        'driver': driverId,
        'operator': operatorId,
        'extra_operator': extraOperatorIds,
        'from_date': fromDate,
        'to_date': toDate,
        'change_reason': changeReason,
        if (changeRemarks != null && changeRemarks.trim().isNotEmpty)
          'change_remarks': changeRemarks,
      });
    } on DioException catch (e) {
      throw SupervisorException(_message(e));
    } catch (e) {
      throw SupervisorException(e.toString());
    }
  }

  /// Applies an alternative staff template substitution onto a trip
  /// assignment — the substituted-in crew starts seeing the trip in their
  /// own "my trips today", and the original crew stops seeing it.
  Future<void> applyAlternativeStaffTemplate({
    required String assignmentId,
    required String altStaffTemplateId,
  }) async {
    try {
      final dio = await authorizedDio();
      await dio.patch(
        '$_assignments$assignmentId/',
        data: {'alt_staff_template_id': altStaffTemplateId},
      );
    } on DioException catch (e) {
      throw SupervisorException(_message(e));
    } catch (e) {
      throw SupervisorException(e.toString());
    }
  }

  /// Supervisor mobile now chooses a normal staff template for substitution.
  /// The backend still applies substitutions through
  /// `alt_staff_template_id`, so create a same-day temporary alternative
  /// template from the selected team, then attach it to the assignment.
  Future<void> applyStaffTemplateSubstitution({
    required String assignmentId,
    required SupervisorTeam team,
  }) async {
    try {
      final dio = await authorizedDio();
      final today = _formatDate(DateTime.now());
      final created = await dio.post(_alternativeStaffTemplates, data: {
        'staff_template': team.uniqueId,
        'driver': team.driverId,
        'operator': team.operatorId,
        'extra_operator': team.extraOperatorIds,
        'from_date': today,
        'to_date': today,
        'change_reason': 'Supervisor mobile substitution',
        'change_remarks': 'Created from selected staff template in mobile app',
      });

      final body = created.data;
      final altId = body is Map<String, dynamic>
          ? body['unique_id']?.toString() ?? ''
          : '';
      if (altId.isEmpty) {
        throw SupervisorException('Substitution template was not returned.');
      }

      await dio.patch(
        '$_assignments$assignmentId/',
        data: {'alt_staff_template_id': altId},
      );
    } on DioException catch (e) {
      throw SupervisorException(_message(e));
    } catch (e) {
      throw SupervisorException(e.toString());
    }
  }

  /// Creates a new staff template ("Team"). [geo] carries the supervisor's
  /// own hierarchy ids (state/district/area_type/.../panchayat) since a
  /// brand-new template has no parent record to inherit geo from.
  Future<void> createStaffTemplate({
    required String driverId,
    required String operatorId,
    List<String> extraOperatorIds = const [],
    required GeoScope? geo,
  }) async {
    try {
      final dio = await authorizedDio();
      await dio.post(_staffTemplates, data: {
        'driver_id': driverId,
        'operator_id': operatorId,
        'extra_operator_id': extraOperatorIds,
        if (geo?.stateId != null) 'state_id': geo!.stateId,
        if (geo?.districtId != null) 'district_id': geo!.districtId,
        if (geo?.areaTypeId != null) 'area_type_id': geo!.areaTypeId,
        if (geo?.corporationId != null) 'corporation_id': geo!.corporationId,
        if (geo?.municipalityId != null)
          'municipality_id': geo!.municipalityId,
        if (geo?.townPanchayatId != null)
          'town_panchayat_id': geo!.townPanchayatId,
        if (geo?.panchayatUnionId != null)
          'panchayat_union_id': geo!.panchayatUnionId,
        if (geo?.panchayatId != null) 'panchayat_id': geo!.panchayatId,
      });
    } on DioException catch (e) {
      throw SupervisorException(_message(e));
    } catch (e) {
      throw SupervisorException(e.toString());
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

  List<SupervisorAssignment> _parseList(dynamic data) {
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
        .map((e) => SupervisorAssignment.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  String _formatDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  String _message(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['detail'] != null) {
      return data['detail'].toString();
    }
    return e.message ?? 'Network error';
  }
}
