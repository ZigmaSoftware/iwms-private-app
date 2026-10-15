import 'package:dio/dio.dart';
import 'supervisor_trip_workbench.dart';

import 'package:iwms_private_app/core/api_config.dart';
import 'package:iwms_private_app/core/network/authorized_dio.dart';
import 'package:iwms_private_app/data/models/user_model.dart';
import 'package:iwms_private_app/modules/module5_supervisor/data/supervisor_models.dart';

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
  SupervisorRepository({Future<Dio> Function()? dioProvider})
      : _dioProvider = dioProvider ?? authorizedDio;
  final Future<Dio> Function() _dioProvider;

  Future<List<SupervisorPlanOption>> fetchTodayPlanOptions() async {
    try {
      final dio = await _dioProvider();
      final response = await dio.get(ApiConfig.supervisorTodayPlanOptions);
      final rows = response.data is Map ? response.data['results'] : null;
      return (rows is List ? rows : const [])
          .whereType<Map>()
          .map((row) =>
              SupervisorPlanOption.fromJson(Map<String, dynamic>.from(row)))
          .toList(growable: false);
    } on DioException catch (e) {
      throw SupervisorException(_message(e));
    }
  }

  Future<void> assignSelectedPlans(List<String> tripPlanIds) async {
    try {
      final dio = await _dioProvider();
      final response = await dio.post(ApiConfig.supervisorGenerateSelected,
          data: {'trip_plan_ids': tripPlanIds});
      // The server answers 200 even when it skipped every plan, listing why
      // under `blocked` — surface that instead of claiming success.
      final data = response.data is Map ? response.data as Map : const {};
      final assigned = [
        ...(data['created'] as List? ?? const []),
        ...(data['existing'] as List? ?? const []),
      ];
      final blocked = (data['blocked'] as List? ?? const [])
          .whereType<Map>()
          .map((b) => b['reason']?.toString() ?? '')
          .where((r) => r.isNotEmpty)
          .toSet();
      if (assigned.isEmpty) {
        throw SupervisorException(blocked.isEmpty
            ? 'The trip could not be assigned. Please refresh and try again.'
            : blocked.join('. '));
      }
    } on DioException catch (e) {
      throw SupervisorException(_message(e));
    }
  }

  Future<void> declareNoCollection({
    required List<String> tripPlanIds,
    required String reasonCode,
    String reasonText = '',
  }) async {
    try {
      final dio = await _dioProvider();
      await dio.post(ApiConfig.supervisorNoCollection, data: {
        'trip_plan_ids': tripPlanIds,
        'reason_code': reasonCode,
        'reason_text': reasonText.trim(),
      });
    } on DioException catch (e) {
      throw SupervisorException(_message(e));
    }
  }

  Future<void> revokeNoCollection(String noticeId, {String reason = ''}) async {
    try {
      final dio = await _dioProvider();
      await dio.post(ApiConfig.supervisorRevokeNoCollection,
          data: {'notice_id': noticeId, 'reason': reason.trim()});
    } on DioException catch (e) {
      throw SupervisorException(_message(e));
    }
  }

  static const String _assignments =
      '${ApiConfig.desktopBase}schedule-operations/daily-trip-assignments/';
  // "staff-creations" — a dev merge renamed the backend's router group (and
  // the underlying model package) from "user-creations"; this was left
  // pointing at the old URL and 404'd on every call.
  static const String _staff =
      '${ApiConfig.desktopBase}staff-creations/staffcreation/';
  static const String _staffTemplates =
      '${ApiConfig.desktopBase}schedule-setup/staff-templates/';
  static const String _binCollectionEvents =
      '${ApiConfig.desktopBase}schedule-operations/bin-collection-events/';
  static const String _householdWasteCollections =
      '${ApiConfig.desktopBase}schedule-operations/wastecollections/';
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
  /// based, not zone-based) — `staff-creations/supervisor-zone-map/me/` was
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
    final dio = await _dioProvider();
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

  Future<void> reviewTripAssignment(String id,
      {required bool approve, String reason = ''}) async {
    try {
      final dio = await _dioProvider();
      await dio.patch('$_assignments$id/approval/', data: {
        'approval_status': approve ? 'Approved' : 'Rejected',
        'reason': reason,
      });
    } on DioException catch (e) {
      throw SupervisorException(_message(e));
    }
  }

  Future<void> cancelScheduledTrip(String id, String reason) async {
    try {
      final dio = await _dioProvider();
      await dio.patch('$_assignments$id/status/', data: {
        'status': 'Cancelled',
        'expected_status': 'Scheduled',
        'reason': reason,
      });
    } on DioException catch (e) {
      throw SupervisorException(_message(e));
    }
  }

  /// Fetch all workbench pages before publishing counts. Do not silently treat
  /// an old backend or a malformed response as an empty work day.
  Future<SupervisorTripWorkbench> fetchTripWorkbench() async {
    try {
      final dio = await _dioProvider();
      final items = <String, SupervisorAssignment>{};
      DateTime? serviceDate;
      DateTime? serverNow;
      var offset = 0;
      while (true) {
        final res = await dio.get(_assignments, queryParameters: {
          'mine': 'true',
          'trip_view': 'workbench',
          'limit': 100,
          'offset': offset,
          'ordering': 'trip_date,scheduled_time,unique_id',
        });
        final data = _tripPageData(res.data);
        final day = DateTime.parse(data['service_date'] as String);
        if (serviceDate != null && day != serviceDate) {
          throw SupervisorException('The service date changed. Refresh trips.');
        }
        serviceDate = day;
        serverNow ??= parseServiceWallTime(data['as_of'] as String);
        final page = _parseList(data);
        for (final item in page) {
          items[item.uniqueId] = item;
        }
        if (data['next'] == null) break;
        if (page.isEmpty) {
          throw SupervisorException('Could not load all trips. Please retry.');
        }
        offset += page.length;
      }
      return SupervisorTripWorkbench(
          serviceDate: serviceDate,
          serverNow: serverNow,
          assignments: items.values.toList());
    } on DioException catch (e) {
      throw SupervisorException(_message(e),
          code: e.response?.statusCode == 403 ? 'FORBIDDEN' : null);
    }
  }

  Future<SupervisorTripHistoryPage> fetchTripHistoryPage({
    DateTime? from,
    DateTime? to,
    String? status,
    String search = '',
    bool retripOnly = false,
    bool exceptionsOnly = false,
    int offset = 0,
  }) async {
    try {
      final dio = await _dioProvider();
      final res = await dio.get(_assignments, queryParameters: {
        'mine': 'true',
        'trip_view': 'history',
        'limit': 30,
        'offset': offset,
        if (from != null) 'from_date': _formatDate(from),
        if (to != null) 'to_date': _formatDate(to),
        if (status != null) 'status': status,
        if (search.trim().isNotEmpty) 'search': search.trim(),
        if (retripOnly) 'retrip_only': 'true',
        if (exceptionsOnly) 'exceptions_only': 'true',
      });
      final data = _tripPageData(res.data);
      return SupervisorTripHistoryPage(
          items: _parseList(data),
          count: (data['count'] as num).toInt(),
          hasMore: data['next'] != null,
          serviceDate: DateTime.parse(data['service_date'] as String));
    } on DioException catch (e) {
      throw SupervisorException(_message(e),
          code: e.response?.statusCode == 403 ? 'FORBIDDEN' : null);
    }
  }

  Map<String, dynamic> _tripPageData(dynamic data) {
    if (data is! Map ||
        data['results'] is! List ||
        data['count'] is! num ||
        data['service_date'] is! String ||
        data['as_of'] is! String) {
      throw SupervisorException(
          'Trip information is unavailable. Please refresh or contact your administrator.');
    }
    return Map<String, dynamic>.from(data);
  }

  /// The supervisor's collected-waste time series (one entry per bin
  /// collection event), sourced from the actual per-bin waste type — wet vs
  /// dry — rather than the bin/household stop-kind split the daily trip log
  /// carries. Bucketing by day/week/month is done in the chart widget.
  Future<List<SupervisorWastePoint>> fetchWasteSeries() async {
    try {
      final events = await fetchWasteEvents();
      return events
          .map((e) => SupervisorWastePoint(
                date: e.date,
                wetKg: e.isWet ? e.weightKg : 0,
                dryKg: e.isDry ? e.weightKg : 0,
                otherKg: (e.isWet || e.isDry) ? 0 : e.weightKg,
              ))
          .where((p) => p.hasValidDate)
          .toList();
    } on DioException catch (e) {
      throw SupervisorException(_message(e));
    } catch (e) {
      throw SupervisorException(e.toString());
    }
  }

  /// The full per-event detail behind [fetchWasteSeries] — vehicle,
  /// collection point, and status per collected bin — for the waste-summary
  /// cards' tap-through "which vehicle collected this" view. Combines BOTH
  /// bin-collection events and household waste collections, scoped to this
  /// supervisor's own trip plans either way (`mine=true` on each call).
  ///
  /// Household collections used to be entirely missing here — `BinCollectionEvent`
  /// only exists for bin scans, so a supervisor whose drivers were doing
  /// household rounds (see household_collect_sheet.dart) saw a Total/Wet/Dry
  /// summary that never moved, however much was actually collected. A
  /// household `WasteCollection` row holds all four waste-type weights on one
  /// record rather than one type per row, so it's fanned out into up to 4
  /// synthetic events (see `SupervisorWasteEvent.fromHouseholdCollectionJson`)
  /// to match the per-type shape the summary cards expect.
  Future<List<SupervisorWasteEvent>> fetchWasteEvents({
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final dio = await _dioProvider();
      final dateQuery = <String, dynamic>{
        if (from != null) 'date_from': _formatDate(from),
        if (to != null) 'date_to': _formatDate(to),
      };
      final results = await Future.wait([
        dio.get(
          _binCollectionEvents,
          queryParameters: {
            'mine': 'true',
            'status': 'Collected',
            'limit': '5000',
            ...dateQuery,
          },
        ),
        dio.get(
          _householdWasteCollections,
          queryParameters: {'mine': 'true', 'limit': '5000', ...dateQuery},
        ),
      ]);

      final binEvents = _rawList(results[0].data)
          .map((e) => SupervisorWasteEvent.fromJson(e))
          .where((p) => p.hasValidDate);
      final householdEvents = _rawList(results[1].data)
          .expand((e) => SupervisorWasteEvent.fromHouseholdCollectionJson(e))
          .where((p) => p.hasValidDate);

      return [...binEvents, ...householdEvents];
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
      final raw = await _fetchAllRaw(_staff);
      return raw.map((e) => SupervisorStaff.fromJson(e)).toList();
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
      final dio = await _dioProvider();
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
      try {
        final staff = await fetchStaff();
        return SupervisorStaffAttendanceSummary.fromStaffList(staff);
      } catch (_) {
        throw SupervisorException(_message(e));
      }
    } catch (e) {
      try {
        final staff = await fetchStaff();
        return SupervisorStaffAttendanceSummary.fromStaffList(staff);
      } catch (_) {
        throw SupervisorException(e.toString());
      }
    }
  }

  /// Staff templates (the "Teams" list).
  Future<List<SupervisorTeam>> fetchTeams() async {
    try {
      final raw = await _fetchAllRaw(_staffTemplates);
      return raw.map((e) => SupervisorTeam.fromJson(e)).toList();
    } on DioException catch (e) {
      throw SupervisorException(_message(e));
    } catch (e) {
      throw SupervisorException(e.toString());
    }
  }

  Future<List<SupervisorVehicle>> fetchVehicles() async {
    try {
      final raw = await _fetchAllRaw(ApiConfig.vehicles);
      return raw.map((e) => SupervisorVehicle.fromJson(e)).toList();
    } on DioException catch (e) {
      throw SupervisorException(_message(e));
    } catch (e) {
      throw SupervisorException(e.toString());
    }
  }

  Future<List<SupervisorCollectionPoint>> fetchCollectionPoints() async {
    try {
      final raw = await _fetchAllRaw(_collectionPoints);
      return raw.map((e) => SupervisorCollectionPoint.fromJson(e)).toList();
    } on DioException catch (e) {
      throw SupervisorException(_message(e));
    } catch (e) {
      throw SupervisorException(e.toString());
    }
  }

  Future<List<SupervisorHousehold>> fetchHouseholds() async {
    try {
      final raw = await _fetchAllRaw(_households);
      return raw.map((e) => SupervisorHousehold.fromJson(e)).toList();
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
      final dio = await _dioProvider();
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
      _fetchAvailableStaffByRole('driver',
          excludeTemplateId: excludeTemplateId);

  Future<List<SupervisorCrewOption>> fetchAvailableOperators({
    String? excludeTemplateId,
  }) =>
      _fetchAvailableStaffByRole('operator',
          excludeTemplateId: excludeTemplateId);

  Future<List<SupervisorCrewOption>> _fetchAvailableStaffByRole(
    String role, {
    String? excludeTemplateId,
  }) async {
    try {
      final dio = await _dioProvider();
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
      final raw = await _fetchAllRaw(_staff);
      final options = <SupervisorCrewOption>[];
      for (final j in raw) {
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
  Future<List<SupervisorAltStaffTemplate>>
      fetchAlternativeStaffTemplates() async {
    try {
      final dio = await _dioProvider();
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
      final dio = await _dioProvider();
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
      final dio = await _dioProvider();
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
      final dio = await _dioProvider();
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
      final dio = await _dioProvider();
      await dio.post(_staffTemplates, data: {
        'driver_id': driverId,
        'operator_id': operatorId,
        'extra_operator_id': extraOperatorIds,
        if (geo?.stateId != null) 'state_id': geo!.stateId,
        if (geo?.districtId != null) 'district_id': geo!.districtId,
        if (geo?.areaTypeId != null) 'area_type_id': geo!.areaTypeId,
        if (geo?.corporationId != null) 'corporation_id': geo!.corporationId,
        if (geo?.municipalityId != null) 'municipality_id': geo!.municipalityId,
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

  /// Fetches every page of a paginated master-list endpoint (staff, teams,
  /// vehicles, collection points, households/customers), following the
  /// backend's `next` link until exhausted.
  ///
  /// The backend paginates every list at 20 rows by default
  /// (`LimitOffsetWithPage`, `PAGE_SIZE = 20`). A single unpaginated GET only
  /// ever sees page one, so a company with more than 20 of something — the
  /// 130+ customers under this account being the case that surfaced it —
  /// silently lost everything past the 20th. `?limit=200` cuts the common
  /// case to one request; `next` covers however many more pages remain
  /// (there is no server-side cap on `limit`, so this never needs raising).
  Future<List<Map<String, dynamic>>> _fetchAllRaw(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final dio = await _dioProvider();
    final combined = <Map<String, dynamic>>[];

    var res = await dio.get(
      path,
      queryParameters: {'limit': 200, ...?queryParameters},
    );
    combined.addAll(_rawList(res.data));

    var next = _nextPageUrl(res.data);
    while (next != null) {
      res = await dio.get(next);
      combined.addAll(_rawList(res.data));
      next = _nextPageUrl(res.data);
    }
    return combined;
  }

  String? _nextPageUrl(dynamic data) {
    if (data is Map && data['next'] is String) {
      final next = data['next'] as String;
      return next.isEmpty ? null : next;
    }
    return null;
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
