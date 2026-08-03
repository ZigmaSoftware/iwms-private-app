import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:iwms_citizen_app/core/map/map_style.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/presentation/theme/supervisor_theme.dart';

/// Shows a single point (collection point or household) on the map — just
/// the location marker, no trip route/vehicle tracking.
class SupervisorPointLocationMapScreen extends StatefulWidget {
  const SupervisorPointLocationMapScreen({
    super.key,
    required this.title,
    required this.latitude,
    required this.longitude,
    this.subtitle,
  });

  final String title;
  final double latitude;
  final double longitude;
  final String? subtitle;

  @override
  State<SupervisorPointLocationMapScreen> createState() =>
      _SupervisorPointLocationMapScreenState();
}

class _SupervisorPointLocationMapScreenState
    extends State<SupervisorPointLocationMapScreen> {
  final MapController _map = MapController();
  MapStyle _mapStyle = kDefaultMapStyle;

  @override
  void initState() {
    super.initState();
    MapStylePrefs.load().then((style) {
      if (mounted) setState(() => _mapStyle = style);
    });
  }

  @override
  Widget build(BuildContext context) {
    final point = LatLng(widget.latitude, widget.longitude);
    final subtitle = widget.subtitle?.trim() ?? '';
    return Scaffold(
      backgroundColor: SupervisorTheme.background,
      appBar: AppBar(
        backgroundColor: SupervisorTheme.primary,
        foregroundColor: Colors.white,
        title: Text(widget.title),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: point,
              initialZoom: 16,
              minZoom: 6,
              maxZoom: 18,
            ),
            children: [
              buildMapTileLayer(_mapStyle),
              MarkerLayer(
                markers: [
                  Marker(
                    point: point,
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
                        Icons.location_on_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            right: 12,
            bottom: 84,
            child: MapStyleToggle(
              selected: _mapStyle,
              onChanged: (style) => setState(() => _mapStyle = style),
            ),
          ),
          Positioned(
            right: 12,
            bottom: 36,
            child: FloatingActionButton.small(
              heroTag: 'sup_point_location_recenter',
              backgroundColor: Colors.white,
              foregroundColor: SupervisorTheme.accent,
              onPressed: () => _map.move(point, 16),
              child: const Icon(Icons.center_focus_strong_rounded),
            ),
          ),
          if (subtitle.isNotEmpty)
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
                      Icons.location_on_outlined,
                      color: SupervisorTheme.accent,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        subtitle,
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
