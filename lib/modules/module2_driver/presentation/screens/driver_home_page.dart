import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:animations/animations.dart';
import 'package:intl/intl.dart';
import 'package:iwms_private_app/core/env.dart';
import 'package:iwms_private_app/core/ui/app_copy.dart';
import 'package:iwms_private_app/core/ui/app_flash.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/di.dart';
import '../../../../core/geofence_config.dart';
import 'package:iwms_private_app/data/models/operator_trip_models.dart';
import 'package:iwms_private_app/data/models/vehicle_model.dart';
import 'package:iwms_private_app/data/repositories/operator_trip_repository.dart';
import 'package:iwms_private_app/data/repositories/staff_notification_repository.dart';
import 'package:iwms_private_app/shared/widgets/staff_notifications_screen.dart';
import '../../../../logic/vehicle_tracking/vehicle_bloc.dart';
import '../../../../logic/vehicle_tracking/vehicle_event.dart';
import 'package:iwms_private_app/logic/auth/auth_bloc.dart';
import 'package:iwms_private_app/logic/auth/auth_event.dart';
import 'package:iwms_private_app/logic/auth/auth_state.dart';
import 'package:iwms_private_app/core/api_config.dart';
import 'package:iwms_private_app/core/push/push_notification_service.dart';
import 'package:iwms_private_app/core/map/map_style.dart';
import 'package:iwms_private_app/core/ors_service.dart';
import 'package:iwms_private_app/core/network/authorized_dio.dart';
import 'package:iwms_private_app/modules/module2_driver/presentation/screens/attendance/attendance_driver.dart';
import 'package:iwms_private_app/modules/module2_driver/presentation/screens/captain_home_tab.dart';
import 'package:iwms_private_app/modules/module2_driver/presentation/state/collection_mode_store.dart';
import 'package:iwms_private_app/modules/module2_driver/presentation/state/trip_sequence.dart';
import 'package:iwms_private_app/modules/module2_driver/presentation/theme/captain_theme.dart';
import 'package:iwms_private_app/modules/module2_driver/presentation/theme/driver_theme.dart';
import 'package:iwms_private_app/modules/module2_driver/presentation/widgets/captain_glass.dart';
import 'package:iwms_private_app/modules/module2_driver/presentation/widgets/captain_nav_bar.dart';
import 'package:iwms_private_app/modules/module2_driver/presentation/widgets/driver_header.dart';
import 'package:iwms_private_app/modules/module2_driver/presentation/widgets/driver_report_actions_sheet.dart';
import 'package:iwms_private_app/modules/module3_operator/presentation/screens/operator_qr_scanner.dart';
import 'package:iwms_private_app/modules/module3_operator/presentation/screens/operator_trip_home_screen.dart'
    show OperatorTripScanScreen;
import 'package:iwms_private_app/modules/module3_operator/presentation/theme/operator_theme.dart';
import 'package:iwms_private_app/modules/module3_operator/presentation/widgets/operator_cp_card.dart';
import 'package:iwms_private_app/modules/module3_operator/presentation/widgets/operator_trip_summary_card.dart';
import 'package:iwms_private_app/shared/constants/skip_reasons.dart';

const Duration _kNavigationTransitionDuration = Duration(milliseconds: 600);
const List<String> _skipReasons = kSkipReasons;

/// Colour matrix that turns the light OSM raster into a dark-map look
/// (invert luminance, then rotate the hue back so water/land keep sensible
/// tones). Applied via [ColorFiltered] only when the Captain dark theme is on.
const List<double> _darkMapMatrix = <double>[
  -0.6, -0.4, -0.4, 0, 255, //
  -0.4, -0.6, -0.4, 0, 255, //
  -0.4, -0.4, -0.6, 0, 255, //
  0, 0, 0, 1, 0, //
];

enum _NavigationMode { overview, navigating }

enum _CustomerStatus { pending, later, collected, skipped, navigating }

/// Route polyline styling — a Google-Maps-style white casing around a saturated
/// royal-blue core. The white edge keeps the line legible on dark and satellite
/// imagery; the blue core stands out on light maps. Works across all map modes.
const Color _kRouteCore = Color(0xFF2563EB);
const Color _kRouteCasing = Colors.white;
// Upcoming (not-yet-active) legs: a muted slate grey, drawn dotted. Semi-opaque
// so it reads as "deferred" on light, dark and satellite base maps.
const Color _kRouteUpcoming = Color(0x9964748B);

class _DriverAssignmentStop {
  final String assignmentId;
  final String? wardId;
  final String wardName;
  final String? customerName;
  final LatLng location;
  final String assignmentType;
  final String shift;
  // Visit-order number (1..N) shared with the map markers and the home list,
  // so the "next collection point" card reads the same sequence everywhere.
  final int sequence;

  _CustomerStatus status = _CustomerStatus.pending;
  String? skipReason;

  _DriverAssignmentStop({
    required this.assignmentId,
    required this.wardId,
    required this.wardName,
    required this.location,
    required this.assignmentType,
    required this.shift,
    this.sequence = 0,
    this.customerName,
    this.status = _CustomerStatus.pending,
  });

  // =====================
  // BACKWARD COMPATIBILITY
  // =====================

  String get id => assignmentId;

  String get name => (customerName != null && customerName!.trim().isNotEmpty)
      ? customerName!
      : wardName;

  String get address => wardName; // placeholder until API adds address

  String get baseAssignmentId => assignmentId.split('-').first;
}

class _TripPlannedStop {
  final String plannedStopId;
  final int sequence;
  final LatLng location;
  final String collectionPointId;
  final String propertyType;
  final bool isCollected;

  const _TripPlannedStop({
    required this.plannedStopId,
    required this.sequence,
    required this.location,
    required this.collectionPointId,
    required this.propertyType,
    this.isCollected = false,
  });
}

/// Captain shell tabs. Home is the today-first dashboard; Map hosts the
/// turn-by-turn navigation view; the centre Scan FAB owns collection.
/// (Assignments folded into Home — trip history opens from a quick action.)
enum _DriverTab { home, map, attendance, profile }

class DriverHomePage extends StatefulWidget {
  const DriverHomePage({super.key});

  @override
  State<DriverHomePage> createState() => _DriverHomePageState();
}

class _DriverHomePageState extends State<DriverHomePage> {
  _DriverTab _activeTab = _DriverTab.home;
  late final OperatorTripRepository _tripRepository;
  final MapController _mapController = MapController();
  List<_DriverAssignmentStop> _customers = [];
  List<_TripPlannedStop> _tripStops = [];
  List<LatLng> _tripPolyline = [];
  String? _activeTripId;
  String? _activeRoutePlanId;
  String? _activeVehicleType;
  List<OperatorTripHistorySummary> _currentAssignments = [];
  List<OperatorTripHistorySummary> _historyAssignments = [];
  OperatorTripToday? _todayTrip;
  // The trip whose stops the Map tab currently shows. Defaults to the primary
  // (bin) trip, but tapping a household card in the carousel switches it to
  // that household trip so the map plots customer locations instead of bins.
  OperatorTripToday? _mapTrip;
  List<OperatorTripToday> _todayTrips = [];
  OperatorTripHistoryDetail? _activeTripDetail;
  LatLng? _staticDriverLocation;
  bool _loadingCustomers = true;
  bool _loadingAssignments = true;
  bool _loadingTrip = false;
  String? _customerError;
  String? _assignmentError;
  String? _tripError;
  final StaffNotificationRepository _notificationRepository =
      StaffNotificationRepository();
  int _unreadNotificationCount = 0;

