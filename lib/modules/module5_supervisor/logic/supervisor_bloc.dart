import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../data/supervisor_trip_workbench.dart';
import 'package:iwms_private_app/data/models/vehicle_breakdown_models.dart';
import 'package:iwms_private_app/data/repositories/vehicle_breakdown_repository.dart';

import 'package:iwms_private_app/data/models/trip_retrip_models.dart';
import 'package:iwms_private_app/data/repositories/trip_retrip_repository.dart';
import 'package:iwms_private_app/modules/module5_supervisor/data/supervisor_models.dart';
import 'package:iwms_private_app/modules/module5_supervisor/data/supervisor_repository.dart';

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
  const SupervisorRefreshRequested({this.completer});
  final Completer<void>? completer;
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
  final List<TripRetripRequest> retripRequests;
  final String? errorMessage;
  final SupervisorTripWorkbench? workbench;
  final bool refreshing;
  final String? attentionError;
  final List<VehicleBreakdownReport> pendingBreakdowns;
  final DateTime? updatedAt;

  const SupervisorState({
    this.status = SupervisorStatus.initial,
    this.scope = SupervisorZoneScope.empty,
    this.assignments = const [],
    this.kpis = SupervisorKpis.empty,
    this.alerts = const [],
    this.retripRequests = const [],
    this.errorMessage,
    this.workbench,
    this.refreshing = false,
    this.attentionError,
    this.pendingBreakdowns = const [],
    this.updatedAt,
  });

  SupervisorState copyWith({
    SupervisorStatus? status,
    SupervisorZoneScope? scope,
    List<SupervisorAssignment>? assignments,
    SupervisorKpis? kpis,
    List<SupervisorAlert>? alerts,
    List<TripRetripRequest>? retripRequests,
    String? errorMessage,
    SupervisorTripWorkbench? workbench,
    bool? refreshing,
    String? attentionError,
    List<VehicleBreakdownReport>? pendingBreakdowns,
    DateTime? updatedAt,
  }) {
    return SupervisorState(
      status: status ?? this.status,
      scope: scope ?? this.scope,
      assignments: assignments ?? this.assignments,
      kpis: kpis ?? this.kpis,
      alerts: alerts ?? this.alerts,
      retripRequests: retripRequests ?? this.retripRequests,
      errorMessage: errorMessage,
      workbench: workbench ?? this.workbench,
      refreshing: refreshing ?? this.refreshing,
      attentionError: attentionError,
      pendingBreakdowns: pendingBreakdowns ?? this.pendingBreakdowns,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  List<SupervisorAssignment> get activeTrips =>
      workbench?.remaining ?? const [];
  List<SupervisorAssignment> get carriedOver =>
      workbench?.carriedOver ?? const [];
  bool get hasOutstandingDecisions =>
      pendingRetripRequests.isNotEmpty ||
      pendingBreakdowns.isNotEmpty ||
      attentionError != null;

  List<SupervisorAssignment> get inProgress =>
      assignments.where((a) => a.isInProgress).toList();
  List<SupervisorAssignment> get completed =>
      assignments.where((a) => a.isCompleted).toList();
  List<SupervisorAssignment> get pendingReview =>
      assignments.where((a) => a.isPendingApproval).toList();
  List<TripRetripRequest> get pendingRetripRequests =>
      retripRequests.where((r) => r.isPending).toList();

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
  final TripRetripRepository _retripRepo;
  final VehicleBreakdownRepository _breakdownRepo;
  Future<void>? _inFlight;

  SupervisorBloc({
    required SupervisorRepository repository,
    TripRetripRepository? retripRepository,
    VehicleBreakdownRepository? breakdownRepository,
  })  : _repo = repository,
        _retripRepo = retripRepository ?? TripRetripRepository(),
        _breakdownRepo = breakdownRepository ?? VehicleBreakdownRepository(),
        super(const SupervisorState()) {
    on<SupervisorLoadRequested>((event, emit) => _load(emit));
    on<SupervisorRefreshRequested>((event, emit) async {
      try {
        await _load(emit);
      } finally {
        event.completer?.complete();
      }
    });
  }

  Future<void> refresh() {
    final completer = Completer<void>();
    add(SupervisorRefreshRequested(completer: completer));
    return completer.future;
  }

  Future<void> _load(Emitter<SupervisorState> emit) async {
    // Coalesce timer, pull-to-refresh and resume requests. An older response
    // must never restore a trip which a newer request has already completed.
    if (_inFlight != null) {
      await _inFlight;
      return;
    }
    final done = Completer<void>();
    _inFlight = done.future;
    emit(state.copyWith(
        refreshing: true,
        status:
            state.workbench == null ? SupervisorStatus.loading : state.status,
        attentionError: state.attentionError));
    try {
      final workbench = await _repo.fetchTripWorkbench();
      var retrips = state.retripRequests;
      var breakdowns = state.pendingBreakdowns;
      final failures = <String>[];
      await Future.wait([
        () async {
          try {
            retrips = await _retripRepo.fetchRequests(status: 'Pending');
          } catch (_) {
            failures.add('Re-Trip requests');
          }
        }(),
        () async {
          try {
            breakdowns = await _breakdownRepo.fetchBreakdowns(
                approvalStatus: 'PENDING', mine: true);
          } catch (_) {
            failures.add('breakdown reports');
          }
        }(),
      ]);
      emit(state.copyWith(
        status: workbench.assignments.isEmpty
            ? SupervisorStatus.empty
            : SupervisorStatus.ready,
        workbench: workbench,
        assignments: workbench.today,
        kpis: SupervisorKpis.fromAssignments(workbench.today),
        alerts: SupervisorAlert.fromAssignments(workbench.today),
        retripRequests: retrips,
        pendingBreakdowns: breakdowns,
        attentionError: failures.isEmpty
            ? null
            : 'Could not update ${failures.join(' and ')}. Decisions may still be pending.',
        refreshing: false,
        updatedAt: DateTime.now(),
      ));
    } catch (e) {
      final forbidden = e is SupervisorException && e.code == 'FORBIDDEN';
      if (forbidden) {
        emit(const SupervisorState(
            status: SupervisorStatus.failure,
            errorMessage: 'You do not have access to these trips.'));
      } else {
        emit(state.copyWith(
            status: state.workbench == null
                ? SupervisorStatus.failure
                : state.status,
            errorMessage: 'Could not update trips. Please retry.',
            attentionError: state.attentionError,
            refreshing: false));
      }
    } finally {
      _inFlight = null;
      done.complete();
    }
  }
}
