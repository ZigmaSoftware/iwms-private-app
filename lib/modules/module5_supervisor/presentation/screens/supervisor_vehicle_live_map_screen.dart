import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:iwms_citizen_app/core/api_config.dart';
import 'package:iwms_citizen_app/core/map/map_style.dart';
import 'package:iwms_citizen_app/core/network/authorized_dio.dart';
import 'package:iwms_citizen_app/data/models/operator_trip_models.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/presentation/theme/supervisor_theme.dart';
import 'package:iwms_citizen_app/shared/widgets/crew_avatar_stack.dart';

class SupervisorVehicleLiveMapScreen extends StatefulWidget {
  const SupervisorVehicleLiveMapScreen({
    super.key,
    required this.vehicleNo,
    this.title = 'Vehicle map',
    this.crew,
    this.driverName = '',
    this.operatorName = '',
    this.collectedStops = 0,
    this.totalStops = 0,
  });

  final String vehicleNo;
  final String title;
  final OperatorTripCrew? crew;
  final String driverName;
  final String operatorName;
  final int collectedStops;
  final int totalStops;

  @override
  State<SupervisorVehicleLiveMapScreen> createState() =>
      _SupervisorVehicleLiveMapScreenState();
}

class _SupervisorVehicleLiveMapScreenState
    extends State<SupervisorVehicleLiveMapScreen> {
  final MapController _map = MapController();

  bool _loading = true;
  String? _error;
  LatLng? _vehiclePoint;
  String _status = '';
  MapStyle _mapStyle = kDefaultMapStyle;

  @override
  void initState() {
    super.initState();
    MapStylePrefs.load().then((style) {
      if (mounted) setState(() => _mapStyle = style);
    });
    _load();
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dio = await authorizedDio();
      final response = await dio.get(ApiConfig.vehicleLiveApi);
      final raw = response.data;
      final list = raw is List ? raw : const [];
      Map? match;
      for (final item in list) {
        if (item is! Map) continue;
        final vehicleNo = item['vehicle_no']?.toString() ??
            item['VEHICLE_NO']?.toString() ??
            item['regNo']?.toString();
        if ((vehicleNo ?? '').trim().toLowerCase() ==
            widget.vehicleNo.trim().toLowerCase()) {
          match = item;
          break;
        }
      }
      if (match == null) {
        throw Exception('Vehicle not found');
      }
      final lat = _toDouble(match['lat'] ?? match['LAT'] ?? match['latitude']);
      final lng = _toDouble(match['lng'] ?? match['LON'] ?? match['longitude']);
      if (lat == null || lng == null || lat == 0 || lng == 0) {
        throw Exception('Vehicle location unavailable');
      }
      final ignition = match['ignitionStatus']?.toString().toLowerCase();
      final fallback = match['status']?.toString().toLowerCase();
      final speed = _toDouble(match['speed']) ?? 0;
      var status = 'No Data';
      if (ignition == 'off' || fallback == 'off') {
        status = 'Parked';
      } else if (ignition == 'on' && speed > 0) {
        status = 'Running';
      } else if (ignition == 'on') {
        status = 'Idle';
      } else if (speed > 0) {
        status = 'Running';
      } else if (speed == 0) {
        status = 'Parked';
      }
      if (!mounted) return;
      setState(() {
        _vehiclePoint = LatLng(lat, lng);
        _status = status;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_vehiclePoint != null) {
          _map.move(_vehiclePoint!, 16);
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to locate vehicle';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final center = _vehiclePoint ?? const LatLng(11.0, 78.0);
    return Scaffold(
      backgroundColor: SupervisorTheme.background,
      appBar: AppBar(
        backgroundColor: SupervisorTheme.primary,
        foregroundColor: Colors.white,
        title: Text(widget.title),
      ),
      body: Stack(
        children: [
          if (_loading)
            const Center(
              child: CircularProgressIndicator(color: SupervisorTheme.accent),
            )
          else if (_error != null)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.location_off_rounded,
                    color: SupervisorTheme.danger,
                    size: 42,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: SupervisorTheme.mutedText),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _load,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SupervisorTheme.accent,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          else
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 16,
                minZoom: 6,
                maxZoom: 18,
              ),
              children: [
                buildMapTileLayer(_mapStyle),
                if (_vehiclePoint != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _vehiclePoint!,
                        width: 52,
                        height: 52,
                        child: Container(
                          decoration: BoxDecoration(
                            color: SupervisorTheme.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                            boxShadow: SupervisorTheme.softShadow,
                          ),
                          child: const Icon(
                            Icons.local_shipping_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          if (!_loading && _error == null)
            Positioned(
              right: 12,
              bottom: 240,
              child: MapStyleToggle(
                selected: _mapStyle,
                onChanged: (style) => setState(() => _mapStyle = style),
              ),
            ),
          if (!_loading && _error == null)
            Positioned(
              right: 12,
              bottom: 192,
              child: FloatingActionButton.small(
                heroTag: 'sup_vehicle_live_recenter',
                backgroundColor: Colors.white,
                foregroundColor: SupervisorTheme.accent,
                onPressed: () {
                  if (_vehiclePoint != null) _map.move(_vehiclePoint!, 16);
                },
                child: const Icon(Icons.center_focus_strong_rounded),
              ),
            ),
          if (!_loading && _error == null)
            _VehicleCrewDrawer(
              vehicleNo: widget.vehicleNo,
              status: _status,
              crew: widget.crew,
              driverName: widget.driverName,
              operatorName: widget.operatorName,
              collectedStops: widget.collectedStops,
              totalStops: widget.totalStops,
            ),
        ],
      ),
    );
  }
}

class _VehicleCrewDrawer extends StatelessWidget {
  const _VehicleCrewDrawer({
    required this.vehicleNo,
    required this.status,
    required this.crew,
    required this.driverName,
    required this.operatorName,
    required this.collectedStops,
    required this.totalStops,
  });

  final String vehicleNo;
  final String status;
  final OperatorTripCrew? crew;
  final String driverName;
  final String operatorName;
  final int collectedStops;
  final int totalStops;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (status.toLowerCase()) {
      'running' => SupervisorTheme.success,
      'idle' => SupervisorTheme.warning,
      _ => SupervisorTheme.info,
    };

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        padding: EdgeInsets.fromLTRB(
          18,
          14,
          18,
          18 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        decoration: BoxDecoration(
          color: SupervisorTheme.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: SupervisorTheme.elevatedShadow,
          border: Border.all(
            color: SupervisorTheme.hairline.withValues(alpha: 0.45),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: SupervisorTheme.hairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    vehicleNo,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: SupervisorTheme.strongText,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (crew != null &&
                (crew!.driver != null ||
                    crew!.operator != null ||
                    crew!.extraOperators.isNotEmpty)) ...[
              Row(
                children: [
                  CrewAvatarStack(
                    crew: crew!,
                    size: 28,
                    overlap: 15,
                    borderColor: SupervisorTheme.surface,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      [
                        if (driverName.isNotEmpty) driverName,
                        if (operatorName.isNotEmpty) operatorName,
                      ].join('  •  '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: SupervisorTheme.strongText,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                _InfoPill(
                  icon: Icons.check_circle_outline_rounded,
                  label: '$collectedStops/$totalStops stops',
                  color: SupervisorTheme.info,
                ),
                const SizedBox(width: 8),
                _InfoPill(
                  icon: Icons.route_rounded,
                  label: '${(totalStops - collectedStops).clamp(0, totalStops)} left',
                  color: SupervisorTheme.warning,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
