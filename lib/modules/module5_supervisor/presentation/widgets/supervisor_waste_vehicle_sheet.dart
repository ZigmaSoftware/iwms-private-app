import 'package:flutter/material.dart';

import 'package:iwms_private_app/modules/module5_supervisor/data/supervisor_models.dart';
import 'package:iwms_private_app/modules/module5_supervisor/data/supervisor_repository.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/screens/supervisor_trip_map_screen.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/screens/supervisor_vehicle_live_map_screen.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/theme/supervisor_theme.dart';

/// One vehicle's collections within the tapped waste-card's date window —
/// weight, the collection points it hit, and shortcuts to that vehicle's
/// live trips/map.
class _VehicleWasteGroup {
  _VehicleWasteGroup({required this.vehicleNo, this.vehicleUniqueId});

  final String vehicleNo;
  final String? vehicleUniqueId;
  double totalKg = 0;
  final List<SupervisorWasteEvent> events = [];

  void add(SupervisorWasteEvent e) {
    totalKg += e.weightKg;
    events.add(e);
  }
}

/// Floating window opened by tapping the Wet/Dry Waste card on the
/// supervisor home page — lists every vehicle that collected that waste
/// stream in the selected date window, its total weight, the collection
/// points it visited (with status), and "View Trip" / "Map" shortcuts.
Future<void> showSupervisorWasteVehicleSheet(
  BuildContext context, {
  required String title,
  required Color accentColor,
  required List<SupervisorWasteEvent> events,
  required bool Function(SupervisorWasteEvent) matches,
}) {
  final matched = events.where(matches).toList();

  final groups = <String, _VehicleWasteGroup>{};
  for (final e in matched) {
    final vehicleNo = (e.vehicleNo ?? '').trim();
    if (vehicleNo.isEmpty) continue;
    final group = groups.putIfAbsent(
      vehicleNo,
      () => _VehicleWasteGroup(
        vehicleNo: vehicleNo,
        vehicleUniqueId: e.vehicleUniqueId,
      ),
    );
    group.add(e);
  }
  final vehicles = groups.values.toList()
    ..sort((a, b) => b.totalKg.compareTo(a.totalKg));

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _SupervisorWasteVehicleSheet(
      title: title,
      accentColor: accentColor,
      vehicles: vehicles,
    ),
  );
}

class _SupervisorWasteVehicleSheet extends StatelessWidget {
  const _SupervisorWasteVehicleSheet({
    required this.title,
    required this.accentColor,
    required this.vehicles,
  });

  final String title;
  final Color accentColor;
  final List<_VehicleWasteGroup> vehicles;

