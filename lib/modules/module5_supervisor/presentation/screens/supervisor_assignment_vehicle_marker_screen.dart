import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:iwms_private_app/core/api_config.dart';
import 'package:iwms_private_app/core/map/map_style.dart';
import 'package:iwms_private_app/core/network/authorized_dio.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/theme/supervisor_theme.dart';

class SupervisorAssignmentVehicleMarkerScreen extends StatefulWidget {
  const SupervisorAssignmentVehicleMarkerScreen({
    super.key,
    required this.assignmentId,
    this.title = 'Vehicle location',
  });

  final String assignmentId;
  final String title;

  @override
  State<SupervisorAssignmentVehicleMarkerScreen> createState() =>
      _SupervisorAssignmentVehicleMarkerScreenState();
}

class _SupervisorAssignmentVehicleMarkerScreenState
    extends State<SupervisorAssignmentVehicleMarkerScreen> {
  final MapController _map = MapController();

  bool _loading = true;
  String? _error;
  LatLng? _point;
  String? _recordedAt;
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
      final response = await dio.get(
        ApiConfig.tripRouteGeometry,
        queryParameters: {'trip_assignment_id': widget.assignmentId},
      );
      final data = response.data;
      if (data is! Map) {
        throw Exception('Invalid response');
      }
      final vehicleTracking = data['vehicle_tracking'];
      final currentLocation =
          vehicleTracking is Map ? vehicleTracking['current_location'] : null;
      if (currentLocation is! Map) {
        throw Exception('Vehicle location unavailable');
      }
      final lat = _toDouble(currentLocation['latitude']);
      final lng = _toDouble(currentLocation['longitude']);
      if (lat == null || lng == null || lat == 0 || lng == 0) {
        throw Exception('Vehicle location unavailable');
      }
      if (!mounted) return;
      setState(() {
        _point = LatLng(lat, lng);
        _recordedAt = currentLocation['recorded_at']?.toString();
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_point != null) _map.move(_point!, 16);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No assignment marker available';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final center = _point ?? const LatLng(11.0, 78.0);
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
                if (_point != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _point!,
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
              bottom: 132,
              child: MapStyleToggle(
                selected: _mapStyle,
                onChanged: (style) => setState(() => _mapStyle = style),
              ),
            ),
          if (!_loading && _error == null)
            Positioned(
              right: 12,
              bottom: 84,
              child: FloatingActionButton.small(
                heroTag: 'sup_assignment_marker_recenter',
                backgroundColor: Colors.white,
                foregroundColor: SupervisorTheme.accent,
                onPressed: () {
                  if (_point != null) _map.move(_point!, 16);
                },
                child: const Icon(Icons.center_focus_strong_rounded),
              ),
            ),
          if (!_loading && _error == null && _point != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 20,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: SupervisorTheme.hairline.withValues(alpha: 0.45),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.my_location_rounded,
                      color: SupervisorTheme.accent,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _recordedAt?.isNotEmpty == true
                            ? 'Recorded at $_recordedAt'
                            : 'Current assignment marker',
                        style: const TextStyle(
                          color: SupervisorTheme.strongText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
