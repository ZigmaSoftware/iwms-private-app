import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:iwms_citizen_app/modules/module5_supervisor/data/supervisor_models.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/data/supervisor_repository.dart';

// ============================================================
// EVENTS
// ============================================================

abstract class SupervisorEvent {
  const SupervisorEvent();
}

/// Initial bootstrap: load the zone scope then today's assignments.
class SupervisorLoadRequested extends SupervisorEvent {
  const SupervisorLoadRequested();
}

/// Pull-to-refresh / FAB refresh — re-fetch assignments for the loaded scope.
class SupervisorRefreshRequested extends SupervisorEvent {
  const SupervisorRefreshRequested();
}

// ============================================================
// STATE
// ============================================================

enum SupervisorStatus { initial, loading, ready, empty, failure }

class SupervisorState {
  final SupervisorStatus status;
  final SupervisorZoneScope scope;
  final List<SupervisorAssignment> assignments;
  final SupervisorKpis kpis;
  final List<SupervisorAlert> alerts;
  final String? errorMessage;

  const SupervisorState({
    this.status = SupervisorStatus.initial,
    this.scope = SupervisorZoneScope.empty,
    this.assignments = const [],
    this.kpis = SupervisorKpis.empty,
    this.alerts = const [],
    this.errorMessage,
  });

  SupervisorState copyWith({
    SupervisorStatus? status,
    SupervisorZoneScope? scope,
    List<SupervisorAssignment>? assignments,
    SupervisorKpis? kpis,
    List<SupervisorAlert>? alerts,
    String? errorMessage,
  }) {
    return SupervisorState(
      status: status ?? this.status,
      scope: scope ?? this.scope,
      assignments: assignments ?? this.assignments,
      kpis: kpis ?? this.kpis,
      alerts: alerts ?? this.alerts,
      errorMessage: errorMessage,
    );
  }

  List<SupervisorAssignment> get inProgress =>
      assignments.where((a) => a.isInProgress).toList();
  List<SupervisorAssignment> get completed =>
      assignments.where((a) => a.isCompleted).toList();
  List<SupervisorAssignment> get pendingReview =>
      assignments.where((a) => a.isPendingApproval).toList();

  /// Human-readable scope for the header. The government backend is
  /// hierarchy-based (no zone map), so a supervisor's scope is best described by
  /// the distinct areas (panchayats/wards) of the trips they own today, e.g.
  /// "Anthiyur Panchayat" or "Anthiyur Panchayat +1". Falls back to the
  /// zone-scope names when present, else empty (header then shows its default).
  String get scopeLabel {
    final areas = <String>{};
    for (final a in assignments) {
      final name = a.areaName.trim();
      if (name.isNotEmpty && name.toLowerCase() != 'unassigned area') {
        areas.add(name);
      }
    }
    if (areas.isEmpty) {
      final zones = scope.zoneNames.where((z) => z.trim().isNotEmpty).toList();
      if (zones.isEmpty) return '';
      return zones.length == 1
          ? zones.first
          : '${zones.first} +${zones.length - 1}';
    }
    final list = areas.toList();
    return list.length == 1 ? list.first : '${list.first} +${list.length - 1}';
  }
}

// ============================================================
// BLOC
// ============================================================

class SupervisorBloc extends Bloc<SupervisorEvent, SupervisorState> {
  final SupervisorRepository _repo;

  SupervisorBloc({required SupervisorRepository repository})
      : _repo = repository,
        super(const SupervisorState()) {
    on<SupervisorLoadRequested>(_onLoad);
    on<SupervisorRefreshRequested>(_onRefresh);
  }

  Future<void> _onLoad(
    SupervisorLoadRequested event,
    Emitter<SupervisorState> emit,
  ) async {
    emit(state.copyWith(status: SupervisorStatus.loading));
    try {
      final scope = await _repo.fetchMyZoneScope();
      await _loadAssignments(scope, emit);
    } on SupervisorException catch (e) {
      emit(state.copyWith(
        status: SupervisorStatus.failure,
        errorMessage: e.message,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: SupervisorStatus.failure,
        errorMessage: 'Failed to load supervisor data: $e',
      ));
    }
  }

  Future<void> _onRefresh(
    SupervisorRefreshRequested event,
    Emitter<SupervisorState> emit,
  ) async {
    try {
      await _loadAssignments(state.scope, emit);
    } on SupervisorException catch (e) {
      emit(state.copyWith(
        status: SupervisorStatus.failure,
        errorMessage: e.message,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: SupervisorStatus.failure,
        errorMessage: 'Failed to refresh: $e',
      ));
    }
  }

  Future<void> _loadAssignments(
    SupervisorZoneScope scope,
    Emitter<SupervisorState> emit,
  ) async {
    // Show only THIS supervisor's assignments (trip plans they supervise),
    // scoped to today. If the device/backend day has drifted forward by one
    // day, fall back once to yesterday so the supervisor still sees the latest
    // active demo trips instead of an empty dashboard.
    final today = DateTime.now();
    var assignments = await _repo.fetchAssignments(mine: true, date: today);
    if (assignments.isEmpty) {
      assignments = await _repo.fetchAssignments(
        mine: true,
        date: today.subtract(const Duration(days: 1)),
      );
    }
    final kpis = SupervisorKpis.fromAssignments(assignments);
    final alerts = SupervisorAlert.fromAssignments(assignments);

    emit(state.copyWith(
      status:
          assignments.isEmpty ? SupervisorStatus.empty : SupervisorStatus.ready,
      scope: scope,
      assignments: assignments,
      kpis: kpis,
      alerts: alerts,
    ));
  }
}