  String _fmt(double kg) => kg >= 1000
      ? '${(kg / 1000).toStringAsFixed(2)} t'
      : '${kg.toStringAsFixed(1)} kg';

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.82;
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: const BoxDecoration(
          color: SupervisorTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: SupervisorTheme.hairline,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 10),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Icon(Icons.local_shipping_rounded,
                        color: accentColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: SupervisorTheme.strongText,
                          ),
                        ),
                        Text(
                          '${vehicles.length} vehicle${vehicles.length == 1 ? '' : 's'}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: SupervisorTheme.mutedText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded,
                        color: SupervisorTheme.mutedText),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: SupervisorTheme.hairline),
            Expanded(
              child: vehicles.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'No collections in this range yet.',
                          style: const TextStyle(
                            color: SupervisorTheme.mutedText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      itemCount: vehicles.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) => _VehicleTile(
                        group: vehicles[index],
                        accentColor: accentColor,
                        fmt: _fmt,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VehicleTile extends StatefulWidget {
  const _VehicleTile({
    required this.group,
    required this.accentColor,
    required this.fmt,
  });

  final _VehicleWasteGroup group;
  final Color accentColor;
  final String Function(double) fmt;

  @override
  State<_VehicleTile> createState() => _VehicleTileState();
}

class _VehicleTileState extends State<_VehicleTile> {
  bool _expanded = false;
  bool _loadingTrips = false;

  Future<void> _viewTrip() async {
    if (_loadingTrips) return;
    setState(() => _loadingTrips = true);
    try {
      final repo = SupervisorRepository();
      final all = await repo.fetchAssignments(mine: true);
      final mine = all
          .where((a) =>
              a.vehicleNo.trim().toLowerCase() ==
              widget.group.vehicleNo.trim().toLowerCase())
          .toList();
      if (!mounted) return;
      if (mine.isEmpty) {
        _showNoTrips();
        return;
      }
      if (mine.length == 1) {
        _openTripMap(mine.first);
        return;
      }
      _showTripPicker(mine);
    } catch (_) {
      if (mounted) _showNoTrips();
    } finally {
      if (mounted) setState(() => _loadingTrips = false);
    }
  }

  void _showNoTrips() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('No live trip found for this vehicle today.')),
    );
  }

  void _openTripMap(SupervisorAssignment trip) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SupervisorTripMapScreen(
          assignmentId: trip.uniqueId,
          title:
              '${trip.tripCode.isNotEmpty ? trip.tripCode : trip.areaName} route',
          driverName: trip.driverName,
          vehicleNo: trip.vehicleNo,
          tripDate: trip.tripDate,
        ),
      ),
    );
  }

  void _showTripPicker(List<SupervisorAssignment> trips) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: SupervisorTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Live trips for this vehicle',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: SupervisorTheme.strongText,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (final trip in trips)
              ListTile(
                leading: const Icon(Icons.alt_route_rounded,
                    color: SupervisorTheme.accent),
                title: Text(
                  trip.tripCode.isNotEmpty ? trip.tripCode : trip.areaName,
                ),
                subtitle: Text('${trip.status} • ${trip.collectionTypeLabel}'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openTripMap(trip);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _openLiveMap() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SupervisorVehicleLiveMapScreen(
          vehicleNo: widget.group.vehicleNo,
          title: '${widget.group.vehicleNo} — live map',
        ),
      ),
    );
  }

  Color _statusColor(String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'collected':
        return SupervisorTheme.success;
      case 'skipped':
      case 'collect later':
        return SupervisorTheme.warning;
      case 'missed':
      case 'not available':
        return SupervisorTheme.danger;
      default:
        return SupervisorTheme.mutedText;
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    return Container(
      decoration: BoxDecoration(
        color: SupervisorTheme.surfaceMuted,
        borderRadius: SupervisorTheme.cardRadius,
        border:
            Border.all(color: SupervisorTheme.hairline.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: SupervisorTheme.cardRadius,
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: widget.accentColor.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(Icons.local_shipping_rounded,
                        color: widget.accentColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.vehicleNo,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: SupervisorTheme.strongText,
                          ),
                        ),
                        Text(
                          '${group.events.length} collection point${group.events.length == 1 ? '' : 's'}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: SupervisorTheme.mutedText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    widget.fmt(group.totalKg),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: widget.accentColor,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: SupervisorTheme.mutedText,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1, color: SupervisorTheme.hairline),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final e in group.events)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: _statusColor(e.status),
                              shape: BoxShape.circle,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              (e.collectionPointName ?? '').isNotEmpty
                                  ? e.collectionPointName!
                                  : 'Collection point',
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: SupervisorTheme.strongText,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            e.wasteTypeName,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: SupervisorTheme.mutedText,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            widget.fmt(e.weightKg),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: SupervisorTheme.strongText,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _loadingTrips ? null : _viewTrip,
                      icon: _loadingTrips
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.alt_route_rounded, size: 16),
                      label: const Text('View Trip'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: SupervisorTheme.strongText,
                        side: const BorderSide(color: SupervisorTheme.hairline),
                        shape: RoundedRectangleBorder(
                          borderRadius: SupervisorTheme.chipRadius,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _openLiveMap,
                      icon: const Icon(Icons.map_rounded, size: 16),
                      label: const Text('Map'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: widget.accentColor,
                        side: BorderSide(
                            color: widget.accentColor.withValues(alpha: 0.4)),
                        shape: RoundedRectangleBorder(
                          borderRadius: SupervisorTheme.chipRadius,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