  @override
  void initState() {
    super.initState();
    // Hydrate the persisted light/dark choice before first paint settles.
    CaptainThemeStore.load();
    // Hydrate the persisted Household/Bin collection mode.
    CollectionModeStore.load();
    _tripRepository = getIt<OperatorTripRepository>();
    unawaited(PushNotificationService.instance.initAndRegister(
      registerUrl: ApiConfig.registerStaffFcmToken,
    ));
    _refreshUnreadNotificationCount();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _centerOnDriver(GammaGeofenceConfig.center),
    );
    _loadAssignmentsForDriver();
  }

  Future<void> _refreshUnreadNotificationCount() async {
    try {
      final count = await _notificationRepository.fetchUnreadCount();
      if (!mounted) return;
      setState(() => _unreadNotificationCount = count);
    } catch (_) {
      // Non-fatal — badge just stays at its last known value.
    }
  }

  Future<void> _openNotifications() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const StaffNotificationsScreen()),
    );
    _refreshUnreadNotificationCount();
  }

  VehicleModel? _selectedVehicleFrom(VehicleState state) {
    return state is VehicleLoaded ? state.selectedVehicle : null;
  }

  LatLng _resolveDriverLocation(VehicleModel? vehicle) {
    if (_staticDriverLocation != null) return _staticDriverLocation!;
    if (vehicle == null) return GammaGeofenceConfig.center;
    return LatLng(vehicle.latitude, vehicle.longitude);
  }

  VehicleModel _chooseDriverVehicle(List<VehicleModel> vehicles) {
    return vehicles.firstWhere(
      (vehicle) => (vehicle.status ?? '').toLowerCase() == 'running',
      orElse: () => vehicles.first,
    );
  }

  void _centerOnDriver(LatLng target) {
    _mapController.move(target, 15.0);
  }

  bool _tripMatchesMode(OperatorTripToday trip, CollectionMode mode) {
    return mode == CollectionMode.household
        ? trip.isHousehold
        : !trip.isHousehold;
  }

  List<OperatorTripToday> _tripsForMode(
    CollectionMode mode, [
    List<OperatorTripToday>? source,
  ]) {
    final trips = source ?? _todayTrips;
    return trips.where((trip) => _tripMatchesMode(trip, mode)).toList();
  }

  List<OperatorTripToday> get _visibleTodayTrips =>
      _tripsForMode(CollectionModeStore.mode.value);

  OperatorTripToday? _tripById(
    Iterable<OperatorTripToday> trips,
    String? assignmentUniqueId,
  ) {
    if (assignmentUniqueId == null || assignmentUniqueId.isEmpty) return null;
    for (final trip in trips) {
      if (trip.assignmentUniqueId == assignmentUniqueId) return trip;
    }
    return null;
  }

  LatLng _anchorForVisibleTripStops(
    List<_DriverAssignmentStop> stops,
    List<_TripPlannedStop> tripStops,
  ) {
    if (tripStops.isNotEmpty) {
      return _staticLocationNearStops(tripStops);
    }
    if (stops.isNotEmpty) {
      return _staticLocationNear([for (final stop in stops) stop.location]);
    }
    return GammaGeofenceConfig.center;
  }

  /// The blocker on the trip the driver is currently looking at, or null when
  /// it is open for work. Same rule the Home tab's carousel renders, so the
  /// scan button and the cards can never disagree.
  TripBlocker? _blockerForSelectedTrip() {
    final trip = _todayTrip;
    if (trip == null) return null;
    return tripBlockers(_visibleTodayTrips)[trip.assignmentUniqueId];
  }

  void _applyCollectionModeState(
    CollectionMode mode, {
    List<OperatorTripToday>? sourceTrips,
    String? preferredTripId,
  }) {
    final allTrips = sourceTrips ?? _todayTrips;
    final visibleTrips = _tripsForMode(mode, allTrips);
    final selectedTrip = _tripById(visibleTrips, preferredTripId) ??
        _tripById(visibleTrips, _mapTrip?.assignmentUniqueId) ??
        _tripById(visibleTrips, _todayTrip?.assignmentUniqueId) ??
        // Land on the trip the driver can actually work — with a 06:30 and a
        // 15:00 bin run, opening on the locked afternoon card would be a dead
        // end.
        firstWorkableTrip(visibleTrips);
    final detail = selectedTrip?.toHistoryDetail();
    final (stops, tripStops) = _buildMapStopsForTrip(selectedTrip);

    setState(() {
      _todayTrip = selectedTrip;
      _mapTrip = selectedTrip;
      _customers = stops;
      _tripStops = tripStops;
      _tripPolyline = const [];
      _activeTripId = selectedTrip?.assignmentUniqueId;
      _activeRoutePlanId = detail?.summary.tripPlan?.uniqueId;
      _activeVehicleType = null;
      _activeTripDetail = detail;
      _staticDriverLocation = _anchorForVisibleTripStops(stops, tripStops);
      _currentAssignments = [
        if (selectedTrip != null) selectedTrip.toHistorySummary(),
      ];
    });
  }

  Future<void> _onCollectionModeChanged(CollectionMode mode) async {
    if (CollectionModeStore.mode.value == mode) return;
    await CollectionModeStore.set(mode);
    if (!mounted) return;
    _applyCollectionModeState(
      mode,
      preferredTripId: _todayTrip?.assignmentUniqueId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final nameFromState = context.select<AuthBloc, String?>((bloc) =>
        bloc.state is AuthStateAuthenticated
            ? (bloc.state as AuthStateAuthenticated).userName
            : null);

    final empIdFromState = context.select<AuthBloc, String?>((bloc) =>
        bloc.state is AuthStateAuthenticated
            ? (bloc.state as AuthStateAuthenticated).emp_id
            : null);

    // Human-readable employee id (e.g. "13753223") for display in the header
    // badge. The API ships this as `employee_id`; `emp_id` is the internal
    // staff unique id ("STC-...") used only for the profile-photo lookup.
    final employeeIdFromState = context.select<AuthBloc, String?>((bloc) =>
        bloc.state is AuthStateAuthenticated
            ? (bloc.state as AuthStateAuthenticated).employeeId
            : null);

    return BlocProvider(
      create: (_) => getIt<VehicleBloc>(),
      child: BlocListener<VehicleBloc, VehicleState>(
        listener: (context, state) {
          if (state is VehicleLoaded &&
              state.selectedVehicle == null &&
              state.vehicles.isNotEmpty) {
            final defaultVehicle = _chooseDriverVehicle(state.vehicles);
            context
                .read<VehicleBloc>()
                .add(VehicleSelectionUpdated(defaultVehicle.id));
          }
        },
        child: BlocBuilder<VehicleBloc, VehicleState>(
          builder: (context, state) {
            final selectedVehicle = _selectedVehicleFrom(state);
            final driverLocation = _resolveDriverLocation(selectedVehicle);

            // Rebuild the whole Captain shell when the light/dark toggle
            // flips so every mode-aware token re-resolves.
            return ValueListenableBuilder<bool>(
              valueListenable: CaptainThemeStore.isDark,
              builder: (context, _, __) =>
                  ValueListenableBuilder<CollectionMode>(
                // Rebuild when the Household/Bin toggle flips, so the
                // carousel, home list, map and scan button all switch to
                // showing only the selected mode's trips.
                valueListenable: CollectionModeStore.mode,
                builder: (context, collectionMode, __) => _buildShell(
                  context,
                  driverLocation,
                  nameFromState,
                  empIdFromState,
                  employeeIdFromState,
                  selectedVehicle,
                  collectionMode,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildShell(
    BuildContext context,
    LatLng driverLocation,
    String? nameFromState,
    String? empIdFromState,
    String? employeeIdFromState,
    VehicleModel? selectedVehicle,
    CollectionMode collectionMode,
  ) {
    final showCollectionToggle =
        _activeTab == _DriverTab.home || _activeTab == _DriverTab.map;
    final pullInHeader =
        _activeTab == _DriverTab.attendance || _activeTab == _DriverTab.profile;

    return Scaffold(
      backgroundColor: DriverTheme.background,
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            DriverHeader(
              name: nameFromState ?? 'Driver',
              empId: empIdFromState ?? '',
              displayId: employeeIdFromState,
              locationLabel: _todayTrip?.areaName,
              onLogout: () => _logout(context),
              onProfileTap: () =>
                  setState(() => _activeTab = _DriverTab.profile),
              onDangerTap: () => DriverReportActionsSheet.show(context),
              onNotificationsTap: _openNotifications,
              unreadNotificationCount: _unreadNotificationCount,
              collapsed: pullInHeader,
              showCollectionModeToggle: showCollectionToggle,
              collectionMode: collectionMode,
              onCollectionModeChanged: _onCollectionModeChanged,
            ),
            Expanded(
              child: PageTransitionSwitcher(
                duration: const Duration(milliseconds: 320),
                transitionBuilder: (child, animation, secondaryAnimation) {
                  return SharedAxisTransition(
                    animation: animation,
                    secondaryAnimation: secondaryAnimation,
                    transitionType: SharedAxisTransitionType.horizontal,
                    child: child,
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey<_DriverTab>(_activeTab),
                  child: _buildTab(
                    _activeTab,
                    driverLocation,
                    nameFromState ?? 'Driver',
                    empIdFromState ?? '',
                    selectedVehicle,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: CaptainScanFab(onPressed: _openScanner),
      bottomNavigationBar: CaptainNavBar(
        activeIndex: _activeTab.index,
        onTabSelected: (index) {
          final tab = _tabFromIndex(index);
          if (_activeTab != tab) setState(() => _activeTab = tab);
        },
        items: const [
          CaptainNavItem(
            icon: Icons.home_rounded,
            label: AppCopy.driverTabHome,
          ),
          CaptainNavItem(
            icon: Icons.map_rounded,
            label: AppCopy.driverTabMap,
          ),
          CaptainNavItem(
            icon: Icons.event_available_rounded,
            label: AppCopy.driverTabAttendance,
            blink: true,
          ),
          CaptainNavItem(
            icon: Icons.person_outline_rounded,
            label: AppCopy.driverTabProfile,
          ),
        ],
      ),
    );
  }

  Future<void> _loadAssignmentsForDriver() async {
    setState(() {
      _loadingCustomers = true;
      _loadingAssignments = true;
      _loadingTrip = true;
      _customerError = null;
      _assignmentError = null;
      _tripError = null;
    });

    try {
      final authState = context.read<AuthBloc>().state;
      if (authState is! AuthStateAuthenticated) {
        setState(() {
          _loadingCustomers = false;
          _loadingAssignments = false;
          _loadingTrip = false;
          _customerError = 'User not authenticated';
          _assignmentError = 'User not authenticated';
          _tripError = 'User not authenticated';
        });
        return;
      }

      final today = DateTime.now();

      // Active trip comes from the CENTRALIZED single-trip endpoint
      // (/operator-mobile/my-trip-today/), exactly like the operator app. The
      // backend resolves it against the staff template, so the operator and the
      // driver on the same template get the same DailyTripAssignment — and the
      // same collection-point rows, so collection progress is shared instantly.
      // A driver can hold more than one trip today (e.g. a bin trip AND a
      // household trip); fetch them all for the header carousel. The primary
      // trip (drives the map + collection points below) is the first one that
      // actually has collection points, else simply the first.
      List<OperatorTripToday> todayTrips;
      try {
        todayTrips = await _tripRepository.fetchMyTripsToday();
      } on OperatorTripException catch (e) {
        // "No trip assigned today" is a normal empty state, not a failure.
        if (e.code != 'NO_ACTIVE_TRIP') rethrow;
        todayTrips = const [];
      }
      OperatorTripToday? todayTrip;
      for (final t in todayTrips) {
        if (t.collectionPoints.isNotEmpty) {
          todayTrip = t;
          break;
        }
      }
      todayTrip ??= todayTrips.isNotEmpty ? todayTrips.first : null;

      // Re-sequence the primary bin trip's collection points into a driver-first
      // route order (nearest = 1) and renumber them. This ordering is the SINGLE
      // source of truth read by both the home collection-point list and the map
      // markers, so a stop's number is identical on both screens. Household
      // trips keep their backend sequence.
      if (todayTrip != null &&
          !todayTrip.isHousehold &&
          todayTrip.collectionPoints.isNotEmpty) {
        final anchor = _staticLocationNear([
          for (final cp in todayTrip.collectionPoints)
            if (cp.collectionPoint.latitude != null &&
                cp.collectionPoint.longitude != null)
              LatLng(
                  cp.collectionPoint.latitude!, cp.collectionPoint.longitude!),
        ]);
        final reordered =
            _routeOrderedCollectionPoints(anchor, todayTrip.collectionPoints);
        final reorderedTrip = todayTrip.withCollectionPoints(reordered);
        todayTrips = [
          for (final t in todayTrips)
            identical(t, todayTrip) ? reorderedTrip : t,
        ];
        todayTrip = reorderedTrip;
      }

      // History list (completed / cancelled past trips) is still backed by
      // trip-history, but it no longer decides the active trip or feeds the
      // header carousel.
      final history = await _tripRepository.fetchHistory(
        from: today.subtract(const Duration(days: 45)),
        to: today.add(const Duration(days: 1)),
      );
      final activeAssignmentId = todayTrip?.assignmentUniqueId;
      final historyAssignments = history
          .where((trip) => trip.assignmentUniqueId != activeAssignmentId)
          .toList();

      // The header carousel surfaces only the driver's single active trip.
      final detail = todayTrip?.toHistoryDetail();
      final activeTrip = todayTrip?.toHistorySummary();
      final currentAssignments = <OperatorTripHistorySummary>[
        if (activeTrip != null) activeTrip,
      ];

      // The Map tab defaults to the primary (bin) trip. Build its stops via the
      // shared per-trip helper so a household trip renders its customers.
      final mapTrip = todayTrip;
      final (stops, tripStops) = _buildMapStopsForTrip(mapTrip);

      setState(() {
        _customers = stops;
        _tripStops = tripStops;
        _tripPolyline = const [];
        _todayTrips = todayTrips;
        _todayTrip = todayTrip;
        _mapTrip = mapTrip;
        _activeTripId = activeTrip?.assignmentUniqueId;
        _activeRoutePlanId = detail?.summary.tripPlan?.uniqueId;
        _activeVehicleType = null;
        _activeTripDetail = detail;
        _staticDriverLocation = _staticLocationNearStops(tripStops);
        _currentAssignments = currentAssignments;
        _historyAssignments = historyAssignments;
        _loadingCustomers = false;
        _loadingAssignments = false;
        _loadingTrip = false;
        _customerError = null;
        _assignmentError = null;
        _tripError = null;
      });
      _applyCollectionModeState(CollectionModeStore.mode.value);
    } catch (e) {
      setState(() {
        _loadingCustomers = false;
        _loadingAssignments = false;
        _loadingTrip = false;
        _customerError = 'Failed to load assignments';
        _assignmentError = 'Failed to load assignments';
        _tripError = _tripError ?? 'Failed to load trip route';
      });
    }
  }

  /// Build the Map tab's stop lists for [trip].
  ///
  /// A household/bulk trip has no bins: each assigned household becomes a map
  /// "customer" pin, and [_computeRoute] turns those into an optimised
  /// multi-stop route from the driver. There are no numbered bin trip-stops.
  /// A bin trip keeps the collection-point behaviour (each point is both a
  /// customer pin and a numbered [_TripPlannedStop]).
  (List<_DriverAssignmentStop>, List<_TripPlannedStop>) _buildMapStopsForTrip(
      OperatorTripToday? trip) {
    final stops = <_DriverAssignmentStop>[];
    final tripStops = <_TripPlannedStop>[];
    if (trip == null) return (stops, tripStops);

    final detail = trip.toHistoryDetail();

    if (trip.isHousehold) {
      final households = [...trip.householdCollections]
        ..sort((a, b) => a.sequence.compareTo(b.sequence));
      for (final h in households) {
        final lat = h.latitude;
        final lng = h.longitude;
        if (lat == null || lng == null) continue;
        stops.add(
          _DriverAssignmentStop(
            assignmentId: h.uniqueId,
            wardId: null,
            wardName: (h.address != null && h.address!.trim().isNotEmpty)
                ? h.address!
                : detail.summary.areaName,
            customerName: h.customerName,
            assignmentType: 'household_collection',
            shift: detail.summary.scheduledTime ?? 'scheduled',
            location: LatLng(lat, lng),
            sequence: h.sequence,
            status: h.isCollected
                ? _CustomerStatus.collected
                : _CustomerStatus.pending,
          ),
        );
      }
      return (stops, tripStops);
    }

    for (final cp in detail.collectionPoints) {
      final lat = cp.collectionPoint.latitude;
      final lng = cp.collectionPoint.longitude;
      if (lat == null || lng == null) continue;
      final seq = cp.sequence > 0 ? cp.sequence : tripStops.length + 1;
      stops.add(
        _DriverAssignmentStop(
          assignmentId: cp.uniqueId,
          wardId: detail.summary.ward?.uniqueId ??
              detail.summary.panchayat?.uniqueId,
          wardName: detail.summary.areaName,
          customerName: cp.collectionPoint.name,
          assignmentType: detail.summary.wasteType.name,
          shift: detail.summary.scheduledTime ?? 'scheduled',
          location: LatLng(lat, lng),
          sequence: seq,
          status: cp.isCollected
              ? _CustomerStatus.collected
              : _CustomerStatus.pending,
        ),
      );
      tripStops.add(
        _TripPlannedStop(
          plannedStopId: cp.uniqueId,
          sequence: seq,
          location: LatLng(lat, lng),
          collectionPointId: cp.collectionPoint.uniqueId,
          propertyType: cp.status,
          isCollected: cp.isCollected,
        ),
      );
    }
    // Route order is the single source of truth: keep both lists in sequence.
    stops.sort((a, b) => a.sequence.compareTo(b.sequence));
    tripStops.sort((a, b) => a.sequence.compareTo(b.sequence));
    return (stops, tripStops);
  }

  /// Switch the Map tab to show [trip] (bin or household) and open it. Called
  /// when a carousel card is tapped so the correct trip's stops are plotted.
  void _openMapForTrip(OperatorTripToday trip) {
    final (stops, tripStops) = _buildMapStopsForTrip(trip);
    final detail = trip.toHistoryDetail();
    setState(() {
      _todayTrip = trip;
      _mapTrip = trip;
      _customers = stops;
      _tripStops = tripStops;
      _tripPolyline = const [];
      _activeTripId = trip.assignmentUniqueId;
      _activeRoutePlanId = detail.summary.tripPlan?.uniqueId;
      _activeTripDetail = detail;
      _staticDriverLocation = _anchorForVisibleTripStops(stops, tripStops);
      _currentAssignments = [trip.toHistorySummary()];
      _activeTab = _DriverTab.map;
    });
  }

  LatLng _staticLocationNearStops(List<_TripPlannedStop> stops) =>
      _staticLocationNear([for (final s in stops) s.location]);

  /// A synthetic driver start near a cluster of [points] (offset to the SW of
  /// their bounding box). Used both to place the driver marker and as the
  /// anchor for the route-order re-sequence, so the two agree.
  LatLng _staticLocationNear(List<LatLng> points) {
    if (points.isEmpty) return GammaGeofenceConfig.center;

    var minLat = points.first.latitude;
    var maxLat = minLat;
    var minLng = points.first.longitude;
    var maxLng = minLng;
    for (final point in points) {
      minLat = min(minLat, point.latitude);
      maxLat = max(maxLat, point.latitude);
      minLng = min(minLng, point.longitude);
      maxLng = max(maxLng, point.longitude);
    }

    final centerLat = (minLat + maxLat) / 2;
    final centerLng = (minLng + maxLng) / 2;
    final latOffset = max(0.003, (maxLat - minLat) * 0.18);
    final lngOffset = max(0.003, (maxLng - minLng) * 0.18);
    return LatLng(centerLat - latOffset, centerLng - lngOffset);
  }

  /// Re-order a bin trip's collection points into a driver-first visiting order
  /// (greedy nearest-neighbour from [anchor]) and renumber them 1..N. This is
  /// the SINGLE source of truth for stop numbering: both the home collection-
  /// point list and the map markers consume this order, so "Stop 1" is the same
  /// place on both. Points without coordinates keep their relative order at the
  /// end. Already-collected points keep their route number.
  List<OperatorTripCollectionPoint> _routeOrderedCollectionPoints(
      LatLng anchor, List<OperatorTripCollectionPoint> points) {
    final located = <(OperatorTripCollectionPoint, LatLng)>[];
    final unlocated = <OperatorTripCollectionPoint>[];
    for (final p in points) {
      final lat = p.collectionPoint.latitude;
      final lng = p.collectionPoint.longitude;
      if (lat == null || lng == null) {
        unlocated.add(p);
      } else {
        located.add((p, LatLng(lat, lng)));
      }
    }

    const distance = Distance();
    final ordered = <OperatorTripCollectionPoint>[];
    var cursor = anchor;
    final remaining = [...located];
    while (remaining.isNotEmpty) {
      var bestIdx = 0;
      var bestDist = distance(cursor, remaining.first.$2);
      for (var i = 1; i < remaining.length; i++) {
        final d = distance(cursor, remaining[i].$2);
        if (d < bestDist) {
          bestDist = d;
          bestIdx = i;
        }
      }
      final chosen = remaining.removeAt(bestIdx);
      ordered.add(chosen.$1);
      cursor = chosen.$2;
    }
    ordered.addAll(unlocated);

    return [
      for (var i = 0; i < ordered.length; i++)
        ordered[i].copyWith(sequence: i + 1),
    ];
  }

  // List<_DriverAssignmentStop> _decodeCustomerList(String body,
  //     {bool fromAssignments = false}) {
  //   final List<_DriverAssignmentStop> out = [];

  //   try {
  //     final decoded = jsonDecode(body);
  //     final list = decoded is List
  //         ? decoded
  //         : (decoded is Map && decoded['results'] is List
  //             ? decoded['results']
  //             : []);

  //     if (list is! List) return out;

  //     for (final entry in list) {
  //       if (entry is! Map) continue;
  //       final map = Map<String, dynamic>.from(entry);

  //       final id = (map['unique_id'] ?? map['customer_id'] ?? '').toString();
  //       if (id.trim().isEmpty) continue;

  //       final latRaw =
  //           fromAssignments ? map['customer_latitude'] : map['latitude'];
  //       final lonRaw =
  //           fromAssignments ? map['customer_longitude'] : map['longitude'];

  //       final position = _safeLatLng(latRaw, lonRaw);
  //       if (position == null) continue;

  //       final name = (map['customer_name'] ??
  //               map['ward_name'] ??
  //               map['driver_name'] ??
  //               'Unknown')
  //           .toString();

  //       final addressParts = [
  //         map['building_no'],
  //         map['street'],
  //         map['area'],
  //         map['pincode'],
  //       ].whereType<String>().where((v) => v.trim().isNotEmpty).toList();

  //       out.add(_DriverAssignmentStop(
  //         assignmentId: id,
  //         wardName: name,
  //         assignmentType: 'primary',
  //         shift: 'morning',
  //         location: position,
  //       ));
  //     }
  //   } catch (_) {}

  //   return out;
  // }

  Widget _buildTab(_DriverTab tab, LatLng driverLocation, String nameFromState,
      String empIdFromState, VehicleModel? vehicle) {
    switch (tab) {
      case _DriverTab.home:
        return CaptainHomeTab(
          trips: _visibleTodayTrips,
          loading: _loadingTrip,
          error: _tripError,
          onRefresh: _loadAssignmentsForDriver,
          onOpenMap: _openMapForTrip,
          onScan: _openScanner,
          onOpenTrips: _openTripsPage,
          driverName: nameFromState,
        );
      case _DriverTab.map:
        return _HomeTab(
          mapController: _mapController,
          driverLocation: driverLocation,
          onCenter: () => _centerOnDriver(driverLocation),
          customers: _customers,
          currentAssignments: _currentAssignments,
          activeTripDetail: _activeTripDetail,
          tripStops: _tripStops,
          tripPolyline: _tripPolyline,
          // A household trip has no server-computed bin route; the map builds an
          // optimised multi-stop route from the customer stops via ORS instead.
          activeRouteGeojson:
              (_mapTrip?.isHousehold ?? false) ? null : _mapTrip?.routeGeojson,
          activeTripId: _mapTrip?.assignmentUniqueId ?? _activeTripId,
          activeRoutePlanId: _activeRoutePlanId,
          activeVehicleType: _activeVehicleType,
          tripLoading: _loadingTrip,
          tripError: _tripError,
          loading: _loadingCustomers,
          error: _customerError,
          onRefresh: _loadAssignmentsForDriver,
          onStatusChanged: _updateCustomerStatus,
        );
      case _DriverTab.attendance:
        return AttendancePageDriver(
          driverName: nameFromState,
          driverCode: empIdFromState,
        );
      case _DriverTab.profile:
        return _ProfileTab(
          onLogout: () => _logout(context),
          driverName: nameFromState,
          empId: empIdFromState,
          tripVehicle: _resolveProfileTripVehicle(),
        );
    }
  }

  OperatorTripVehicle? _resolveProfileTripVehicle() {
    final activeVehicle = _todayTrip?.vehicle;
    if (activeVehicle != null) return activeVehicle;
    for (final trip in _todayTrips) {
      final tripVehicle = trip.vehicle;
      if (tripVehicle != null) return tripVehicle;
    }
    return null;
  }

  _DriverTab _tabFromIndex(int index) {
    switch (index) {
      case 1:
        return _DriverTab.map;
      case 2:
        return _DriverTab.attendance;
      case 3:
        return _DriverTab.profile;
      case 0:
      default:
        return _DriverTab.home;
    }
  }

  /// Full trips view (current + history tabs), preserved from the old
  /// Assignments tab and now pushed from the Home dashboard.
  void _openTripsPage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        // The trips view keeps the operator module's light styling (dark
        // text), so it needs a light scaffold — not the Captain black.
        builder: (_) => Scaffold(
          backgroundColor: OperatorTheme.background,
          appBar: AppBar(
            title: const Text('My Trips'),
            backgroundColor: CaptainTheme.primary,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          body: _AssignmentsTab(
            currentAssignments: _currentAssignments,
            historyAssignments: _historyAssignments,
            activeTripDetail: _activeTripDetail,
            loading: _loadingAssignments,
            error: _assignmentError,
            onRefresh: _loadAssignmentsForDriver,
          ),
        ),
      ),
    );
  }

  /// Centre Scan FAB → choose between the two collection flows the vehicle
  /// crew performs (both inherited from the operator app):
  ///   • Bin QR — validate a bin against today's trip, then weight entry.
  ///   • Household — scan a customer QR, then wet/dry/mixed weighment.
  ///
  /// The global Household/Bin toggle owns this choice now, so the FAB opens
  /// only the currently-selected flow instead of asking again.
  Future<void> _openScanner() async {
    // The floating scan button is reachable from anywhere, including while a
    // locked trip is the selected card. Scanning it would come back from the
    // backend as TRIP_LOCKED, so say so here instead of opening the camera.
    final blocker = _blockerForSelectedTrip();
    if (blocker != null) {
      AppFlash.warning(context, blocker.message);
      return;
    }

    if (CollectionModeStore.mode.value == CollectionMode.bin) {
      final result = await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const OperatorTripScanScreen()),
      );
      if (!mounted) return;
      if (result != null) await _loadAssignmentsForDriver();
    } else {
      final householdAssignmentId =
          (_todayTrip != null && _todayTrip!.isHousehold)
              ? _todayTrip!.assignmentUniqueId
              : null;
      final householdStatuses = <String, String>{
        if (_todayTrip != null && _todayTrip!.isHousehold)
          for (final stop in _todayTrip!.householdCollections)
            stop.customerUniqueId: stop.isCollected ? 'collected' : stop.status,
      };
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OperatorQRScanner(
            expectedAssignmentId: householdAssignmentId,
            knownAssignmentStatuses: householdStatuses,
          ),
        ),
      );
      if (!mounted) return;
      await _loadAssignmentsForDriver();
    }
  }

  void _logout(BuildContext context) {
    if (!mounted) return;
    context.read<AuthBloc>().add(AuthLogoutRequested());
  }

  void _updateCustomerStatus(String id, _CustomerStatus status) {
    setState(() {
      for (final c in _customers) {
        if (c.assignmentId == id) {
          c.status = status;
        }
      }
    });
  }
}

/// One option row in the Scan chooser sheet — big tap target, icon plate,
/// title + one-line explanation.
class _ScanChoiceTile extends StatelessWidget {
  const _ScanChoiceTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.28)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: CaptainTheme.strongText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: CaptainTheme.mutedText,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// PART 3: HomeTab Widget with Map and Navigation
// ============================================================
class _HomeTab extends StatefulWidget {
  const _HomeTab({
    required this.mapController,
    required this.driverLocation,
    required this.onCenter,
    required this.customers, // ✅ DECLARED
    required this.currentAssignments,
    required this.activeTripDetail,
    required this.tripStops,
    required this.tripPolyline,
    required this.activeRouteGeojson,
    required this.activeTripId,
    required this.activeRoutePlanId,
    required this.activeVehicleType,
    required this.tripLoading,
    required this.tripError,
    required this.loading,
    required this.error,
    required this.onRefresh,
    required this.onStatusChanged,
  });

  final MapController mapController;
  final LatLng driverLocation;
  final VoidCallback onCenter;
  final List<_DriverAssignmentStop> customers; // ✅ ADD THIS
  final List<OperatorTripHistorySummary> currentAssignments;
  final OperatorTripHistoryDetail? activeTripDetail;
  final List<_TripPlannedStop> tripStops;
  final List<LatLng> tripPolyline;
  final Object? activeRouteGeojson;
  final String? activeTripId;
  final String? activeRoutePlanId;
  final String? activeVehicleType;
  final bool tripLoading;
  final String? tripError;
  final bool loading;
  final String? error;
  final Future<void> Function() onRefresh;
  final void Function(String id, _CustomerStatus status) onStatusChanged;

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> with TickerProviderStateMixin {
  static const EdgeInsets _overviewFitPadding =
      EdgeInsets.fromLTRB(46, 238, 46, 252);

  List<LatLng> _orsRoute = [];
  List<LatLng> _tripPolyline = [];
  // Overview route split into two visual states:
  //  • _activeLeg   — driver → the immediate next pending stop (solid, blue).
  //  • _upcomingLeg — that stop → the remaining stops (dotted, grey).
  // The active leg advances as the driver collects / defers / skips a stop.
  List<LatLng> _activeLeg = [];
  List<LatLng> _upcomingLeg = [];
  MapStyle _mapStyle = kDefaultMapStyle;
  double _driverBearing = 0.0;
  List<_DriverAssignmentStop> _customers = [];
  List<_TripPlannedStop> _tripStops = [];
  _NavigationMode _navMode = _NavigationMode.overview;
  String? _activeNavigationId;
  late AnimationController _navAnimController;
  LatLng _driverLocation = GammaGeofenceConfig.center;
  bool _manualDriverOverride = false;
  bool _isDraggingDriver = false;
  Point<double>? _driverScreenPoint;
  String? _tripId;
  String? _routePlanId;
  String? _vehicleType;
  bool _rerouting = false;
  int _tripRouteRequestId = 0;
  List<String> _lastActualSequence = [];
  bool _autoRerouteDone = false;

  @override
  void initState() {
    super.initState();
    _driverLocation = _sanitizeDriverLocation(widget.driverLocation);
    _customers = widget.customers
        .where((c) =>
            c.status == _CustomerStatus.pending ||
            c.status == _CustomerStatus.later ||
            c.status == _CustomerStatus.navigating)
        .toList();
    _tripStops = widget.tripStops;
    _tripPolyline = _extractLineCoords(widget.activeRouteGeojson);
    _tripId = widget.activeTripId;
    _routePlanId = widget.activeRoutePlanId;
    _vehicleType = widget.activeVehicleType;
    _lastActualSequence = _tripStops
        .map((stop) => stop.plannedStopId)
        .where((id) => id.isNotEmpty)
        .toList();
    _navAnimController = AnimationController(
      vsync: this,
      duration: _kNavigationTransitionDuration,
    );
    // Restore the driver's saved map style (defaults to light).
    MapStylePrefs.load().then((style) {
      if (mounted) setState(() => _mapStyle = style);
    });
    _computeRoute();
    _computeTripRoadRoute();
    _computeLegs();
    _maybeAutoReroute();
    // Frame the active leg (driver → next stop) as soon as the map is laid out,
    // so the first thing the driver sees is a clear driver-to-next-stop view
    // even before the road route resolves.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitActiveLeg();
    });
  }

  LatLng _sanitizeDriverLocation(LatLng location) {
    return location;
  }

  @override
  void dispose() {
    _navAnimController.dispose();
    super.dispose();
  }

  void _updateCustomerStatus(String id, _CustomerStatus status) {
    final isDone = status == _CustomerStatus.collected ||
        status == _CustomerStatus.skipped;
    final shouldExitNavigation =
        _navMode == _NavigationMode.navigating && _activeNavigationId == id;

    setState(() {
      if (isDone) {
        _customers.removeWhere((c) => c.id == id);
        if (shouldExitNavigation) {
          _activeNavigationId = null;
          _navMode = _NavigationMode.overview;
        }
      } else {
        for (final c in _customers) {
          if (c.id == id) {
            c.status = status;
          }
        }
      }
    });

    if (shouldExitNavigation) {
      _navAnimController.reverse();
      _animateToOverview();
    }
    // The active stop was handled (collected / deferred / skipped) — advance the
    // active leg to the next pending stop and re-frame.
    _computeLegs();
    widget.onStatusChanged(id, status);
  }

  @override
  void didUpdateWidget(covariant _HomeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final customersChanged = oldWidget.customers != widget.customers;
    final driverChanged = oldWidget.driverLocation != widget.driverLocation;
    final tripChanged = oldWidget.tripStops != widget.tripStops ||
        oldWidget.tripPolyline != widget.tripPolyline ||
        oldWidget.activeRouteGeojson != widget.activeRouteGeojson ||
        oldWidget.activeTripId != widget.activeTripId ||
        oldWidget.activeRoutePlanId != widget.activeRoutePlanId;

    if (driverChanged && !_manualDriverOverride && !_isDraggingDriver) {
      _driverLocation = _sanitizeDriverLocation(widget.driverLocation);
    }

    if (customersChanged) {
      _customers = widget.customers
          .where((c) =>
              c.status == _CustomerStatus.pending ||
              c.status == _CustomerStatus.later ||
              c.status == _CustomerStatus.navigating)
          .toList();
    }

    if (tripChanged) {
      _tripStops = widget.tripStops;
      _tripPolyline = _extractLineCoords(widget.activeRouteGeojson);
      _tripId = widget.activeTripId;
      _routePlanId = widget.activeRoutePlanId;
      _vehicleType = widget.activeVehicleType;
      _autoRerouteDone = false;
      _lastActualSequence = _tripStops
          .map((stop) => stop.plannedStopId)
          .where((id) => id.isNotEmpty)
          .toList();
    }

    if (customersChanged || driverChanged) {
      _computeRoute();
      _computeLegs();
    }

    if (tripChanged || driverChanged) {
      _computeTripRoadRoute();
    }

    if (tripChanged && !_autoRerouteDone) {
      _maybeAutoReroute();
    }
  }

  Future<void> _computeRoute() async {
    if (_customers.isEmpty) {
      if (!mounted) return;
      setState(() {
        _orsRoute = [];
        _driverBearing = 0.0;
      });
      return;
    }

    final List<List<double>> coords = [
      [_driverLocation.longitude, _driverLocation.latitude],
      ..._customers.map((c) => [c.location.longitude, c.location.latitude]),
    ];

    try {
      final route = await ORSService.fetchMultiRoute(coords);

      if (!mounted) return;

      setState(() {
        _orsRoute = route;

        if (route.length > 1) {
          _driverBearing = ORSService.calculateBearing(route.first, route[1]);
        } else {
          _driverBearing = 0.0;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _orsRoute = [];
        _driverBearing = 0.0;
      });
    }
  }

  /// The ordered list of stops still to visit, in route order. Stops marked
  /// "collect later" are deferred to the end so the active leg advances to the
  /// next collectable stop.
  List<_DriverAssignmentStop> _pendingRouteStops() => [
        ..._customers.where((c) => c.status != _CustomerStatus.later),
        ..._customers.where((c) => c.status == _CustomerStatus.later),
      ];

  /// Split the overview route into an active leg (driver → immediate next stop)
  /// and the upcoming legs (that stop → the rest). The active leg is drawn
  /// solid; the upcoming legs are drawn dotted/grey until the driver collects,
  /// defers, or skips the current stop — at which point this recomputes and the
  /// next stop's leg becomes active.
  Future<void> _computeLegs() async {
    final pending = _pendingRouteStops();
    if (pending.isEmpty) {
      if (!mounted) return;
      setState(() {
        _activeLeg = [];
        _upcomingLeg = [];
      });
      return;
    }

    final next = pending.first;
    List<LatLng> active;
    try {
      active = await ORSService.fetchRoadRoute(
        driver: _driverLocation,
        stops: [next.location],
      );
    } catch (_) {
      active = [];
    }
    if (active.isEmpty) active = [_driverLocation, next.location];

    List<LatLng> upcoming = [];
    final rest = pending.skip(1).map((c) => c.location).toList();
    if (rest.isNotEmpty) {
      try {
        upcoming = await ORSService.fetchRoadRoute(
          driver: next.location,
          stops: rest,
        );
      } catch (_) {
        upcoming = [next.location, ...rest];
      }
      if (upcoming.isEmpty) upcoming = [next.location, ...rest];
    }

    if (!mounted) return;
    setState(() {
      _activeLeg = active;
      _upcomingLeg = upcoming;
    });

    if (_navMode == _NavigationMode.overview) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitActiveLeg();
      });
    }
  }

  /// Frame the map so the whole active leg (driver → immediate next stop) fills
  /// the view. Falls back to driver + nearest stop if the leg isn't ready.
  void _fitActiveLeg() {
    final points = <LatLng>[_driverLocation, ..._activeLeg];
    if (points.length < 2) {
      _fitDriverAndNearestStop();
      return;
    }
    widget.mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: _overviewFitPadding,
      ),
    );
  }

  /// The stop (household customer or bin collection point) closest to the
  /// driver — used to frame the map on open.
  LatLng? _nearestStopLocation() {
    final points = <LatLng>[
      ..._customers.map((c) => c.location),
      ..._tripStops.map((s) => s.location),
    ];
    if (points.isEmpty) return null;
    const distance = Distance();
    var nearest = points.first;
    var best = distance(_driverLocation, nearest);
    for (final p in points.skip(1)) {
      final d = distance(_driverLocation, p);
      if (d < best) {
        best = d;
        nearest = p;
      }
    }
    return nearest;
  }

  /// Frame the map so the driver and their NEAREST stop are both clearly in
  /// view (instead of zooming out to fit every stop). This is the view the
  /// driver sees when they open the map.
  void _fitDriverAndNearestStop() {
    final nearest = _nearestStopLocation();
    if (nearest == null) {
      widget.mapController.move(_driverLocation, 15.0);
      return;
    }
    final bounds = LatLngBounds.fromPoints([_driverLocation, nearest]);
    widget.mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: _overviewFitPadding,
      ),
    );
  }

  void _fitDriverAndNextCustomer() {
    if (_customers.isEmpty) return;

    final bounds = LatLngBounds.fromPoints([
      _driverLocation,
      ..._customers.map((customer) => customer.location),
    ]);

    widget.mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: _overviewFitPadding,
      ),
    );
  }

  void _fitTripRoute() {
    if (_tripStops.isEmpty) return;
    final bounds = LatLngBounds.fromPoints([
      _driverLocation,
      ..._tripStops.map((stop) => stop.location),
    ]);

    widget.mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: _overviewFitPadding,
      ),
    );
  }

  void _startNavigation(String customerId) {
    final customer = _customers.firstWhere((c) => c.id == customerId);

    setState(() {
      _activeNavigationId = customerId;
      _navMode = _NavigationMode.navigating;
      customer.status = _CustomerStatus.navigating;
    });

    widget.onStatusChanged(customerId, _CustomerStatus.navigating);
    _navAnimController.forward();
    _animateToNavigationView();
  }

  void _stopNavigation() {
    setState(() {
      if (_activeNavigationId != null) {
        final customer =
            _customers.firstWhere((c) => c.id == _activeNavigationId);
        customer.status = _CustomerStatus.pending;
        widget.onStatusChanged(_activeNavigationId!, _CustomerStatus.pending);
      }
      _activeNavigationId = null;
      _navMode = _NavigationMode.overview;
    });

    _navAnimController.reverse();
    _animateToOverview();
  }

  void _recenterNavigation() {
    if (_navMode == _NavigationMode.navigating) {
      _animateToNavigationView();
    } else if (_customers.isEmpty && _tripStops.isNotEmpty) {
      _fitTripRoute();
    } else {
      _fitDriverAndNextCustomer();
    }
  }

  void _animateToNavigationView() {
    if (_orsRoute.isEmpty) return;

    // Position driver at bottom third of screen, facing up
    final driverPos = _orsRoute.first;

    // Calculate offset to position driver marker at bottom third
    final offsetLat = 0.003; // Adjust this value based on zoom level

    final targetCenter = LatLng(
      driverPos.latitude + offsetLat,
      driverPos.longitude,
    );

    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      widget.mapController.move(targetCenter, 17.5);
      widget.mapController.rotate(0); // North-up orientation
    });
  }

  void _animateToOverview() {
    if (_customers.isEmpty) {
      if (_tripStops.isNotEmpty) {
        _fitTripRoute();
      } else {
        widget.mapController.move(_driverLocation, 15.0);
        widget.mapController.rotate(0);
      }
      return;
    }

    final allPoints = [
      _driverLocation,
      ..._customers.map((c) => c.location),
    ];

    final bounds = LatLngBounds.fromPoints(allPoints);

    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      widget.mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: _overviewFitPadding,
        ),
      );
      widget.mapController.rotate(0);
    });
  }

  void _centerOnDriver() {
    if (_manualDriverOverride) {
      widget.mapController.move(_driverLocation, 15.0);
    } else {
      widget.onCenter();
    }
  }

  void _zoomBy(double delta) {
    final camera = widget.mapController.camera;
    final next = (camera.zoom + delta).clamp(10.0, 18.0);
    widget.mapController.move(camera.center, next);
  }

  void _startDriverDrag(DragStartDetails details) {
    _isDraggingDriver = true;
    _driverScreenPoint =
        widget.mapController.camera.latLngToScreenPoint(_driverLocation);
  }

  void _updateDriverDrag(DragUpdateDetails details) {
    if (_driverScreenPoint == null) return;
    final nextPoint = Point<double>(
      _driverScreenPoint!.x + details.delta.dx,
      _driverScreenPoint!.y + details.delta.dy,
    );
    final nextLocation = widget.mapController.camera.pointToLatLng(nextPoint);
    setState(() {
      _manualDriverOverride = true;
      _driverLocation = nextLocation;
    });
    _driverScreenPoint = nextPoint;
  }

  void _endDriverDrag(DragEndDetails details) {
    _isDraggingDriver = false;
    _driverScreenPoint = null;
    _computeRoute();
    _rerouteTripFromDriver();
  }

  void _resetDriverLocation() {
    setState(() {
      _manualDriverOverride = false;
      _driverLocation = _sanitizeDriverLocation(widget.driverLocation);
    });
    _computeRoute();
  }

  void _maybeAutoReroute() {
    if (_autoRerouteDone) return;
    if (widget.tripLoading || widget.tripError != null) return;
    if (_tripStops.length < 2) return;
    if (_vehicleType == null || _vehicleType!.trim().isEmpty) return;
    if (_tripId == null || _tripId!.isEmpty) return;

    _autoRerouteDone = true;
    _rerouteTripFromDriver();
  }

  bool _isSameSequence(List<String> next, List<String> previous) {
    if (next.length != previous.length) return false;
    for (var i = 0; i < next.length; i++) {
      if (next[i] != previous[i]) return false;
    }
    return true;
  }

  Future<void> _postActualSequence(
    String tripId,
    List<_TripPlannedStop> stops,
  ) async {
    final ordered =
        stops.where((stop) => stop.plannedStopId.isNotEmpty).toList();
    if (ordered.isEmpty) return;

    final dio = await authorizedDio();
    for (var i = 0; i < ordered.length; i++) {
      final stop = ordered[i];
      await dio.post(
        ApiConfig.tripExecutionStops,
        data: {
          'trip_id': tripId,
          'planned_route_stop_id': stop.plannedStopId,
          'actual_sequence_number': i + 1,
          'gps_lat': _driverLocation.latitude,
          'gps_lng': _driverLocation.longitude,
        },
      );
    }
  }

  Future<void> _computeTripRoadRoute({bool force = false}) async {
    if (_tripStops.isEmpty) return;

    final needsRoad =
        _tripPolyline.isEmpty || _tripPolyline.length <= _tripStops.length + 1;
    if (!force && !needsRoad) return;

    final requestId = ++_tripRouteRequestId;

    // Prefer the active-trip payload's server-computed ORS geometry. It is
    // scoped to this driver and avoids loading the heavy all-trip overview.
    var route = _extractLineCoords(widget.activeRouteGeojson);

    // Fallback: direct ORS from the device. If this also fails, keep the route
    // empty instead of drawing a misleading straight line between stops.
    if (route.isEmpty) {
      route = await ORSService.fetchRoadRoute(
        driver: _driverLocation,
        stops: _tripStops.map((s) => s.location).toList(),
      );
    }

    if (!mounted || requestId != _tripRouteRequestId) return;
    setState(() {
      _tripPolyline = route;
    });
  }

  /// GeoJSON coords are [lng, lat]; handles LineString, Feature and
  /// FeatureCollection shapes.
  List<LatLng> _extractLineCoords(dynamic geojson) {
    double? toD(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');
    dynamic geometry = geojson;
    if (geojson is Map && geojson['type'] == 'FeatureCollection') {
      final features = geojson['features'];
      if (features is List && features.isNotEmpty && features.first is Map) {
        geometry = (features.first as Map)['geometry'];
      }
    } else if (geojson is Map && geojson['type'] == 'Feature') {
      geometry = geojson['geometry'];
    }
    if (geometry is! Map) return const [];
    final coords = geometry['coordinates'];
    final out = <LatLng>[];
    if (coords is List) {
      for (final c in coords) {
        if (c is List && c.length >= 2) {
          final lng = toD(c[0]);
          final lat = toD(c[1]);
          if (lat != null && lng != null) out.add(LatLng(lat, lng));
        }
      }
    }
    return out;
  }

  Future<void> _rerouteTripFromDriver() async {
    if (_rerouting) return;
    if (_tripStops.isEmpty) return;
    final tripId = _tripId;
    final vehicleType = _vehicleType;
    if (tripId == null || tripId.isEmpty) return;
    if (vehicleType == null || vehicleType.trim().isEmpty) return;

    final collectionPointIds = _tripStops
        .map((stop) => stop.collectionPointId)
        .where((id) => id.isNotEmpty)
        .toList();

    if (collectionPointIds.isEmpty) return;

    setState(() {
      _rerouting = true;
    });

    try {
      final dio = await authorizedDio();
      final payload = <String, dynamic>{
        'trip_id': tripId,
        'start_lat': _driverLocation.latitude,
        'start_lng': _driverLocation.longitude,
        'collection_point_ids': collectionPointIds,
        'vehicle_type': vehicleType,
        'generated_by': 'ORS',
        'generated_reason': 'MANUAL',
      };

      final parentRoutePlanId = _routePlanId;
      if (parentRoutePlanId != null && parentRoutePlanId.isNotEmpty) {
        payload['parent_route_plan_id'] = parentRoutePlanId;
      }

      final resp =
          await dio.post(ApiConfig.tripRoutePlanGenerate, data: payload);
      final data = resp.data;

      final plan = data is Map ? data['route_plan'] : null;
      final plannedStops = data is Map && data['planned_stops'] is List
          ? data['planned_stops'] as List
          : const [];

      final stops = <_TripPlannedStop>[];
      for (final item in plannedStops) {
        if (item is! Map) continue;
        final lat = double.tryParse(
          item['collection_point_latitude']?.toString() ?? '',
        );
        final lng = double.tryParse(
          item['collection_point_longitude']?.toString() ?? '',
        );
        if (lat == null || lng == null) continue;
        final seqRaw = item['planned_sequence_number'] ?? item['sequence'];
        final sequence = int.tryParse(seqRaw?.toString() ?? '') ?? 0;
        final plannedStopId = (item['unique_id'] ?? '').toString();
        final pointId = (item['collection_point_id'] ?? '').toString();
        final propertyType = (item['collection_point_type'] ?? '').toString();

        stops.add(
          _TripPlannedStop(
            plannedStopId: plannedStopId,
            sequence: sequence > 0 ? sequence : stops.length + 1,
            location: LatLng(lat, lng),
            collectionPointId: pointId,
            propertyType: propertyType,
          ),
        );
      }

      stops.sort((a, b) => a.sequence.compareTo(b.sequence));

      final geometry = data is Map && data['route_geometry'] is Map
          ? data['route_geometry'] as Map
          : null;
      final encoded = geometry?['encoded_polyline'];
      List<LatLng> polyline = [];
      if (encoded is String && encoded.trim().isNotEmpty) {
        polyline = ORSService.decodePolyline(encoded.trim());
      }
      if (polyline.isEmpty && stops.isNotEmpty) {
        polyline = stops.map((s) => s.location).toList();
      }

      if (!mounted) return;
      final newSequence = stops
          .map((stop) => stop.plannedStopId)
          .where((id) => id.isNotEmpty)
          .toList();
      final sequenceChanged = newSequence.isNotEmpty &&
          !_isSameSequence(newSequence, _lastActualSequence);

      setState(() {
        _tripStops = stops.isEmpty ? _tripStops : stops;
        _tripPolyline = polyline;
        _routePlanId =
            plan is Map ? plan['unique_id']?.toString() : _routePlanId;
        _rerouting = false;
      });

      if (sequenceChanged && tripId.isNotEmpty) {
        try {
          await _postActualSequence(tripId, stops);
          if (!mounted) return;
          setState(() {
            _lastActualSequence = newSequence;
          });
        } catch (_) {
          // Best effort only: route display should not fail when sequence logging
          // has a transient backend issue.
        }
      }

      if (stops.isNotEmpty) {
        _fitTripRoute();
      }
      await _computeTripRoadRoute(force: true);
    } on DioException catch (e) {
      final message = _extractDioMessage(e) ?? 'Reroute failed';
      if (!mounted) return;
      setState(() {
        _rerouting = false;
      });
      AppFlash.error(context, message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _rerouting = false;
      });
      AppFlash.error(context, 'Reroute failed');
    }
  }

  Future<void> _reportCompletion(_DriverAssignmentStop customer) async {
    if (!ApiConfig.legacyRoleAssignEnabled) return;

    final assignmentId = customer.baseAssignmentId;
    String? driverId;
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthStateAuthenticated) {
      final trimmed = authState.userId.trim();
      if (trimmed.isNotEmpty) {
        driverId = trimmed;
      }
    }
    final dio = await authorizedDio();

    try {
      await dio.post(
        '${ApiConfig.assignments}$assignmentId/complete/',
      );
    } on DioException catch (e) {
      final alreadyCompleted =
          await _verifyAssignmentCompletion(dio, assignmentId);
      if (alreadyCompleted) return;
      final message = _extractDioMessage(e) ?? 'Failed to sync completion';
      if (!mounted) return;
      AppFlash.error(context, message);
      return;
    } catch (_) {
      final alreadyCompleted =
          await _verifyAssignmentCompletion(dio, assignmentId);
      if (alreadyCompleted) return;
      if (!mounted) return;
      AppFlash.error(context, 'Failed to sync completion');
      return;
    }

    try {
      await dio.post(
        ApiConfig.collectionLogs,
        data: {
          'assignment': assignmentId,
          if (driverId != null) 'driver': driverId,
          'action': 'collection_completed',
          'latitude': _driverLocation.latitude,
          'longitude': _driverLocation.longitude,
        },
      );
    } catch (_) {
      // ignore log failures once completion succeeded
    }
  }

  String? _extractDioMessage(DioException error) {
    final data = error.response?.data;
    if (data is Map) {
      final detail = data['detail'] ?? data['reason'] ?? data['message'];
      if (detail != null) return detail.toString();
    }
    return null;
  }

  Future<bool> _verifyAssignmentCompletion(
    Dio dio,
    String assignmentId,
  ) async {
    if (!ApiConfig.legacyRoleAssignEnabled) return false;

    try {
      final resp = await dio.get('${ApiConfig.assignments}$assignmentId/');
      final data = resp.data;
      if (data is Map) {
        final status = data['current_status']?.toString().toLowerCase();
        return status == 'completed' ||
            status == 'skipped' ||
            status == 'cancelled';
      }
    } catch (_) {}
    return false;
  }

  Future<void> _handleCollect(_DriverAssignmentStop customer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm Collection'),
        content: const Text(
          'Have you completed waste collection for this customer?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      customer.status = _CustomerStatus.collected;
    });

    _updateCustomerStatus(customer.id, _CustomerStatus.collected);

    await _reportCompletion(customer);

    if (mounted) {
      AppFlash.success(context, 'Collection completed',
          duration: const Duration(seconds: 2));
    }

    await _computeRoute();
  }

  Future<void> _handleSkip(_DriverAssignmentStop customer) async {
    String? selectedReason;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Skip Waste Collection'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Select a reason for skipping:'),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedReason,
                    isExpanded: true,
                    dropdownColor: Colors.white,
                    decoration: const InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(),
                      hintText: 'Reason',
                    ),
                    items: _skipReasons
                        .map(
                          (r) => DropdownMenuItem(
                            value: r,
                            child: Text(
                              r,
                              style: const TextStyle(color: Colors.black),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      setStateDialog(() {
                        selectedReason = val;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: selectedReason == null
                      ? null
                      : () => Navigator.pop(dialogContext, true),
                  child: const Text('Skip'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true || selectedReason == null) return;

    setState(() {
      customer.status = _CustomerStatus.skipped;
      customer.skipReason = selectedReason;
    });

    _updateCustomerStatus(customer.id, _CustomerStatus.skipped);

    await _reportSkip(customer, selectedReason!);

    if (mounted) {
      AppFlash.info(context, 'Skipped', duration: const Duration(seconds: 2));
    }

    await _computeRoute();
  }

  void _handleLater(_DriverAssignmentStop customer) {
    setState(() {
      customer.status = _CustomerStatus.later;
    });

    _updateCustomerStatus(customer.id, _CustomerStatus.later);

    AppFlash.info(context, 'Marked for later',
        duration: const Duration(seconds: 2));
  }

  void _openAssignmentScreen(_DriverAssignmentStop customer) {
    final wardId = customer.wardId;
    final wardName = customer.wardName;

    if (wardId == null && wardName.isEmpty) {
      AppFlash.warning(context, 'Ward not available for this assignment');
      return;
    }

    final wardCustomers = _customers.where((c) {
      if (wardId != null && wardId.isNotEmpty) {
        return c.wardId == wardId;
      }
      return c.wardName == wardName;
    }).toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _AssignmentScreen(
          wardName: wardName,
          customers: wardCustomers,
          onCollect: _handleCollect,
          onLater: _handleLater,
          onSkip: _handleSkip,
        ),
      ),
    );
  }

  Future<void> _reportSkip(
    _DriverAssignmentStop customer,
    String reason,
  ) async {
    if (!ApiConfig.legacyRoleAssignEnabled) return;

    try {
      final dio = await authorizedDio();
      final assignmentId = customer.baseAssignmentId;

      await dio.post(
        '${ApiConfig.assignments}$assignmentId/skip/',
        data: {'reason': reason},
      );

      await dio.post(
        ApiConfig.collectionLogs,
        data: {
          'assignment': assignmentId,
          'action': 'skipped',
          'skip_reason': reason,
          'latitude': _driverLocation.latitude,
          'longitude': _driverLocation.longitude,
        },
      );
    } catch (e) {
      if (!mounted) return;
      AppFlash.error(context, 'Failed to sync skip');
    }
  }

  Color _statusColor(_CustomerStatus status) {
    switch (status) {
      case _CustomerStatus.collected:
        return CaptainTheme.success;
      case _CustomerStatus.later:
        return CaptainTheme.gold;
      case _CustomerStatus.skipped:
        return CaptainTheme.warning;
      case _CustomerStatus.navigating:
        return CaptainTheme.accent;
      case _CustomerStatus.pending:
        return CaptainTheme.danger;
    }
  }

  String _getDistanceToCustomer(_DriverAssignmentStop customer) {
    final distance = const Distance().as(
      LengthUnit.Meter,
      _driverLocation,
      customer.location,
    );

    if (distance < 1000) {
      return '${distance.round()} m';
    } else {
      return '${(distance / 1000).toStringAsFixed(1)} km';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNavigating = _navMode == _NavigationMode.navigating;
    _DriverAssignmentStop? activeCustomer;
    if (_activeNavigationId != null) {
      for (final c in _customers) {
        if (c.id == _activeNavigationId) {
          activeCustomer = c;
          break;
        }
      }
    }
    final navigationCustomer = isNavigating ? activeCustomer : null;
    // The next stop is the head of the route order (deferred "collect later"
    // stops go last), so the card matches the active leg's destination.
    final pendingStops = _pendingRouteStops();
    final nextCustomer =
        !isNavigating && pendingStops.isNotEmpty ? pendingStops.first : null;
    // Use the stop's shared route sequence so the card reads the same number as
    // the map marker and the home list (e.g. "Stop 3 of 8"). Fall back to the
    // list index if a sequence wasn't provided.
    final nextCustomerPosition = nextCustomer == null
        ? 0
        : (nextCustomer.sequence > 0
            ? nextCustomer.sequence - 1
            : _customers.indexWhere((c) => c.id == nextCustomer.id));
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final bottomOverlayOffset = kCaptainMapBottomOverlayOffset + bottomInset;
    // The map now carries ONLY the next-collection-point card (the daily
    // assignment carousel was removed to declutter the view); controls sit
    // just below it, or at the top when there's no next stop.
    final mapControlsTop =
        isNavigating ? 12.0 : (nextCustomer != null ? 118.0 : 12.0);
    final dark = CaptainThemeStore.isDark.value;

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: Stack(
        children: [
          // Map
          Positioned.fill(
            child: FlutterMap(
              mapController: widget.mapController,
              options: MapOptions(
                initialCenter: _driverLocation,
                initialZoom: 14.5,
                minZoom: 10,
                maxZoom: 18,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all,
                ),
              ),
              children: [
                // Base map honours the user's chosen style (Default / Light /
                // Dark / Satellite). Only for the Default style in the app's
                // dark theme do we run the light OSM raster through an
                // invert+hue matrix so it reads as a proper dark map instead of
                // glaring white on the black Captain canvas.
                _mapStyle == MapStyle.standard && dark
                    ? ColorFiltered(
                        colorFilter: const ColorFilter.matrix(_darkMapMatrix),
                        child: buildMapTileLayer(MapStyle.standard),
                      )
                    : buildMapTileLayer(_mapStyle),
                // NAVIGATING: keep the full solid active route (turn-by-turn).
                if (isNavigating && _orsRoute.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _orsRoute,
                        color: _kRouteCore,
                        borderColor: _kRouteCasing,
                        borderStrokeWidth: 3.5,
                        strokeWidth: 7.0,
                      ),
                    ],
                  ),
                // OVERVIEW: upcoming legs are drawn first (underneath) as a
                // dotted, greyed line — the driver isn't heading there yet.
                if (!isNavigating && _upcomingLeg.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _upcomingLeg,
                        color: _kRouteUpcoming,
                        strokeWidth: 4.0,
                        pattern: StrokePattern.dotted(
                          spacingFactor: 2.2,
                        ),
                      ),
                    ],
                  ),
                // OVERVIEW: the active leg (driver → immediate next stop) is the
                // solid, prominent blue line drawn on top.
                if (!isNavigating && _activeLeg.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _activeLeg,
                        color: _kRouteCore,
                        borderColor: _kRouteCasing,
                        borderStrokeWidth: 3.5,
                        strokeWidth: 6.0,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    Marker(
                      width: 42,
                      height: 42,
                      point: _orsRoute.isNotEmpty
                          ? _orsRoute.first
                          : _driverLocation,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: _startDriverDrag,
                        onPanUpdate: _updateDriverDrag,
                        onPanEnd: _endDriverDrag,
                        child: _DriverMarker(
                          isActive: true,
                          rotation: _driverBearing,
                        ),
                      ),
                    ),
                    ..._customers.map(
                      (c) => Marker(
                        width: 36,
                        height: 36,
                        point: c.location,
                        child: _HouseMarker(
                          color: _statusColor(c.status),
                          label: c.name.substring(0, 1).toUpperCase(),
                          pulse: c.id == _activeNavigationId,
                        ),
                      ),
                    ),
                    ..._tripStops.map(
                      (stop) => Marker(
                        width: 42,
                        height: 48,
                        point: stop.location,
                        child: _TripStopMarker(
                          sequence: stop.sequence,
                          propertyType: stop.propertyType,
                          isCollected: stop.isCollected,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Top controls
          Positioned(
            top: mapControlsTop,
            right: 12,
            child: Column(
              children: [
                // Map-type picker (Default / Light / Dark / Satellite).
                MapStyleToggle(
                  selected: _mapStyle,
                  onChanged: (style) => setState(() => _mapStyle = style),
                ),
                const SizedBox(height: 8),
                if (isNavigating)
                  _MapButton(
                    icon: Icons.my_location_rounded,
                    onPressed: _recenterNavigation,
                    tooltip: 'Recenter',
                  ),
                if (!isNavigating) ...[
                  _MapButton(
                    icon: Icons.my_location_rounded,
                    onPressed: _centerOnDriver,
                    tooltip: 'Center on me',
                  ),
                  const SizedBox(height: 8),
                  // Fit the whole route in view — quick way to see all
                  // remaining stops at a glance.
                  _MapButton(
                    icon: Icons.zoom_out_map_rounded,
                    onPressed: _recenterNavigation,
                    tooltip: 'Fit route',
                  ),
                  const SizedBox(height: 8),
                  _MapButton(
                    icon: Icons.add_rounded,
                    onPressed: () => _zoomBy(1),
                    tooltip: 'Zoom in',
                  ),
                  const SizedBox(height: 8),
                  _MapButton(
                    icon: Icons.remove_rounded,
                    onPressed: () => _zoomBy(-1),
                    tooltip: 'Zoom out',
                  ),
                  const SizedBox(height: 8),
                  _MapButton(
                    icon: Icons.refresh_rounded,
                    onPressed: () async {
                      await widget.onRefresh();
                      await _computeRoute();
                    },
                    tooltip: 'Refresh',
                  ),
                  if (_manualDriverOverride) ...[
                    const SizedBox(height: 8),
                    _MapButton(
                      icon: Icons.gps_fixed_rounded,
                      onPressed: _resetDriverLocation,
                      tooltip: 'Reset GPS',
                    ),
                  ],
                ],
              ],
            ),
          ),

          // Next collection point — the only card overlaid on the map (the
          // daily-assignment carousel was removed for a cleaner view).
          if (nextCustomer != null)
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: _NextCollectionPointCard(
                customer: nextCustomer,
                distance: _getDistanceToCustomer(nextCustomer),
                position:
                    nextCustomerPosition >= 0 ? nextCustomerPosition + 1 : 1,
                total: widget.customers.length,
                onNavigate: () => _startNavigation(nextCustomer.id),
              ),
            ),

          // Navigation header
          if (navigationCustomer != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _NavigationHeader(
                customer: navigationCustomer,
                distance: _getDistanceToCustomer(navigationCustomer),
                onStop: _stopNavigation,
              ),
            ),

          // Navigation action tray
          // Navigation action tray
          if (navigationCustomer != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: bottomOverlayOffset,
              child: AnimatedContainer(
                duration: _kNavigationTransitionDuration,
                curve: Curves.easeInOut,
                height: 120,
                child: _NavigationActionCard(
                  customer: navigationCustomer,
                  distance: _getDistanceToCustomer(navigationCustomer),
                  onComplete: () => _handleCollect(navigationCustomer),
                  onSkip: () => _handleSkip(navigationCustomer),
                ),
              ),
            ),

          // Bottom customer carousel - compact design
          // Positioned(
          //   left: 0,
          //   right: 0,
          //   bottom: bottomOverlayOffset,
          //   child: AnimatedContainer(
          //     duration: _kNavigationTransitionDuration,
          //     curve: Curves.easeInOut,
          //     height: isNavigating ? 0 : 140,
          //     child: widget.loading
          //         ? const Center(child: CircularProgressIndicator())
          //         : widget.error != null
          //             ? Center(
          //                 child: Text(
          //                   widget.error!,
          //                   style: const TextStyle(
          //                     color: Colors.red,
          //                     fontWeight: FontWeight.w700,
          //                   ),
          //                 ),
          //               )
          //             : _customers.isEmpty
          //                 ? const Center(
          //                     child: Text(
          //                       'All customers completed!',
          //                       style: TextStyle(
          //                         fontSize: 16,
          //                         fontWeight: FontWeight.w700,
          //                         color: Colors.green,
          //                       ),
          //                     ),
          //                   )
          //                 : ListView.separated(
          //                     padding:
          //                         const EdgeInsets.symmetric(horizontal: 16),
          //                     scrollDirection: Axis.horizontal,
          //                     itemBuilder: (context, index) {
          //                       final customer = _customers[index];
          //                       return _CustomerCard(
          //                         customer: customer,
          //                         distance: _getDistanceToCustomer(customer),
          //                         onComplete: () => _handleCollect(customer),
          //                         onSkip: () => _handleSkip(customer),
          //                         onStart: () => _startNavigation(customer.id),
          //                         onOpenAssignment: () =>
          //                             _openAssignmentScreen(customer),
          //                       );
          //                     },
          //                     separatorBuilder: (_, __) =>
          //                         const SizedBox(width: 10),
          //                     itemCount: _customers.length,
          //                   ),
          //   ),
          // ),
        ],
      ),
    );
  }
}

class _NextCollectionPointCard extends StatelessWidget {
  const _NextCollectionPointCard({
    required this.customer,
    required this.distance,
    required this.position,
    required this.total,
    required this.onNavigate,
  });

  final _DriverAssignmentStop customer;
  final String distance;
  final int position;
  final int total;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    return CaptainGlassCard(
      onTap: onNavigate,
      tint: CaptainTheme.gold,
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: CaptainTheme.accentGradient,
              borderRadius: const BorderRadius.all(Radius.circular(14)),
            ),
            child: Text(
              position.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.flag_rounded,
                        size: 12, color: CaptainTheme.gold),
                    const SizedBox(width: 4),
                    Text(
                      'NEXT COLLECTION POINT',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: CaptainTheme.gold,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  customer.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: CaptainTheme.strongText,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  total > 0 ? 'Stop $position of $total' : 'Ready for route',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: CaptainTheme.mutedText,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            decoration: BoxDecoration(
              color: CaptainTheme.accentSoft,
              borderRadius: CaptainTheme.chipRadius,
              border: Border.all(
                color: CaptainTheme.accent.withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  distance,
                  style: TextStyle(
                    color: CaptainTheme.accent,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  'away',
                  style: TextStyle(
                    color: CaptainTheme.accent.withValues(alpha: 0.85),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// PART 4: NavigationHeader, Cards, History, Profile, and Markers
// ============================================================

class _NavigationHeader extends StatelessWidget {
  const _NavigationHeader({
    required this.customer,
    required this.distance,
    required this.onStop,
  });

  final _DriverAssignmentStop customer;
  final String distance;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: CaptainGlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CaptainGlassChip(
                  icon: Icons.navigation_rounded,
                  color: CaptainTheme.accent,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        distance,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: CaptainTheme.accent,
                        ),
                      ),
                      Text(
                        customer.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: CaptainTheme.strongText,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 36,
                  height: 36,
                  child: Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: Icon(Icons.close_rounded,
                          color: CaptainTheme.mutedText, size: 18),
                      onPressed: onStop,
                      tooltip: 'Stop navigation',
                    ),
                  ),
                ),
              ],
            ),
            if (customer.address.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.location_on_outlined,
                      size: 16, color: CaptainTheme.mutedText),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      customer.address,
                      style: TextStyle(
                        fontSize: 12,
                        color: CaptainTheme.mutedText,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NavigationActionCard extends StatelessWidget {
  const _NavigationActionCard({
    required this.customer,
    required this.distance,
    required this.onComplete,
    required this.onSkip,
  });

  final _DriverAssignmentStop customer;
  final String distance;
  final VoidCallback onComplete;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final displayName = customer.customerName?.trim().isNotEmpty == true
        ? customer.customerName!
        : customer.wardName;
    final isDone = customer.status == _CustomerStatus.collected ||
        customer.status == _CustomerStatus.skipped;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: CaptainGlassCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: CaptainTheme.accentGradient,
              ),
              alignment: Alignment.center,
              child: Text(
                displayName[0].toUpperCase(),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: CaptainTheme.strongText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    distance,
                    style: TextStyle(
                      color: CaptainTheme.mutedText,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    customer.shift.replaceAll('_', ' ').toUpperCase(),
                    style: TextStyle(
                      color: CaptainTheme.mutedText.withValues(alpha: 0.8),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              children: [
                SizedBox(
                  height: 32,
                  child: ElevatedButton(
                    onPressed: isDone ? null : onComplete,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      backgroundColor: isDone
                          ? CaptainTheme.mutedText.withValues(alpha: 0.3)
                          : CaptainTheme.success,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Done',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: isDone ? CaptainTheme.mutedText : Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 28,
                  child: OutlinedButton(
                    onPressed: isDone ? null : onSkip,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      side: BorderSide(
                        color: CaptainTheme.hairline,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Skip',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: CaptainTheme.strongText,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({
    required this.customer,
    required this.distance,
    required this.onComplete,
    required this.onSkip,
    required this.onStart,
    required this.onOpenAssignment,
  });

  final _DriverAssignmentStop customer;
  final String distance;
  final VoidCallback onComplete;
  final VoidCallback onSkip;
  final VoidCallback onStart;
  final VoidCallback onOpenAssignment;

  Color get _statusColor {
    switch (customer.status) {
      case _CustomerStatus.collected:
        return Colors.green;
      case _CustomerStatus.skipped:
        return Colors.orange;
      case _CustomerStatus.later:
        return Colors.deepOrange;
      case _CustomerStatus.navigating:
        return Colors.blue;
      case _CustomerStatus.pending:
        return Colors.red;
    }
  }

  Color get _assignmentBg {
    switch (customer.assignmentType.toLowerCase()) {
      case 'emergency':
        return Colors.red.shade100;
      case 'temporary':
        return Colors.orange.shade100;
      default:
        return Colors.green.shade100;
    }
  }

  Color get _assignmentFg {
    switch (customer.assignmentType.toLowerCase()) {
      case 'emergency':
        return Colors.red.shade700;
      case 'temporary':
        return Colors.orange.shade700;
      default:
        return Colors.green.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName = customer.customerName?.trim().isNotEmpty == true
        ? customer.customerName!
        : customer.wardName;
    final isDone = customer.status == _CustomerStatus.collected ||
        customer.status == _CustomerStatus.skipped;

    return SizedBox(
      width: 240,
      child: Card(
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onOpenAssignment,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ================= HEADER =================
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: _statusColor.withOpacity(0.15),
                      child: Text(
                        displayName[0].toUpperCase(),
                        style: TextStyle(
                          color: _statusColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                Icons.near_me_rounded,
                                size: 11,
                                color: Colors.grey.shade600,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                distance,
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // ===== ASSIGNMENT TYPE BADGE =====
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _assignmentBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        customer.assignmentType.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: _assignmentFg,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // ================= ACTION BUTTONS =================
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 32,
                        child: ElevatedButton(
                          onPressed: isDone ? null : onComplete,
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            backgroundColor: Colors.green.shade700,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'Complete',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: SizedBox(
                        height: 32,
                        child: OutlinedButton(
                          onPressed: isDone ? null : onSkip,
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'Skip',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // ================= NAVIGATE =================
                SizedBox(
                  width: double.infinity,
                  height: 32,
                  child: ElevatedButton.icon(
                    onPressed:
                        isDone || customer.status == _CustomerStatus.navigating
                            ? null
                            : onStart,
                    icon: const Icon(Icons.navigation_rounded, size: 13),
                    label: const Text(
                      'Navigate',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      backgroundColor: Colors.blue.shade700,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AssignmentsTab extends StatelessWidget {
  const _AssignmentsTab({
    required this.currentAssignments,
    required this.historyAssignments,
    required this.activeTripDetail,
    required this.loading,
    required this.error,
    required this.onRefresh,
  });

  final List<OperatorTripHistorySummary> currentAssignments;
  final List<OperatorTripHistorySummary> historyAssignments;
  final OperatorTripHistoryDetail? activeTripDetail;
  final bool loading;
  final String? error;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return _AssignmentsErrorState(
        message: error!,
        onRetry: () => onRefresh(),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AssignmentsHeader(
            currentCount: currentAssignments.length,
            historyCount: historyAssignments.length,
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: TabBar(
              labelColor: OperatorTheme.primary,
              unselectedLabelColor: OperatorTheme.mutedText,
              indicatorColor: OperatorTheme.primary,
              tabs: [
                Tab(text: 'Current Trip'),
                Tab(text: 'History'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _DriverCurrentTripTab(
                  detail: activeTripDetail,
                  fallbackTrips: currentAssignments,
                  onRefresh: onRefresh,
                ),
                _DriverTripHistoryTab(
                  assignments: historyAssignments,
                  onRefresh: onRefresh,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverCurrentTripTab extends StatelessWidget {
  const _DriverCurrentTripTab({
    required this.detail,
    required this.fallbackTrips,
    required this.onRefresh,
  });

  final OperatorTripHistoryDetail? detail;
  final List<OperatorTripHistorySummary> fallbackTrips;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final summary = detail?.summary ??
        (fallbackTrips.isNotEmpty ? fallbackTrips.first : null);

    return RefreshIndicator(
      color: OperatorTheme.accent,
      onRefresh: onRefresh,
      child: summary == null
          ? ListView(
              padding: const EdgeInsets.fromLTRB(20, 40, 20, 140),
              children: const [
                _DriverEmptyAssignmentMessage(
                  icon: Icons.route_rounded,
                  message: 'No current trip assigned.',
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 140),
              children: [
                OperatorTripSummaryCard(
                  trip: summary,
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Text(
                      'Collection Points',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: OperatorTheme.strongText,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${detail?.collectionPoints.length ?? 0}',
                      style: TextStyle(
                        color: OperatorTheme.mutedText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (detail == null || detail!.collectionPoints.isEmpty)
                  const _DriverEmptyAssignmentMessage(
                    icon: Icons.location_off_rounded,
                    message: 'No collection points found for this trip.',
                  )
                else
                  ...detail!.collectionPoints.map(
                    (cp) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: OperatorCpCard(cp: cp),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _DriverTripHistoryTab extends StatelessWidget {
  const _DriverTripHistoryTab({
    required this.assignments,
    required this.onRefresh,
  });

  final List<OperatorTripHistorySummary> assignments;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: OperatorTheme.accent,
      onRefresh: onRefresh,
      child: assignments.isEmpty
          ? ListView(
              padding: const EdgeInsets.fromLTRB(20, 40, 20, 140),
              children: const [
                _DriverEmptyAssignmentMessage(
                  icon: Icons.history_toggle_off_rounded,
                  message: 'No completed trips yet.',
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 140),
              itemCount: assignments.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final trip = assignments[index];
                return OperatorTripSummaryCard(
                  trip: trip,
                );
              },
            ),
    );
  }
}

class _DriverEmptyAssignmentMessage extends StatelessWidget {
  const _DriverEmptyAssignmentMessage({
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: OperatorTheme.mutedText, size: 46),
        const SizedBox(height: 10),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: OperatorTheme.mutedText,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _AssignmentsHeader extends StatelessWidget {
  const _AssignmentsHeader({
    required this.currentCount,
    required this.historyCount,
  });

  final int currentCount;
  final int historyCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Row(
        children: [
          Text(
            AppCopy.driverAssignments,
            style: TextStyle(
              color: OperatorTheme.strongText,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          _CountChip(
            label: AppCopy.driverCurrent,
            count: currentCount,
            color: OperatorTheme.primary,
          ),
          const SizedBox(width: 8),
          _CountChip(
            label: AppCopy.driverHistory,
            count: historyCount,
            color: OperatorTheme.mutedText,
          ),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        '$count $label',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _AssignmentsErrorState extends StatelessWidget {
  const _AssignmentsErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            message,
            style: const TextStyle(
              color: Colors.redAccent,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
              backgroundColor: OperatorTheme.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _AssignmentScreen extends StatefulWidget {
  const _AssignmentScreen({
    required this.wardName,
    required this.customers,
    required this.onCollect,
    required this.onLater,
    required this.onSkip,
  });

  final String wardName;
  final List<_DriverAssignmentStop> customers;
  final Future<void> Function(_DriverAssignmentStop customer) onCollect;
  final void Function(_DriverAssignmentStop customer) onLater;
  final Future<void> Function(_DriverAssignmentStop customer) onSkip;

  @override
  State<_AssignmentScreen> createState() => _AssignmentScreenState();
}

class _AssignmentScreenState extends State<_AssignmentScreen> {
  @override
  Widget build(BuildContext context) {
    final title = widget.wardName.isNotEmpty ? widget.wardName : 'Assignment';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: widget.customers.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final customer = widget.customers[index];
          final displayName = customer.customerName?.trim().isNotEmpty == true
              ? customer.customerName!
              : customer.wardName;
          final isDone = customer.status == _CustomerStatus.collected ||
              customer.status == _CustomerStatus.skipped;

          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Shift: ${customer.shift.replaceAll('_', ' ').toUpperCase()}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                if (customer.customerName == null ||
                    customer.customerName!.isEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Ward: ${customer.wardName}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: isDone
                            ? null
                            : () async {
                                await widget.onCollect(customer);
                                if (mounted) setState(() {});
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('Collect'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          widget.onLater(customer);
                          setState(() {});
                        },
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('Later'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: isDone
                            ? null
                            : () async {
                                await widget.onSkip(customer);
                                if (mounted) setState(() {});
                              },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('Skip'),
                      ),
                    ),
                  ],
                ),
                if (customer.status == _CustomerStatus.skipped &&
                    customer.skipReason != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Reason: ${customer.skipReason}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red.shade400,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (customer.status == _CustomerStatus.later) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Marked for later',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.deepOrange.shade400,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ProfileTab extends StatefulWidget {
  const _ProfileTab({
    required this.onLogout,
    required this.driverName,
    required this.empId,
    required this.tripVehicle,
  });

  final VoidCallback onLogout;
  final String driverName;
  final String empId;
  final OperatorTripVehicle? tripVehicle;

  @override
  State<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<_ProfileTab> {
  static const String _baseUrl = kOperatorProfileBaseUrl;

  bool _loading = true;
  String? _imageName;
  String? _department;
  String? _designation;
  DateTime? _doj;
  String? _drivingLicenceNo;
  DateTime? _drivingLicenceExpiry;
  int? _drivingExperienceYears;
  String? _dob;
  String? _bloodGroup;
  String? _gender;
  String? _presentAddress;
  String? _permanentAddress;
  String? _contactMobile;
  String? _contactEmail;
  bool _vehicleLoading = false;
  String? _vehicleNumber;
  String? _vehicleType;
  String? _vehicleCondition;
  bool? _vehicleIsActive;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
    _fetchVehicleDetails();
  }

  @override
  void didUpdateWidget(covariant _ProfileTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.empId != widget.empId) {
      _loading = true;
      _fetchProfile();
    }
    if (oldWidget.tripVehicle?.uniqueId != widget.tripVehicle?.uniqueId ||
        oldWidget.tripVehicle?.vehicleNo != widget.tripVehicle?.vehicleNo) {
      _fetchVehicleDetails();
    }
  }

  Future<void> _fetchProfile() async {
    if (widget.empId.trim().isEmpty) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }
    try {
      final dio = await authorizedDio();
      final response = await dio.get(
        '${ApiConfig.attendanceBase}staff-profile/',
        queryParameters: {'staff_id_id': widget.empId},
      );
      final json = response.data;
      if (json is Map && json['status'] == 'success') {
        final data = json['data'] as Map?;
        final personal = data?['personal'] as Map?;
        if (!mounted) return;
        setState(() {
          final registered = data?['attendance_reg_image']?.toString() ?? '';
          final staffPhoto = data?['photo']?.toString() ?? '';
          _imageName = registered.isNotEmpty ? registered : staffPhoto;
          _department = data?['department']?.toString();
          _designation = data?['designation']?.toString();
          _doj = _tryParseDate(data?['doj']);
          _drivingLicenceNo = data?['driving_licence_no']?.toString();
          _drivingLicenceExpiry =
              _tryParseDate(data?['driving_licence_expiry_date']);
          _drivingExperienceYears =
              int.tryParse(data?['driving_experience_years']?.toString() ?? '');
          _dob = personal?['dob']?.toString();
          _bloodGroup = personal?['blood_group']?.toString();
          _gender = personal?['gender']?.toString();
          _presentAddress = personal?['present_address']?.toString();
          _permanentAddress = personal?['permanent_address']?.toString();
          _contactMobile = personal?['contact_mobile']?.toString();
          _contactEmail = personal?['contact_email']?.toString();
          _loading = false;
        });
      } else {
        if (!mounted) return;
        setState(() => _loading = false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _fetchVehicleDetails() async {
    final tripVehicle = widget.tripVehicle;
    if (tripVehicle == null) {
      if (!mounted) return;
      setState(() {
        _vehicleLoading = false;
        _vehicleNumber = null;
        _vehicleType = null;
        _vehicleCondition = null;
        _vehicleIsActive = null;
      });
      return;
    }

    if (mounted) {
      setState(() {
        _vehicleLoading = true;
        _vehicleNumber = tripVehicle.vehicleNo;
        _vehicleType = null;
        _vehicleCondition = null;
        _vehicleIsActive = null;
      });
    }

    final vehicleId = tripVehicle.uniqueId.trim();
    if (vehicleId.isEmpty) {
      if (!mounted) return;
      setState(() => _vehicleLoading = false);
      return;
    }

    try {
      final dio = await authorizedDio();
      final response = await dio.get('${ApiConfig.vehicles}$vehicleId/');
      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : const <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _vehicleNumber =
            data['vehicle_no']?.toString() ?? tripVehicle.vehicleNo;
        _vehicleType = data['vehicle_type_name']?.toString();
        _vehicleCondition =
            _formatVehicleCondition(data['vehicle_condition']?.toString());
        final isActiveRaw = data['is_active'];
        _vehicleIsActive = isActiveRaw == true ||
            isActiveRaw?.toString().toLowerCase() == 'true';
        _vehicleLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _vehicleLoading = false);
    }
  }

  DateTime? _tryParseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  String? _formatVehicleCondition(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final normalized = value.trim().toLowerCase().replaceAll('_', ' ');
    return normalized
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  String _convertToUrl(String path) {
    final clean = path.replaceAll('\\', '/');
    if (clean.startsWith('http')) return clean;
    if (clean.startsWith('/')) return '$_baseUrl$clean';
    return '$_baseUrl/media/$clean';
  }

  bool _isEmpty(String? v) => v == null || v.trim().isEmpty;

  @override
  Widget build(BuildContext context) {
    final driverName = widget.driverName;
    final empId = widget.empId;
    final hasPhoto = !_isEmpty(_imageName);

    final hasEmployment =
        !_isEmpty(_department) || !_isEmpty(_designation) || _doj != null;
    final hasPersonal =
        !_isEmpty(_dob) || !_isEmpty(_bloodGroup) || !_isEmpty(_gender);
    final hasContact = !_isEmpty(_contactMobile) || !_isEmpty(_contactEmail);
    final hasLicence = !_isEmpty(_drivingLicenceNo) ||
        _drivingLicenceExpiry != null ||
        _drivingExperienceYears != null;
    final hasAddress =
        !_isEmpty(_presentAddress) || !_isEmpty(_permanentAddress);
    final hasVehicle = _vehicleLoading ||
        !_isEmpty(_vehicleNumber) ||
        !_isEmpty(_vehicleType) ||
        !_isEmpty(_vehicleCondition) ||
        _vehicleIsActive != null;

    return CaptainBackground(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Profile card
            CaptainGlassCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: hasPhoto ? null : CaptainTheme.accentGradient,
                    ),
                    alignment: Alignment.center,
                    clipBehavior: Clip.antiAlias,
                    child: hasPhoto
                        ? Image.network(
                            _convertToUrl(_imageName!),
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.person_rounded,
                              size: 32,
                              color: CaptainTheme.mutedText,
                            ),
                          )
                        : Icon(Icons.person_rounded,
                            size: 32, color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    driverName.isEmpty ? 'Captain' : driverName,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: CaptainTheme.strongText,
                    ),
                  ),
                  if (!_isEmpty(_designation)) ...[
                    const SizedBox(height: 2),
                    Text(
                      _designation!,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: CaptainTheme.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    'ID: $empId',
                    style: TextStyle(
                      fontSize: 11,
                      color: CaptainTheme.mutedText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: CircularProgressIndicator(),
              ),

            if (!_loading && hasEmployment) ...[
              _ProfileSectionCard(
                icon: Icons.badge_outlined,
                title: 'EMPLOYMENT',
                rows: [
                  if (!_isEmpty(_department)) ('Department', _department!),
                  if (!_isEmpty(_designation)) ('Designation', _designation!),
                  if (_doj != null)
                    ('Date of joining', DateFormat.yMMMd().format(_doj!)),
                ],
              ),
              const SizedBox(height: 18),
            ],

            if (!_loading && hasLicence) ...[
              _ProfileSectionCard(
                icon: Icons.badge_outlined,
                title: 'DRIVING LICENCE',
                rows: [
                  if (!_isEmpty(_drivingLicenceNo))
                    ('Licence no.', _drivingLicenceNo!),
                  if (_drivingLicenceExpiry != null)
                    (
                      'Expiry',
                      DateFormat.yMMMd().format(_drivingLicenceExpiry!),
                    ),
                  if (_drivingExperienceYears != null)
                    ('Experience', '$_drivingExperienceYears yrs'),
                ],
                warning: _drivingLicenceExpiry != null &&
                        _drivingLicenceExpiry!.isBefore(
                            DateTime.now().add(const Duration(days: 30)))
                    ? (_drivingLicenceExpiry!.isBefore(DateTime.now())
                        ? 'Licence has expired'
                        : 'Licence expires soon')
                    : null,
              ),
              const SizedBox(height: 18),
            ],

            if (!_loading && hasPersonal) ...[
              _ProfileSectionCard(
                icon: Icons.person_outline_rounded,
                title: 'PERSONAL',
                rows: [
                  if (!_isEmpty(_dob)) ('Date of birth', _dob!),
                  if (!_isEmpty(_bloodGroup)) ('Blood group', _bloodGroup!),
                  if (!_isEmpty(_gender)) ('Gender', _gender!),
                ],
              ),
              const SizedBox(height: 18),
            ],

            if (!_loading && hasContact) ...[
              _ProfileSectionCard(
                icon: Icons.contact_phone_outlined,
                title: 'CONTACT',
                rows: [
                  if (!_isEmpty(_contactMobile)) ('Mobile', _contactMobile!),
                  if (!_isEmpty(_contactEmail)) ('Email', _contactEmail!),
                ],
              ),
              const SizedBox(height: 18),
            ],

            if (!_loading && hasAddress) ...[
              _ProfileSectionCard(
                icon: Icons.home_outlined,
                title: 'ADDRESS',
                rows: [
                  if (!_isEmpty(_presentAddress)) ('Present', _presentAddress!),
                  if (!_isEmpty(_permanentAddress))
                    ('Permanent', _permanentAddress!),
                ],
              ),
              const SizedBox(height: 18),
            ],

            // Vehicle card
            if (hasVehicle)
              CaptainGlassCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.local_shipping_rounded,
                            size: 18, color: CaptainTheme.accent),
                        const SizedBox(width: 8),
                        Text(
                          'VEHICLE',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: CaptainTheme.mutedText,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _SimpleRow(
                      'Number',
                      _vehicleNumber ?? '—',
                    ),
                    const SizedBox(height: 8),
                    _SimpleRow(
                      'Type',
                      _vehicleType ?? '—',
                    ),
                    if (!_isEmpty(_vehicleCondition)) ...[
                      const SizedBox(height: 8),
                      _SimpleRow(
                        'Condition',
                        _vehicleCondition!,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _SimpleRow(
                            'Status',
                            _vehicleIsActive == null
                                ? '—'
                                : (_vehicleIsActive! ? 'Active' : 'Inactive'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _vehicleIsActive == true
                                ? CaptainTheme.success
                                : CaptainTheme.mutedText,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            if (hasVehicle) const SizedBox(height: 18),

            // Theme toggle
            CaptainGlassCard(
              padding: const EdgeInsets.all(14),
              child: ValueListenableBuilder<bool>(
                valueListenable: CaptainThemeStore.isDark,
                builder: (context, isDark, _) {
                  return Row(
                    children: [
                      Icon(
                        isDark
                            ? Icons.dark_mode_rounded
                            : Icons.light_mode_rounded,
                        size: 18,
                        color: CaptainTheme.accent,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Theme',
                          style: TextStyle(
                            fontSize: 13,
                            color: CaptainTheme.strongText,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        isDark ? 'Dark' : 'Light',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: CaptainTheme.mutedText,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Switch(
                        value: isDark,
                        activeColor: CaptainTheme.accent,
                        onChanged: (value) => CaptainThemeStore.setDark(value),
                      ),
                    ],
                  );
                },
              ),
            ),

            const SizedBox(height: 24),

            // Logout
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: widget.onLogout,
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text(
                  'Logout',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: CaptainTheme.danger,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: MediaQuery.viewPaddingOf(context).bottom +
                  kCaptainProfileBottomSpacer,
            ),
          ],
        ),
      ),
    );
  }
}

class _SimpleRow extends StatelessWidget {
  const _SimpleRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: CaptainTheme.mutedText,
            fontWeight: FontWeight.w600,
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 13,
              color: CaptainTheme.strongText,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

/// A titled profile detail card — icon + label header, a list of label/value
/// rows, and an optional warning strip (e.g. licence expiring soon).
class _ProfileSectionCard extends StatelessWidget {
  const _ProfileSectionCard({
    required this.icon,
    required this.title,
    required this.rows,
    this.warning,
  });

  final IconData icon;
  final String title;
  final List<(String, String)> rows;
  final String? warning;

  @override
  Widget build(BuildContext context) {
    return CaptainGlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: CaptainTheme.accent),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 10.5,
                  color: CaptainTheme.mutedText,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _SimpleRow(rows[i].$1, rows[i].$2),
          ],
          if (warning != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 14, color: CaptainTheme.warning),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    warning!,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: CaptainTheme.warning,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DriverMarker extends StatelessWidget {
  final bool isActive;
  final double rotation;

  const _DriverMarker({
    required this.isActive,
    required this.rotation,
  });

  @override
  Widget build(BuildContext context) {
    return const Icon(
      Icons.navigation_rounded,
      size: 38,
      color: Colors.deepOrange,
    );
  }
}

class _HouseMarker extends StatelessWidget {
  const _HouseMarker({
    required this.color,
    required this.label,
    this.pulse = false,
  });

  final Color color;
  final String label;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _TripStopMarker extends StatelessWidget {
  const _TripStopMarker({
    required this.sequence,
    required this.propertyType,
    required this.isCollected,
  });

  final int sequence;
  final String propertyType;
  final bool isCollected;

  Color _colorForType() {
    switch (propertyType.toLowerCase()) {
      case 'industry':
        return const Color(0xFFFB8C00);
      case 'commercial':
        return const Color(0xFF6D4C41);
      case 'house':
      default:
        return const Color(0xFF00897B);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorForType();
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        ColorFiltered(
          colorFilter: isCollected
              ? const ColorFilter.mode(Colors.green, BlendMode.modulate)
              : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
          child: Image.asset(
            'assets/icons/pin.png',
            width: 36,
            height: 44,
            fit: BoxFit.contain,
          ),
        ),
        Positioned(
          top: 5,
          child: Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isCollected ? Colors.green.shade700 : color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              sequence.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 10,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CaptainTheme.surface,
      shape: const CircleBorder(),
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: CaptainTheme.hairline),
          boxShadow: CaptainTheme.softShadow,
        ),
        child: IconButton(
          icon: Icon(icon, color: CaptainTheme.accent),
          onPressed: onPressed,
          tooltip: tooltip,
        ),
      ),
    );
  }
}
