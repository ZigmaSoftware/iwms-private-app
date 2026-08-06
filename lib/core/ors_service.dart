import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:iwms_private_app/core/api_config.dart';

/// OpenRouteService client for the driver map.
///
/// Every road-geometry request funnels through [_fetchDirections], which:
///
///  * asks ORS for the WHOLE multi-waypoint route in ONE call instead of one
///    call per segment (an 8-stop route used to cost 8 requests, now 1),
///  * caches results in memory, so the map rebuilding / the driver location
///    jittering does not re-buy the same geometry, and
///  * trips a cooldown breaker on 403/429 so a quota-exhausted key stops being
///    hammered dozens of times per screen.
///
/// ORS's free tier is small (2 000 directions/day, 40/min, and a much tighter
/// optimization budget), so request count is a correctness concern here, not a
/// micro-optimisation.
class ORSService {
  static String get _key => ApiConfig.orsApiKey;

  /// ORS refuses a driving-car route with more waypoints than this in one
  /// request, so longer routes are split and stitched.
  static const int _maxWaypointsPerRequest = 50;

  static const Duration _cacheTtl = Duration(minutes: 15);

  /// How long to stop calling ORS after it reports a quota/rate-limit error.
  /// Without this, one exhausted key produces a 403 for every segment of every
  /// map rebuild.
  static const Duration _quotaCooldown = Duration(minutes: 15);

  static final Map<String, _CachedRoute> _cache = <String, _CachedRoute>{};
  static DateTime? _blockedUntil;

  /// True while the breaker is open (quota exceeded / rate limited recently).
  static bool get isThrottled =>
      _blockedUntil != null && DateTime.now().isBefore(_blockedUntil!);

  /// Clears the cache and the cooldown — call after swapping in a new API key.
  static void reset() {
    _cache.clear();
    _blockedUntil = null;
  }

  // ---------------------------------------------------------------------------
  // SINGLE ROUTE (A → B)
  // ---------------------------------------------------------------------------
  static Future<List<LatLng>> fetchRoute(
    LatLng origin,
    LatLng destination,
  ) =>
      _fetchDirections([origin, destination]);

  // ---------------------------------------------------------------------------
  // MULTI-STOP WRAPPER (for backward compatibility)
  // ---------------------------------------------------------------------------
  static Future<List<LatLng>> fetchMultiRoute(
    List<List<double>> coords,
  ) async {
    if (coords.length < 2) {
      debugPrint('ORS MULTI: Not enough coordinates');
      return [];
    }

    final driver = LatLng(coords.first[1], coords.first[0]);
    final stops = coords.skip(1).map((c) => LatLng(c[1], c[0])).toList();

    return fetchOptimizedMultiRoute(driver: driver, stops: stops);
  }

  // ---------------------------------------------------------------------------
  // OPTIMIZED MULTI-STOP ROUTING
  // ---------------------------------------------------------------------------
  static Future<List<LatLng>> fetchOptimizedMultiRoute({
    required LatLng driver,
    required List<LatLng> stops,
  }) async {
    if (stops.isEmpty) return [];

    // With a single stop there is nothing to re-order: skip the (scarce)
    // optimization request entirely.
    if (stops.length == 1) {
      return _fetchDirections([driver, stops.first]);
    }

    final optimizedOrder = await _tryOptimization(driver, stops);
    final ordered = (optimizedOrder != null && optimizedOrder.isNotEmpty)
        ? optimizedOrder
        : stops;
    return _fetchDirections([driver, ...ordered]);
  }

  // ---------------------------------------------------------------------------
  // ROAD ROUTE FOR ORDERED STOPS (NO RE-SEQUENCING)
  // ---------------------------------------------------------------------------
  static Future<List<LatLng>> fetchRoadRoute({
    required LatLng driver,
    required List<LatLng> stops,
  }) async {
    if (stops.isEmpty) return [];
    return _fetchDirections([driver, ...stops]);
  }

