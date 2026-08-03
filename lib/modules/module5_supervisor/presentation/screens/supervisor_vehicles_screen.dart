import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:iwms_citizen_app/core/di.dart';
import 'package:iwms_citizen_app/data/models/operator_trip_models.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/data/supervisor_models.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/data/supervisor_repository.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/logic/supervisor_bloc.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/presentation/screens/supervisor_assignment_vehicle_marker_screen.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/presentation/theme/supervisor_theme.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/presentation/widgets/supervisor_assignment_picker_dialog.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/presentation/widgets/supervisor_state_views.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/presentation/widgets/supervisor_visuals.dart';
import 'package:iwms_citizen_app/shared/widgets/crew_avatar_stack.dart';

class SupervisorVehiclesScreen extends StatefulWidget {
  const SupervisorVehiclesScreen({super.key});

  @override
  State<SupervisorVehiclesScreen> createState() =>
      _SupervisorVehiclesScreenState();
}

class _SupervisorVehiclesScreenState extends State<SupervisorVehiclesScreen> {
  final SupervisorRepository _repo = getIt<SupervisorRepository>();

  bool _loading = true;
  String? _error;
  Map<String, SupervisorVehicle> _vehiclesByNo = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final vehicles = await _repo.fetchVehicles();
      if (!mounted) return;
      setState(() {
        _vehiclesByNo = {
          for (final vehicle in vehicles)
            if (vehicle.vehicleNo.trim().isNotEmpty)
              vehicle.vehicleNo.trim(): vehicle,
        };
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load vehicles';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SupervisorTheme.background,
      appBar: AppBar(
        backgroundColor: SupervisorTheme.primary,
        foregroundColor: Colors.white,
        title: const Text('Vehicles'),
      ),
      body: SupervisorPatternBackground(
        child: BlocBuilder<SupervisorBloc, SupervisorState>(
          builder: (context, state) {
            if (_loading) return const SupervisorLoadingView();
            if (_error != null) {
              return SupervisorErrorView(message: _error!, onRetry: _load);
            }
            final items = _buildItems(state.assignments);
            if (items.isEmpty) {
              return SupervisorEmptyView(
                message: 'No vehicles assigned to this supervisor.',
                icon: Icons.local_shipping_outlined,
                onRefresh: () async {
                  await Future.wait([
                    _load(),
                    () async {
                      context.read<SupervisorBloc>().add(
                            const SupervisorRefreshRequested(),
                          );
                    }(),
                  ]);
                },
              );
            }
            return RefreshIndicator(
              color: SupervisorTheme.accent,
              onRefresh: () async {
                await Future.wait([
                  _load(),
                  () async {
                    context.read<SupervisorBloc>().add(
                          const SupervisorRefreshRequested(),
                        );
                  }(),
                ]);
              },
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) => _VehicleCard(item: items[i]),
              ),
            );
          },
        ),
      ),
    );
  }

  List<_VehicleCardData> _buildItems(List<SupervisorAssignment> assignments) {
    final grouped = <String, List<SupervisorAssignment>>{};
    for (final assignment in assignments) {
      final vehicleNo = assignment.vehicleNo.trim();
      if (vehicleNo.isEmpty) continue;
      grouped.putIfAbsent(vehicleNo, () => []).add(assignment);
    }

    final items = grouped.entries.map((entry) {
      final vehicleNo = entry.key;
      final vehicle = _vehiclesByNo[vehicleNo];
      final trips = entry.value;
      final mapAssignment = trips.firstWhere(
        (assignment) => assignment.isInProgress,
        orElse: () => trips.first,
      );
      double binWeight = 0;
      double householdWeight = 0;
      final areas = <String>{};
      final binStops = <_VehicleStopDetail>[];
      final householdStops = <_VehicleStopDetail>[];
      for (final assignment in trips) {
        areas.add(assignment.areaName);
        for (final stop in assignment.stops) {
          final detail = _VehicleStopDetail(
            assignmentId: assignment.uniqueId,
            assignmentName: assignment.areaName,
            tripCode: assignment.tripCode,
            stop: stop,
          );
          final weight = stop.collectedWeightKg ?? 0;
          if (stop.isHousehold) {
            householdWeight += weight;
            householdStops.add(detail);
          } else {
            binWeight += weight;
            binStops.add(detail);
          }
        }
      }
      final locationText = vehicle?.locationLabel ??
          (areas.isEmpty
              ? ''
              : areas.length == 1
                  ? areas.first
                  : '${areas.first} +${areas.length - 1}');
      trips.sort((a, b) {
        if (a.isInProgress && !b.isInProgress) return -1;
        if (!a.isInProgress && b.isInProgress) return 1;
        final dateA = a.tripDate;
        final dateB = b.tripDate;
        if (dateA == null && dateB == null) return 0;
        if (dateA == null) return 1;
        if (dateB == null) return -1;
        return dateA.compareTo(dateB);
      });
      return _VehicleCardData(
        vehicleNo: vehicleNo,
        vehicleType: vehicle?.vehicleTypeName ?? '',
        fuelType: vehicle?.fuelTypeName ?? '',
        capacity: vehicle?.capacity,
        isActive: vehicle?.isActive ?? true,
        locationText: locationText,
        assignments: trips,
        binWeightKg: binWeight,
        householdWeightKg: householdWeight,
        binStops: binStops,
        householdStops: householdStops,
        crew: mapAssignment.crew,
        driverName: mapAssignment.driverName,
        operatorName: mapAssignment.operatorName,
      );
    }).toList()
      ..sort((a, b) => a.vehicleNo.compareTo(b.vehicleNo));

    return items;
  }
}

