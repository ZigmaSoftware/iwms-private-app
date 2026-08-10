import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:iwms_private_app/core/api_config.dart';
import 'package:iwms_private_app/core/push/push_notification_service.dart';
import 'package:iwms_private_app/core/ui/app_flash.dart';
import 'package:iwms_private_app/data/repositories/staff_notification_repository.dart';
import 'package:iwms_private_app/data/repositories/trip_retrip_repository.dart';
import 'package:iwms_private_app/data/repositories/vehicle_breakdown_repository.dart';
import 'package:iwms_private_app/modules/module1_citizen/citizen/map.dart';
import 'package:iwms_private_app/modules/module5_supervisor/data/supervisor_models.dart';
import 'package:iwms_private_app/modules/module5_supervisor/data/supervisor_grievance_repository.dart';
import 'package:iwms_private_app/modules/module5_supervisor/data/supervisor_repository.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/screens/supervisor_history_screen.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/screens/supervisor_staff_attendance_screen.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/screens/supervisor_staff_screen.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/screens/supervisor_teams_screen.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/screens/supervisor_vehicles_screen.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/screens/supervisor_breakdowns_screen.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/screens/supervisor_retrip_requests_screen.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/screens/supervisor_collection_points_screen.dart';
import 'package:iwms_private_app/modules/module5_supervisor/logic/supervisor_bloc.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/screens/supervisor_grievance_screen.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/theme/supervisor_theme.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/widgets/supervisor_cards.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/widgets/supervisor_header.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/widgets/supervisor_state_views.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/widgets/supervisor_visuals.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/widgets/supervisor_waste_summary_cards.dart';
import 'package:iwms_private_app/shared/widgets/staff_notifications_screen.dart';

/// Dashboard tab — header + zone KPIs + activity/alerts feed.
class SupervisorHomePage extends StatefulWidget {
  const SupervisorHomePage({
    super.key,
    required this.name,
    required this.onLogout,
    this.empId,
    this.onOpenTrips,
    this.onOpenAssignments,
    this.onOpenTeam,
  });

  final String name;
  final String? empId;
  final VoidCallback onLogout;
  final VoidCallback? onOpenTrips;
  final VoidCallback? onOpenAssignments;
  final VoidCallback? onOpenTeam;

  @override
  State<SupervisorHomePage> createState() => _SupervisorHomePageState();
}

enum _QuickActionFilter { actions, approvals, explore }

class _SupervisorHomePageState extends State<SupervisorHomePage> {
  _QuickActionFilter _selectedQuickActionFilter = _QuickActionFilter.actions;
  final SupervisorGrievanceRepository _grievanceRepo =
      SupervisorGrievanceRepository();
  int _grievanceCount = 0;
  int _collectionPointCount = 0;
  int _pendingBreakdownCount = 0;
  int _pendingRetripCount = 0;
  int _unreadNotificationCount = 0;
  final StaffNotificationRepository _notificationRepo =
      StaffNotificationRepository();
  final VehicleBreakdownRepository _breakdownRepo =
      VehicleBreakdownRepository();
  final TripRetripRepository _retripRepo = TripRetripRepository();

  @override
  void initState() {
    super.initState();
    _loadGrievanceCount();
    _loadHierarchyCounts();
    _loadPendingBreakdownCount();
    _loadPendingRetripCount();
    _loadUnreadNotificationCount();
    unawaited(PushNotificationService.instance.initAndRegister(
      registerUrl: ApiConfig.registerStaffFcmToken,
    ));
  }

  Future<void> _loadPendingBreakdownCount() async {
    try {
      final reports =
          await _breakdownRepo.fetchBreakdowns(approvalStatus: 'PENDING');
      if (!mounted) return;
      setState(() => _pendingBreakdownCount = reports.length);
    } catch (_) {}
  }

  Future<void> _loadPendingRetripCount() async {
    try {
      final requests = await _retripRepo.fetchRequests(status: 'Pending');
      if (!mounted) return;
      setState(() => _pendingRetripCount = requests.length);
    } catch (_) {}
  }