  // ---------------------------------------------------------------------------
  // DIRECTIONS — the single road-geometry entry point
  // ---------------------------------------------------------------------------
  /// Road geometry through [waypoints] in the given order. Returns an empty
  /// list when ORS is unavailable, so callers keep their own fallback (a
  /// straight line, or no polyline at all) rather than being handed a fake
  /// route.
  static Future<List<LatLng>> _fetchDirections(List<LatLng> waypoints) async {
    if (waypoints.length < 2) return [];

    final key = _cacheKey('dir', waypoints);
    final cached = _cache[key];
    if (cached != null && !cached.isStale) return cached.points;

    // Long routes exceed ORS's per-request waypoint limit: request them in
    // chunks that share a waypoint, then stitch.
    final chunks = _chunkWaypoints(waypoints);
    final out = <LatLng>[];
    for (final chunk in chunks) {
      final seg = await _requestDirections(chunk);
      if (seg.isEmpty) return []; // partial geometry would draw a broken route
      if (out.isNotEmpty) seg.removeAt(0);
      out.addAll(seg);
    }

    _cache[key] = _CachedRoute(out);
    return out;
  }

  static List<List<LatLng>> _chunkWaypoints(List<LatLng> waypoints) {
    if (waypoints.length <= _maxWaypointsPerRequest) return [waypoints];
    final chunks = <List<LatLng>>[];
    var start = 0;
    while (start < waypoints.length - 1) {
      final end =
          math.min(start + _maxWaypointsPerRequest, waypoints.length);
      chunks.add(waypoints.sublist(start, end));
      start = end - 1; // overlap by one so the legs join
    }
    return chunks;
  }