class _VehicleCardData {
  const _VehicleCardData({
    required this.vehicleNo,
    required this.vehicleType,
    required this.fuelType,
    required this.capacity,
    required this.isActive,
    required this.locationText,
    required this.assignments,
    required this.binWeightKg,
    required this.householdWeightKg,
    required this.binStops,
    required this.householdStops,
    required this.crew,
    required this.driverName,
    required this.operatorName,
  });

  final String vehicleNo;
  final String vehicleType;
  final String fuelType;
  final double? capacity;
  final bool isActive;
  final String locationText;
  final List<SupervisorAssignment> assignments;
  final double binWeightKg;
  final double householdWeightKg;
  final List<_VehicleStopDetail> binStops;
  final List<_VehicleStopDetail> householdStops;
  final OperatorTripCrew? crew;
  final String driverName;
  final String operatorName;
}

class _VehicleStopDetail {
  const _VehicleStopDetail({
    required this.assignmentId,
    required this.assignmentName,
    required this.tripCode,
    required this.stop,
  });

  final String assignmentId;
  final String assignmentName;
  final String tripCode;
  final SupervisorStop stop;
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({required this.item});

  final _VehicleCardData item;

  SupervisorAssignment? get _mapAssignment {
    for (final assignment in item.assignments) {
      if (assignment.isInProgress) return assignment;
    }
    return item.assignments.isNotEmpty ? item.assignments.first : null;
  }

