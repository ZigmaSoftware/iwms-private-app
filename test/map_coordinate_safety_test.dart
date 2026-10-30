import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:iwms_private_app/core/map/safe_camera_fit.dart';

/// A non-finite coordinate reaching the map camera doesn't fail where it is
/// introduced — it fails later and forever, inside flutter_map's tile layer
/// ("Unsupported operation: Infinity or NaN toInt"), on every map event. These
/// pin down the guard that keeps such a value from ever getting that far.
void main() {
  group('isValidLatLng', () {
    test('accepts real coordinates, including the extremes', () {
      expect(isValidLatLng(const LatLng(28.4879, 77.5025)), isTrue);
      expect(isValidLatLng(const LatLng(0, 0)), isTrue);
      expect(isValidLatLng(const LatLng(-90, -180)), isTrue);
      expect(isValidLatLng(const LatLng(90, 180)), isTrue);
    });

    test('rejects NaN and infinities', () {
      expect(isValidLatLng(LatLng(double.nan, 77.5)), isFalse);
      expect(isValidLatLng(LatLng(28.4, double.nan)), isFalse);
      expect(isValidLatLng(LatLng(double.infinity, 77.5)), isFalse);
      expect(isValidLatLng(LatLng(28.4, double.negativeInfinity)), isFalse);
    });

    test('rejects out-of-range values latlong2 would happily construct', () {
      // `const LatLng(lat, lng)` validates nothing, so these are constructible
      // and only blow up once the projection tries to use them.
      expect(isValidLatLng(const LatLng(91, 0)), isFalse);
      expect(isValidLatLng(const LatLng(0, 181)), isFalse);
    });

    test('rejects null', () {
      expect(isValidLatLng(null), isFalse);
    });
  });

  group('tryLatLng', () {
    test('builds a point from real values', () {
      expect(tryLatLng(28.4879, 77.5025), const LatLng(28.4879, 77.5025));
    });

    test('returns null when either value is missing', () {
      expect(tryLatLng(null, 77.5), isNull);
      expect(tryLatLng(28.4, null), isNull);
      expect(tryLatLng(null, null), isNull);
    });

    test('returns null for non-finite values that survive a null check', () {
      expect(tryLatLng(double.nan, 77.5), isNull);
      expect(tryLatLng(28.4, double.infinity), isNull);
    });

    test('rejects the NaN that double.tryParse yields for "NaN"', () {
      // The trap the reroute-stop parser fell into: tryParse('NaN') is not
      // null, it is double.nan, so `lat == null` lets it straight through.
      final parsed = double.tryParse('NaN');
      expect(parsed, isNotNull);
      expect(parsed!.isNaN, isTrue);
      expect(tryLatLng(parsed, 77.5), isNull);
    });

    test('accepts integer inputs', () {
      expect(tryLatLng(28, 77), const LatLng(28, 77));
    });
  });
}