  static Future<List<LatLng>> _requestDirections(List<LatLng> waypoints) async {
    final resp = await _post(
      'https://api.openrouteservice.org/v2/directions/driving-car/geojson',
      {
        'coordinates': [
          for (final p in waypoints) [p.longitude, p.latitude],
        ],
      },
      label: 'ROUTE',
    );
    if (resp == null) return [];

    try {
      return _extractDirectionsGeometry(jsonDecode(resp));
    } catch (e) {
      debugPrint('ORS ROUTE PARSE ERROR: $e');
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // OPTIMIZATION (stop re-sequencing)
  // ---------------------------------------------------------------------------
  static Future<List<LatLng>?> _tryOptimization(
    LatLng driver,
    List<LatLng> stops,
  ) async {
    final key = _cacheKey('opt', [driver, ...stops]);
    final cached = _cache[key];
    if (cached != null && !cached.isStale) {
      return cached.points.isEmpty ? null : cached.points;
    }

    final resp = await _post(
      'https://api.openrouteservice.org/optimization',
      {
        'vehicles': [
          {
            'id': 1,
            'profile': 'driving-car',
            'start': [driver.longitude, driver.latitude],
            'end': [driver.longitude, driver.latitude],
          }
        ],
        'jobs': [
          for (var i = 0; i < stops.length; i++)
            {
              'id': i + 1,
              'location': [stops[i].longitude, stops[i].latitude],
            },
        ],
      },
      label: 'OPT',
    );
    if (resp == null) return null;

    try {
      final json = jsonDecode(resp);
      final steps = json['routes']?[0]?['steps'];
      if (steps is! List || steps.isEmpty) {
        debugPrint('ORS OPT: Invalid or empty steps');
        return null;
      }

      final ordered = <LatLng>[];
      for (final s in steps) {
        if (s['type'] != 'job') continue;
        final loc = s['location'];
        if (loc is List && loc.length == 2) {
          ordered.add(
            LatLng((loc[1] as num).toDouble(), (loc[0] as num).toDouble()),
          );
        }
      }
      if (ordered.isEmpty) return null;

      // Cached so a map rebuild reuses the order instead of spending another
      // optimization request (the scarcest ORS budget of the three).
      _cache[key] = _CachedRoute(ordered);
      return ordered;
    } catch (e) {
      debugPrint('ORS OPT PARSE ERROR: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // HTTP with quota breaker
  // ---------------------------------------------------------------------------
  /// POSTs [body] to [url], returning the response body, or null on any
  /// failure. A 403/429 opens the cooldown breaker so the rest of this screen's
  /// requests short-circuit instead of piling up more rejected calls.
  static Future<String?> _post(
    String url,
    Map<String, dynamic> body, {
    required String label,
  }) async {
    if (isThrottled) return null;

    try {
      final resp = await http
          .post(
            Uri.parse(url),
            headers: {
              'Authorization': _key,
              'Content-Type': 'application/json',
              'Accept': 'application/json, application/geo+json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));

      if (resp.statusCode == 200) return resp.body;

      if (resp.statusCode == 403 || resp.statusCode == 429) {
        _blockedUntil = DateTime.now().add(_quotaCooldown);
        debugPrint(
          'ORS $label ${resp.statusCode}: quota/rate limit hit — pausing ORS '
          'calls for ${_quotaCooldown.inMinutes} min. ${resp.body}',
        );
        return null;
      }

      debugPrint('ORS $label ERROR ${resp.statusCode}: ${resp.body}');
      return null;
    } catch (e) {
      debugPrint('ORS $label EXCEPTION: $e');
      return null;
    }
  }

  static String _cacheKey(String kind, List<LatLng> points) {
    // 5 decimal places ≈ 1 m: enough to dedupe GPS jitter that would otherwise
    // miss the cache on every location tick.
    final parts = points
        .map((p) => '${p.latitude.toStringAsFixed(5)},'
            '${p.longitude.toStringAsFixed(5)}')
        .join(';');
    return '$kind|$parts';
  }

  // ---------------------------------------------------------------------------
  // EXTRACT GEOMETRY FROM ORS RESPONSE
  // ---------------------------------------------------------------------------
  static List<LatLng> _extractDirectionsGeometry(dynamic json) {
    List<LatLng> fromCoords(List coords) => coords
        .whereType<List>()
        .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
        .toList();

    try {
      // GeoJSON shape: { features: [ { geometry: { coordinates: [...] } } ] }
      final features = json['features'];
      if (features is List && features.isNotEmpty) {
        final coords = features[0]?['geometry']?['coordinates'];
        if (coords is List && coords.isNotEmpty) return fromCoords(coords);
      }

      // JSON shape: { routes: [ { geometry: <encoded polyline | object> } ] }
      final routes = json['routes'];
      if (routes is List && routes.isNotEmpty) {
        final geometry = routes[0]?['geometry'];
        if (geometry is String) return decodePolyline(geometry);
        if (geometry is Map) {
          final coords = geometry['coordinates'];
          if (coords is List && coords.isNotEmpty) return fromCoords(coords);
        }
      }

      debugPrint('ORS ROUTE: no geometry in response');
      return [];
    } catch (e) {
      debugPrint('ORS GEOMETRY PARSE ERROR: $e');
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // POLYLINE DECODER (for encoded geometry strings)
  // ---------------------------------------------------------------------------
  static List<LatLng> decodePolyline(String encoded) {
    final List<LatLng> points = [];
    int index = 0;
    int lat = 0;
    int lng = 0;

    while (index < encoded.length) {
      int b;
      int shift = 0;
      int result = 0;

      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);

      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;

      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);

      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }

    return points;
  }

  // ---------------------------------------------------------------------------
  // BEARING CALCULATION
  // ---------------------------------------------------------------------------
  static double calculateBearing(LatLng from, LatLng to) {
    final lat1 = _degToRad(from.latitude);
    final lat2 = _degToRad(to.latitude);
    final dLon = _degToRad(to.longitude - from.longitude);

    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    return (_radToDeg(math.atan2(y, x)) + 360) % 360;
  }

  static double _degToRad(double d) => d * math.pi / 180;
  static double _radToDeg(double r) => r * 180 / math.pi;
}

class _CachedRoute {
  _CachedRoute(this.points) : fetchedAt = DateTime.now();

  final List<LatLng> points;
  final DateTime fetchedAt;

  bool get isStale =>
      DateTime.now().difference(fetchedAt) > ORSService._cacheTtl;
}
