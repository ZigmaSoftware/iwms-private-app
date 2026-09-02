import 'package:flutter_test/flutter_test.dart';

import 'package:iwms_private_app/modules/module2_driver/presentation/state/scale_reading.dart';

void main() {
  group('normalize', () {
    test('accepts a plain decimal weight', () {
      expect(ScaleReadingTracker.normalize('3.5').value, '3.5');
    });

    test('strips units and framing characters', () {
      expect(ScaleReadingTracker.normalize('  3.5 kg \r').value, '3.5');
      expect(ScaleReadingTracker.normalize('ST,GS,3.50kg').value, '3.50');
    });

    test('REJECTS zero — a scale returning to zero must never overwrite', () {
      expect(ScaleReadingTracker.normalize('0').isUsable, isFalse);
      expect(ScaleReadingTracker.normalize('0.00').isUsable, isFalse);
    });

    test('REJECTS a negative/tare reading instead of flipping its sign', () {
      // The old cleaner stripped '-' along with the units, turning this into
      // a valid 1.5 kg collection.
      expect(ScaleReadingTracker.normalize('-1.5').isUsable, isFalse);
      expect(ScaleReadingTracker.normalize('-1.5 kg').isUsable, isFalse);
    });

    test('rejects blank and junk lines', () {
      expect(ScaleReadingTracker.normalize('').isUsable, isFalse);
      expect(ScaleReadingTracker.normalize('   ').isUsable, isFalse);
      expect(ScaleReadingTracker.normalize('ERR').isUsable, isFalse);
      expect(ScaleReadingTracker.normalize('kg').isUsable, isFalse);
    });
  });

  group('settle detection', () {
    test('does not settle while the value is still wobbling', () {
      final t = ScaleReadingTracker(stableReadingsRequired: 4);
      for (final v in ['3.1', '3.4', '3.5', '3.6']) {
        t.add(v);
        expect(t.isSettled, isFalse);
      }
    });

    test('settles after the required identical readings', () {
      final t = ScaleReadingTracker(stableReadingsRequired: 4);
      t.add('3.5');
      t.add('3.5');
      t.add('3.5');
      expect(t.isSettled, isFalse, reason: '3 of 4');
      t.add('3.5');
      expect(t.isSettled, isTrue);
      expect(t.lastValue, '3.5');
    });

    test('a changed value restarts the run', () {
      final t = ScaleReadingTracker(stableReadingsRequired: 3);
      t.add('3.5');
      t.add('3.5');
      t.add('4.0');
      expect(t.isSettled, isFalse);
      expect(t.repeatCount, 1);
    });

    test('a dropout to zero between bags does not count as settled', () {
      final t = ScaleReadingTracker(stableReadingsRequired: 3);
      t.add('3.5');
      t.add('3.5');
      t.add('0'); // bag lifted off
      expect(t.isSettled, isFalse);
      expect(t.lastValue, isNull, reason: 'run was reset, not continued');
    });

    test('reset() forces the next value to settle on its own', () {
      final t = ScaleReadingTracker(stableReadingsRequired: 2);
      t.add('3.5');
      t.add('3.5');
      expect(t.isSettled, isTrue);
      // Moving to the next waste type while the load is still on the platform.
      t.reset();
      expect(t.isSettled, isFalse);
      t.add('3.5');
      expect(t.isSettled, isFalse, reason: 'must re-settle for the new card');
      t.add('3.5');
      expect(t.isSettled, isTrue);
    });
  });

  group('the reported bug: weight lost during photo capture', () {
    test(
        'readings streamed while the camera is open cannot produce a usable '
        'weight once the bag is lifted', () {
      final t = ScaleReadingTracker(stableReadingsRequired: 4);
      // Bag on the platform, settles at 3.5.
      for (var i = 0; i < 4; i++) {
        t.add('3.5');
      }
      expect(t.isSettled, isTrue);
      final latched = ScaleReadingTracker.parseWeight(t.lastValue!);
      expect(latched, 3.5);

      // Driver lifts the bag to shoot the photo — the scale streams zeros.
      for (var i = 0; i < 10; i++) {
        expect(t.add('0.00').isUsable, isFalse,
            reason: 'a zero must never be written into the field');
      }

      // The latched value is what gets saved, untouched by the zeros.
      expect(latched, 3.5);
    });
  });

  group('auto-capture release gate', () {
    test('same bag left on the platform cannot auto-commit a second row', () {
      final t = ScaleReadingTracker(stableReadingsRequired: 3);
      for (var i = 0; i < 3; i++) {
        t.add('3.5');
      }
      expect(t.isSettled, isTrue);

      // Row committed; auto-advance to the next waste type.
      t.armAfterCommit();
      expect(t.isAwaitingRelease, isTrue);

      // The bag is STILL on the scale, streaming the same value.
      for (var i = 0; i < 10; i++) {
        t.add('3.5');
      }
      expect(t.isSettled, isFalse,
          reason: 'must not re-fire while the platform is still loaded');
    });

    test('emptying the platform re-arms the next weight', () {
      final t = ScaleReadingTracker(stableReadingsRequired: 3);
      for (var i = 0; i < 3; i++) {
        t.add('3.5');
      }
      t.armAfterCommit();

      t.add('0');
      expect(t.isAwaitingRelease, isFalse, reason: 'platform cleared');

      for (var i = 0; i < 3; i++) {
        t.add('4.2');
      }
      expect(t.isSettled, isTrue);
      expect(t.lastValue, '4.2');
    });
  });

  group('parseWeight', () {
    test('rejects non-positive and unparseable values', () {
      expect(ScaleReadingTracker.parseWeight('0'), isNull);
      expect(ScaleReadingTracker.parseWeight('-2'), isNull);
      expect(ScaleReadingTracker.parseWeight(''), isNull);
      expect(ScaleReadingTracker.parseWeight('abc'), isNull);
    });

    test('accepts a typed manual weight', () {
      expect(ScaleReadingTracker.parseWeight('12.5'), 12.5);
      expect(ScaleReadingTracker.parseWeight(' 7 '), 7.0);
    });
  });
}