  @override
  Widget build(BuildContext context) {
    final inProgress = item.assignments.any((a) => a.isInProgress);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: SupervisorTheme.cardRadius,
        onTap: () => _showTrips(context),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: inProgress
                ? SupervisorTheme.info.withValues(alpha: 0.06)
                : SupervisorTheme.surface,
            borderRadius: SupervisorTheme.cardRadius,
            border: Border.all(
              color: inProgress
                  ? SupervisorTheme.info.withValues(alpha: 0.28)
                  : SupervisorTheme.hairline.withValues(alpha: 0.6),
            ),
            boxShadow: SupervisorTheme.softShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: SupervisorTheme.info.withValues(alpha: 0.12),
                      borderRadius: SupervisorTheme.chipRadius,
                    ),
                    child: const Icon(
                      Icons.local_shipping_rounded,
                      size: 18,
                      color: SupervisorTheme.info,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.vehicleNo,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: SupervisorTheme.strongText,
                          ),
                        ),
                        if (item.vehicleType.isNotEmpty ||
                            item.locationText.isNotEmpty)
                          const SizedBox(height: 3),
                        if (item.vehicleType.isNotEmpty)
                          Text(
                            item.vehicleType,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: SupervisorTheme.mutedText,
                            ),
                          ),
                        if (item.locationText.isNotEmpty)
                          Text(
                            item.locationText,
                            style: const TextStyle(
                              fontSize: 12,
                              color: SupervisorTheme.mutedText,
                            ),
                          ),
                        if (item.crew != null &&
                            (item.crew!.driver != null ||
                                item.crew!.operator != null ||
                                item.crew!.extraOperators.isNotEmpty)) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              CrewAvatarStack(
                                crew: item.crew!,
                                size: 24,
                                overlap: 13,
                                borderColor: SupervisorTheme.surface,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  item.driverName.isNotEmpty
                                      ? item.driverName
                                      : item.operatorName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: SupervisorTheme.strongText,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Locate vehicle',
                    onPressed: _mapAssignment == null
                        ? null
                        : () => _openVehicleMap(
                              context,
                              assignment: _mapAssignment!,
                            ),
                    icon: const Icon(
                      Icons.my_location_rounded,
                      color: SupervisorTheme.accent,
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: (item.isActive
                              ? SupervisorTheme.success
                              : SupervisorTheme.mutedText)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      item.isActive ? 'ACTIVE' : 'INACTIVE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: item.isActive
                            ? SupervisorTheme.success
                            : SupervisorTheme.mutedText,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _WeightPill(
                    label: 'Bin',
                    value: '${item.binWeightKg.toStringAsFixed(2)} kg',
                    color: SupervisorTheme.info,
                    onTap: () => _showWasteDetails(
                      context,
                      title: '${item.vehicleNo} • Bin collection',
                      stops: item.binStops,
                      color: SupervisorTheme.info,
                    ),
                  ),
                  _WeightPill(
                    label: 'Household',
                    value: '${item.householdWeightKg.toStringAsFixed(2)} kg',
                    color: SupervisorTheme.success,
                    onTap: () => _showWasteDetails(
                      context,
                      title: '${item.vehicleNo} • Household collection',
                      stops: item.householdStops,
                      color: SupervisorTheme.success,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _MetaChip(
                    icon: Icons.route_rounded,
                    label:
                        '${item.assignments.length} trip${item.assignments.length == 1 ? '' : 's'}',
                  ),
                  if (item.capacity != null)
                    _MetaChip(
                      icon: Icons.scale_rounded,
                      label: '${item.capacity!.toStringAsFixed(0)} kg',
                    ),
                  if (item.fuelType.isNotEmpty)
                    _MetaChip(
                      icon: Icons.local_gas_station_rounded,
                      label: item.fuelType,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showTrips(context),
                      icon: const Icon(Icons.visibility_outlined, size: 16),
                      label: const Text('View trips'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: SupervisorTheme.accent,
                        side: BorderSide(
                          color: SupervisorTheme.accent.withValues(alpha: 0.4),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: SupervisorTheme.chipRadius,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _mapAssignment == null
                          ? null
                          : () => _openVehicleMap(
                                context,
                                assignment: _mapAssignment!,
                              ),
                      icon: const Icon(Icons.map_outlined, size: 16),
                      label: const Text('View on map'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: SupervisorTheme.info,
                        side: BorderSide(
                          color: SupervisorTheme.info.withValues(alpha: 0.35),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: SupervisorTheme.chipRadius,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTrips(BuildContext context) {
    SupervisorAssignmentPickerDialog.show(
      context,
      title: item.vehicleNo,
      subtitle:
          '${item.assignments.length} trip${item.assignments.length == 1 ? '' : 's'} assigned',
      assignments: item.assignments,
    );
  }

  void _openVehicleMap(
    BuildContext context, {
    required SupervisorAssignment assignment,
  }) {
    Navigator.of(context).push(_VehicleMapRoute(
      child: SupervisorAssignmentVehicleMarkerScreen(
        title: item.vehicleNo,
        assignmentId: assignment.uniqueId,
      ),
    ));
  }

  void _showWasteDetails(
    BuildContext context, {
    required String title,
    required List<_VehicleStopDetail> stops,
    required Color color,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _VehicleWasteDialog(
        title: title,
        color: color,
        stops: stops,
      ),
    );
  }
}

class _VehicleWasteDialog extends StatelessWidget {
  const _VehicleWasteDialog({
    required this.title,
    required this.color,
    required this.stops,
  });

  final String title;
  final Color color;
  final List<_VehicleStopDetail> stops;

  @override
  Widget build(BuildContext context) {
    final totalWeight = stops.fold<double>(
      0,
      (sum, item) => sum + (item.stop.collectedWeightKg ?? 0),
    );
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: const TextScaler.linear(1.0),
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.84,
        ),
        decoration: const BoxDecoration(
          color: SupervisorTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: SupervisorTheme.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: SupervisorTheme.strongText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${stops.length} stops • ${totalWeight.toStringAsFixed(2)} kg',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: SupervisorTheme.mutedText,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: stops.isEmpty
                    ? const Center(
                        child: Text(
                          'No stops available.',
                          style: TextStyle(
                            color: SupervisorTheme.mutedText,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(
                          20,
                          0,
                          20,
                          20 + MediaQuery.viewPaddingOf(context).bottom,
                        ),
                        itemCount: stops.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final item = stops[i];
                          final tone = _statusTone(item.stop.status);
                          final weightText = item.stop.isCollected
                              ? '${(item.stop.collectedWeightKg ?? 0).toStringAsFixed(2)} kg'
                              : '—';
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: tone.color.withValues(alpha: 0.18),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(tone.icon, color: tone.color, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              item.stop.name,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w800,
                                                color:
                                                    SupervisorTheme.strongText,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            weightText,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w800,
                                              color: item.stop.isCollected
                                                  ? color
                                                  : SupervisorTheme.mutedText,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        item.assignmentName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: SupervisorTheme.mutedText,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Trip: ${item.tripCode}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          color: SupervisorTheme.mutedText,
                                        ),
                                      ),
                                      if ((item.stop.statusReason ?? '')
                                          .trim()
                                          .isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          item.stop.statusReason!.trim(),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: SupervisorTheme.mutedText,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusTone {
  const _StatusTone(this.icon, this.color);

  final IconData icon;
  final Color color;
}

_StatusTone _statusTone(String status) {
  final normalized = status.trim().toLowerCase();
  if (normalized == 'collected') {
    return const _StatusTone(
        Icons.check_circle_rounded, SupervisorTheme.success);
  }
  if (normalized == 'collect later') {
    return const _StatusTone(Icons.schedule_rounded, SupervisorTheme.warning);
  }
  if (normalized == 'not available' ||
      normalized == 'skipped' ||
      normalized == 'missed' ||
      normalized == 'not collected') {
    return const _StatusTone(Icons.cancel_rounded, SupervisorTheme.danger);
  }
  return const _StatusTone(
    Icons.radio_button_unchecked_rounded,
    SupervisorTheme.mutedText,
  );
}

class _VehicleMapRoute extends PageRouteBuilder<void> {
  _VehicleMapRoute({required Widget child})
      : super(
          transitionDuration: const Duration(milliseconds: 320),
          reverseTransitionDuration: const Duration(milliseconds: 240),
          pageBuilder: (_, __, ___) => child,
          transitionsBuilder: (_, animation, __, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
                child: child,
              ),
            );
          },
        );
}

class _WeightPill extends StatelessWidget {
  const _WeightPill({
    required this.label,
    required this.value,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String value;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.18)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.scale_rounded, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                '$label ',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: SupervisorTheme.strongText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: SupervisorTheme.mutedText),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: SupervisorTheme.strongText,
          ),
        ),
      ],
    );
  }
}