  Future<void> _loadUnreadNotificationCount() async {
    try {
      final count = await _notificationRepo.fetchUnreadCount();
      if (!mounted) return;
      setState(() => _unreadNotificationCount = count);
    } catch (_) {}
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const StaffNotificationsScreen()),
    );
    _loadUnreadNotificationCount();
  }

  Future<void> _loadGrievanceCount() async {
    try {
      final tickets = await _grievanceRepo.fetchTickets();
      if (!mounted) return;
      setState(() => _grievanceCount = tickets.length);
    } catch (_) {}
  }

  Future<void> _loadHierarchyCounts() async {
    try {
      final repo = SupervisorRepository();
      final collectionPoints = await repo.fetchCollectionPoints();
      if (!mounted) return;
      setState(() {
        _collectionPointCount = collectionPoints.length;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SupervisorBloc, SupervisorState>(
      builder: (context, state) {
        final kpis = state.kpis;
        return Container(
          color: SupervisorTheme.background,
          child: Column(
            children: [
              SupervisorHeader(
                name: widget.name,
                empId: widget.empId,
                onLogout: widget.onLogout,
                zoneLabel: state.scopeLabel,
                zoneCount: state.scope.zoneIds.length,
                onNotificationsTap: _openNotifications,
                unreadNotificationCount: _unreadNotificationCount,
              ),
              Expanded(
                // Static dotted background: painted once behind the scroll view
                // so it stays fixed while the content scrolls. The KPI cards are
                // transparent tints (very low fill + near-zero blur), so the
                // dots show through them via normal compositing — no need to put
                // the pattern inside the viewport.
                child: SupervisorPatternBackground(
                  child: _buildBody(context, state, kpis),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    SupervisorState state,
    SupervisorKpis kpis,
  ) {
    if (state.status == SupervisorStatus.loading ||
        state.status == SupervisorStatus.initial) {
      return const SupervisorLoadingView();
    }
    if (state.status == SupervisorStatus.failure) {
      return SupervisorErrorView(
        message: state.errorMessage ?? 'Something went wrong',
        onRetry: () =>
            context.read<SupervisorBloc>().add(const SupervisorLoadRequested()),
      );
    }

    return RefreshIndicator(
      color: SupervisorTheme.accent,
      onRefresh: () async {
        context.read<SupervisorBloc>().add(const SupervisorRefreshRequested());
        await _loadGrievanceCount();
        await _loadHierarchyCounts();
        await _loadPendingBreakdownCount();
        await _loadPendingRetripCount();
        await _loadUnreadNotificationCount();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SupervisorWasteSummaryCards(),
              const SizedBox(height: 18),
              const Text(
                'Quick actions',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: SupervisorTheme.strongText,
                ),
              ),
              const SizedBox(height: 10),
              _quickActionFilters(),
              const SizedBox(height: 12),
              _quickActions(context),
              const SizedBox(height: 20),
              const Text(
                'Today at a glance',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: SupervisorTheme.strongText,
                ),
              ),
              const SizedBox(height: 10),
              _glanceGrid(kpis),
              const SizedBox(height: 22),
              Row(
                children: [
                  Text(
                    'Activity & alerts',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: SupervisorTheme.strongText,
                    ),
                  ),
                  const Spacer(),
                  if (widget.onOpenAssignments != null)
                    TextButton(
                      onPressed: widget.onOpenAssignments,
                      child: const Text('Review',
                          style: TextStyle(
                            color: SupervisorTheme.accent,
                            fontWeight: FontWeight.w700,
                          )),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (state.alerts.isEmpty)
                _allClearTile()
              else
                ...state.alerts.map(
                  (a) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SupervisorAlertTile(alert: a),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickActionFilters() {
    return Row(
      children: [
        Expanded(
          child: SupervisorTimeChip(
            label: 'Actions',
            selected: _selectedQuickActionFilter == _QuickActionFilter.actions,
            onTap: () => setState(
                () => _selectedQuickActionFilter = _QuickActionFilter.actions),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SupervisorTimeChip(
            label: 'Reports',
            selected:
                _selectedQuickActionFilter == _QuickActionFilter.approvals,
            badgeCount: _pendingBreakdownCount + _pendingRetripCount,
            onTap: () => setState(() =>
                _selectedQuickActionFilter = _QuickActionFilter.approvals),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SupervisorTimeChip(
            label: 'explore',
            selected: _selectedQuickActionFilter == _QuickActionFilter.explore,
            onTap: () => setState(
                () => _selectedQuickActionFilter = _QuickActionFilter.explore),
          ),
        ),
      ],
    );
  }

  /// Glassmorphism quick-action grid filtered by the pill row above. Each tile
  /// uses the same liquid-glass surface as the KPI cards
  /// ([SupervisorGlassActionTile]) with a raster icon + label.
  Widget _quickActions(BuildContext context) {
    void soon(String name) {
      AppFlash.info(context, '$name — coming soon');
    }

    final assignments = context.read<SupervisorBloc>().state.assignments;
    final supervisorVehicleCount = assignments
        .map((assignment) => assignment.vehicleNo.trim())
        .where((vehicleNo) => vehicleNo.isNotEmpty)
        .toSet()
        .length;
    final supervisorTeamCount = assignments
        .map((assignment) => assignment.staffTemplateId?.trim() ?? '')
        .where((templateId) => templateId.isNotEmpty)
        .toSet()
        .length;
    final tripCount = assignments.length;

    final tiles = <_QuickActionSpec>[
      _QuickActionSpec(
        filter: _QuickActionFilter.actions,
        tile: SupervisorGlassActionTile(
          iconAsset: 'assets/icons/collection_point.png',
          label: 'Points',
          badgeLabel: '$_collectionPointCount',
          onTap: () {
            final bloc = context.read<SupervisorBloc>();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BlocProvider<SupervisorBloc>.value(
                  value: bloc,
                  child: const SupervisorCollectionPointsScreen(),
                ),
              ),
            );
          },
        ),
      ),
      _QuickActionSpec(
        filter: _QuickActionFilter.actions,
        tile: SupervisorGlassActionTile(
          iconAsset: 'assets/icons/attendance.png',
          label: 'Attendance',
          // Read-only oversight: staff directory → each staff's punch records
          // from app_recognized (NOT a punch screen).
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const SupervisorStaffAttendanceScreen(),
            ),
          ),
        ),
      ),
      _QuickActionSpec(
        filter: _QuickActionFilter.actions,
        tile: SupervisorGlassActionTile(
          iconAsset: 'assets/icons/staff.png',
          label: 'Staffs',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SupervisorStaffScreen()),
          ),
        ),
      ),
      _QuickActionSpec(
        filter: _QuickActionFilter.actions,
        tile: SupervisorGlassActionTile(
          iconAsset: 'assets/icons/garbage-truck.png',
          label: 'Trips',
          badgeLabel: '$tripCount',
          onTap: widget.onOpenTrips,
        ),
      ),
      _QuickActionSpec(
        filter: _QuickActionFilter.actions,
        tile: SupervisorGlassActionTile(
          iconAsset: 'assets/icons/trucks.png',
          label: 'Vehicles',
          badgeLabel: '$supervisorVehicleCount',
          onTap: () {
            final bloc = context.read<SupervisorBloc>();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BlocProvider<SupervisorBloc>.value(
                  value: bloc,
                  child: const SupervisorVehiclesScreen(),
                ),
              ),
            );
          },
        ),
      ),
      _QuickActionSpec(
        filter: _QuickActionFilter.actions,
        tile: SupervisorGlassActionTile(
          iconAsset: 'assets/icons/teams.png',
          label: 'Teams',
          badgeLabel: '$supervisorTeamCount',
          onTap: () {
            // Share the existing SupervisorBloc so the Teams screen can tell
            // whether each team is on a trip right now.
            final bloc = context.read<SupervisorBloc>();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BlocProvider<SupervisorBloc>.value(
                  value: bloc,
                  child: const SupervisorTeamsScreen(),
                ),
              ),
            );
          },
        ),
      ),
      _QuickActionSpec(
        filter: _QuickActionFilter.actions,
        tile: SupervisorGlassActionTile(
          iconAsset: 'assets/icons/grievance.png',
          label: 'Grievances',
          badgeLabel: '$_grievanceCount',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const SupervisorGrievanceScreen(),
            ),
          ),
        ),
      ),
      _QuickActionSpec(
        filter: _QuickActionFilter.actions,
        tile: SupervisorGlassActionTile(
          iconAsset: 'assets/icons/map.png',
          label: 'Map',
          // Opens the citizen live-tracking map (all vehicles) — MapScreen
          // self-provides its VehicleBloc, so it works from any context.
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const MapScreen()),
          ),
        ),
      ),
      _QuickActionSpec(
        filter: _QuickActionFilter.actions,
        tile: SupervisorGlassActionTile(
          iconAsset: 'assets/icons/history (1).png',
          label: 'History',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SupervisorHistoryScreen()),
          ),
        ),
      ),
      _QuickActionSpec(
        filter: _QuickActionFilter.actions,
        tile: SupervisorGlassActionTile(
          iconAsset: 'assets/icons/reports.png',
          label: 'Reports',
          onTap: () => soon('Reports'),
        ),
      ),
      _QuickActionSpec(
        filter: _QuickActionFilter.approvals,
        tile: SupervisorGlassActionTile(
          iconAsset: 'assets/icons/car-repair.png',
          label: 'Breakdowns',
          badgeLabel:
              _pendingBreakdownCount > 0 ? '$_pendingBreakdownCount' : null,
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const SupervisorBreakdownsScreen(),
              ),
            );
            _loadPendingBreakdownCount();
          },
        ),
      ),
      _QuickActionSpec(
        filter: _QuickActionFilter.approvals,
        tile: SupervisorGlassActionTile(
          iconAsset: 'assets/icons/garbage-truck.png',
          label: 'Re-Trips',
          badgeLabel: _pendingRetripCount > 0 ? '$_pendingRetripCount' : null,
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const SupervisorRetripRequestsScreen(),
              ),
            );
            _loadPendingRetripCount();
          },
        ),
      ),
    ];

    const spacing = 10.0;
    final visibleTiles = tiles
        .where((item) => item.filter == _selectedQuickActionFilter)
        .toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final tileSize = (constraints.maxWidth - (spacing * 3)) / 4;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final item in visibleTiles)
              SizedBox.square(
                dimension: tileSize,
                child: item.tile,
              ),
          ],
        );
      },
    );
  }

  /// "Today at a glance" grid (2×2) of solid-white illustrated stat cards.
  /// The first two carry artwork; the last two stay image-less until their
  /// illustrations are supplied.
  Widget _glanceGrid(SupervisorKpis kpis) {
    final cards = <SupervisorGlanceCard>[
      SupervisorGlanceCard(
        value: '${kpis.total}',
        label: 'Trips today',
        icon: Icons.route_rounded,
        color: SupervisorTheme.info,
        imageAsset: 'assets/images/trips_today.png',
        onTap: widget.onOpenTrips,
      ),
      SupervisorGlanceCard(
        value: '${kpis.inProgress}',
        label: 'In progress',
        icon: Icons.directions_run_rounded,
        color: const Color(0xFF0EA5E9),
        imageAsset: 'assets/images/in_progress.png',
        onTap: widget.onOpenTrips,
      ),
      SupervisorGlanceCard(
        value: '${kpis.completed}',
        label: 'Completed',
        icon: Icons.check_circle_rounded,
        color: SupervisorTheme.success,
        imageAsset: 'assets/images/completed_trip.png',
        onTap: widget.onOpenTrips,
      ),
      SupervisorGlanceCard(
        value: '${kpis.pendingReview}',
        label: 'Pending review',
        icon: Icons.hourglass_bottom_rounded,
        color: SupervisorTheme.warning,
        imageAsset: 'assets/images/pending_trip.png',
        onTap: widget.onOpenAssignments,
      ),
    ];

    const spacing = 12.0;
    const height = 116.0;

    Widget cell(Widget card) =>
        Expanded(child: SizedBox(height: height, child: card));

    Widget row(Widget a, Widget b) => Row(
          children: [
            cell(a),
            const SizedBox(width: spacing),
            cell(b),
          ],
        );

    return Column(
      children: [
        row(cards[0], cards[1]),
        const SizedBox(height: spacing),
        row(cards[2], cards[3]),
      ],
    );
  }

  Widget _allClearTile() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SupervisorTheme.accentSoft,
        borderRadius: SupervisorTheme.cardRadius,
        border:
            Border.all(color: SupervisorTheme.accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.task_alt_rounded,
            color: SupervisorTheme.accent,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'All clear — no pending alerts in your zones.',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: SupervisorTheme.accentDeep,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionSpec {
  const _QuickActionSpec({
    required this.filter,
    required this.tile,
  });

  final _QuickActionFilter filter;
  final SupervisorGlassActionTile tile;
}
