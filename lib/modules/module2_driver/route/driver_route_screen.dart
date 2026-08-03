import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../core/api_config.dart';
import '../../../core/map/map_style.dart';
import 'driver_route_controller.dart';

class DriverRouteScreen extends StatelessWidget {
  const DriverRouteScreen({
    super.key,
    required this.nextHouseUrl,
  });

  final String nextHouseUrl;


  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
     create: (_) => DriverRouteController(
  djangoNextHouseUrl: nextHouseUrl,
)..start(),


      child: const _DriverRouteView(),
    );
  }
}

class _DriverRouteView extends StatelessWidget {
  const _DriverRouteView();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DriverRouteController>();
    final state = controller.state;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Navigation'),
        actions: [
          IconButton(
            onPressed: () => controller.start(),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh route',
          ),
        ],
      ),
      body: Stack(
        children: [
          if (state.driver != null)
            _RouteMap(
              driver: state.driver!,
              destination: state.destination,
              route: state.route,
            )
          else
            const Center(child: Text('Locating driver...')),
          if (state.loading)
            const Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: Center(child: CircularProgressIndicator()),
            ),
          if (state.error != null)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    state.error!,
                    style: TextStyle(color: Colors.red.shade800),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RouteMap extends StatefulWidget {
  const _RouteMap({
    required this.driver,
    required this.destination,
    required this.route,
  });

  final LatLng driver;
  final LatLng? destination;
  final List<LatLng> route;

  @override
  State<_RouteMap> createState() => _RouteMapState();
}

class _RouteMapState extends State<_RouteMap> {
  final MapController _mapController = MapController();
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
    final driver = widget.driver;
    final destination = widget.destination;
    final route = widget.route;
    final points = route.isNotEmpty
        ? route
        : [
            driver,
            if (destination != null) destination,
          ];
    final bounds = points.isNotEmpty
        ? LatLngBounds.fromPoints(points)
        : LatLngBounds.fromPoints([driver, driver]);

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: driver,
            initialZoom: 15,
            onMapReady: () {
              if (points.length > 1) {
                _mapController.fitCamera(
                  CameraFit.bounds(
                    bounds: bounds,
                    padding: const EdgeInsets.all(40),
                  ),
                );
              }
            },
          ),
          children: [
            buildMapTileLayer(_mapStyle),
            if (route.isNotEmpty)
              PolylineLayer(
                polylines: [
                  Polyline(
                    // Start the route from the driver's location.
                    points: route.first == driver ? route : [driver, ...route],
                    color: const Color.fromARGB(255, 0, 213, 255),
                    borderColor: Colors.black,
                    borderStrokeWidth: 2.0,
                    strokeWidth: 5.0,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                Marker(
                  width: 40,
                  height: 40,
                  point: driver,
                  child: const _MarkerDot(color: Colors.blue),
                ),
                if (destination != null)
                  Marker(
                    width: 40,
                    height: 40,
                    point: destination,
                    child: const _MarkerDot(color: Colors.red),
                  ),
              ],
            ),
          ],
        ),
        Positioned(
          top: 12,
          right: 12,
          child: MapStyleToggle(
            selected: _mapStyle,
            onChanged: (style) => setState(() => _mapStyle = style),
          ),
        ),
      ],
    );
  }
}

class _MarkerDot extends StatelessWidget {
  const _MarkerDot({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
    );
  }
}

/// Convenience helper to launch the screen with defaults.
void openDriverRoute(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => DriverRouteScreen(
        nextHouseUrl: ApiConfig.driverNextHouse,
      ),
    ),
  );
}
