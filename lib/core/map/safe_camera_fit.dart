import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Whether [point] is a coordinate the map camera can actually be placed at.
///
/// `latlong2`'s `LatLng` constructor is `const LatLng(this.latitude,
/// this.longitude)` — it validates nothing, so a NaN or out-of-range double
/// sails straight through and only fails much later, deep inside flutter_map:
/// `TileRangeCalculator._calculatePixelBounds` projects the camera centre and
/// calls `.floor()` on the result, which throws "Unsupported operation:
/// Infinity or NaN toInt". That throw comes from `_onTileUpdateEvent`, which
/// runs on EVERY map event, so a single bad centre doesn't fail once — it
/// bricks the map and repeats forever.
bool isValidLatLng(LatLng? point) {
  if (point == null) return false;
  final lat = point.latitude;
  final lng = point.longitude;
  return lat.isFinite &&
      lng.isFinite &&
      lat >= -90 &&
      lat <= 90 &&
      lng >= -180 &&
      lng <= 180;
}

/// Builds a [LatLng] only when both values are real, in-range coordinates,
/// and returns null otherwise so the caller can skip the record.
///
/// Use this instead of a bare `lat == null || lng == null` guard: a coordinate
/// that arrives as the string "NaN", or as a number that came out of a bad
/// division upstream, passes a null check but is not a location.
LatLng? tryLatLng(num? lat, num? lng, {String? debugSource}) {
  if (lat == null || lng == null) return null;
  final point = LatLng(lat.toDouble(), lng.toDouble());
  if (isValidLatLng(point)) return point;
  if (kDebugMode && debugSource != null) {
    debugPrint('⚠️ $debugSource: dropped invalid coordinate ($lat, $lng)');
  }
  return null;
}

/// Frames [controller] on [points], falling back to a plain pan-to-center
/// instead of crashing when the points don't make a real bounding box.
///
/// flutter_map's `CameraFit.bounds` computes the fitted zoom as
/// `screenSize / boundsSize` (see `FitBounds._getBoundsZoom`). When every
/// point in [points] sits at (or rounds to) the same coordinate — one stop,
/// a driver and destination that coincide, a batch of collection points that
/// all fell back to the same placeholder location — `boundsSize` is zero,
/// the ratio is `Infinity`, and flutter_map crashes the first time it tries
/// to round that zoom to a tile level: "Unsupported operation: Infinity or
/// NaN toInt". A non-finite raw coordinate (bad GPS fix, unparsed backend
/// value) hits the same crash even sooner, inside `LatLngBounds.fromPoints`
/// itself, so those are filtered out here too.
///
/// [fallbackZoom] is used whenever there's nothing to fit a real box to.
void safeFitBounds(
  MapController controller,
  List<LatLng> points, {
  required EdgeInsets padding,
  double fallbackZoom = 15,
  double? maxZoom,
}) {
  final finite = points.where(isValidLatLng).toList();
  if (finite.isEmpty) return;

  if (finite.length == 1) {
    controller.move(finite.first, fallbackZoom);
    return;
  }

  final bounds = LatLngBounds.fromPoints(finite);
  final isDegenerate = bounds.north == bounds.south && bounds.east == bounds.west;
  if (isDegenerate) {
    controller.move(finite.first, fallbackZoom);
    return;
  }

  controller.fitCamera(
    CameraFit.bounds(bounds: bounds, padding: padding, maxZoom: maxZoom),
  );
}

/// Moves the camera to [center], ignoring the request when [center] isn't a
/// real coordinate.
///
/// Every camera write must go through this (or [safeFitBounds]). Placing the
/// camera on a NaN centre doesn't throw at the call site — it throws on the
/// next tile update, and every one after that, so the stack trace points at
/// flutter_map's tile layer and says nothing about which of the app's
/// `move()` calls actually poisoned it.
void safeMove(
  MapController controller,
  LatLng center,
  double zoom, {
  String? debugSource,
}) {
  if (!isValidLatLng(center) || !zoom.isFinite) {
    if (kDebugMode) {
      debugPrint(
        '⚠️ ${debugSource ?? 'safeMove'}: refused camera move to '
        '($center, zoom $zoom)',
      );
    }
    return;
  }
  controller.move(center, zoom);
}
