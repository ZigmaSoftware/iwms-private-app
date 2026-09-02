/// Interpreting the raw line stream from a Bluetooth weigh scale.
///
/// Pulled out of `household_collect_sheet.dart` so the rules that decide
/// "is this a real weight?" and "has the platform settled?" can be tested
/// without standing up the whole collect sheet, its DI and a live socket.
library;

/// A single normalized weight, or the reason the line was rejected.
class ScaleReading {
  const ScaleReading._(this.value, this.rejected);

  /// The cleaned numeric text, e.g. `"3.5"`. Null when [rejected].
  final String? value;

  /// True when the line carried no usable positive weight.
  final bool rejected;

  bool get isUsable => !rejected;

  static const ScaleReading _reject = ScaleReading._(null, true);
}

/// Normalizes raw scale lines and tracks when the reading has settled.
///
/// A scale streams several readings a second and the number wobbles while the
/// load settles, so a weight is only treated as final once the SAME value has
/// repeated [stableReadingsRequired] times.
class ScaleReadingTracker {
  ScaleReadingTracker({this.stableReadingsRequired = 4});

  /// How many identical consecutive readings mean "settled". At typical
  /// HC-05 output rates 4 is roughly half a second of a steady platform.
  final int stableReadingsRequired;

  String? _lastValue;
  int _repeatCount = 0;
  bool _awaitingRelease = false;

  /// The value currently repeating, or null when the last line was rejected.
  String? get lastValue => _lastValue;

  /// How many times [lastValue] has arrived in a row.
  int get repeatCount => _repeatCount;

  /// True once the current value has held steady long enough to commit.
  ///
  /// Stays false while [isAwaitingRelease] — see [armAfterCommit].
  bool get isSettled =>
      !_awaitingRelease &&
      _lastValue != null &&
      _repeatCount >= stableReadingsRequired;

  /// True while the platform must be emptied before another weight can settle.
  bool get isAwaitingRelease => _awaitingRelease;

  /// Call after a weight has been committed from a settled reading.
  ///
  /// Blocks the next settle until the platform actually clears (a zero /
  /// rejected reading). Without this, auto-advancing to the next waste type
  /// with the SAME bag still sitting on the scale would re-settle within half
  /// a second and silently commit a second row at the same weight.
  void armAfterCommit() {
    _awaitingRelease = true;
    _lastValue = null;
    _repeatCount = 0;
  }

  /// Forget the current run, so the next value must settle on its own.
  ///
  /// Called whenever the target card changes: a platform still holding the
  /// previous load already looks "settled", and without this the next card
  /// would instantly lock in the old weight.
  void reset() {
    _lastValue = null;
    _repeatCount = 0;
    _awaitingRelease = false;
  }

  /// Clean one raw line into a usable weight, or reject it.
  ///
  /// Rejected: blank lines, junk, zero, and NEGATIVE values. The sign check
  /// happens before punctuation is stripped — stripping first turned a tare
  /// reading of `-1.5` into a perfectly valid `1.5` kg collection.
  static ScaleReading normalize(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return ScaleReading._reject;
    if (trimmed.startsWith('-')) return ScaleReading._reject;

    final cleaned = trimmed.replaceAll(RegExp(r'[^0-9.]'), '');
    if (cleaned.isEmpty) return ScaleReading._reject;
    if (parseWeight(cleaned) == null) return ScaleReading._reject;
    return ScaleReading._(cleaned, false);
  }

  /// The single definition of a usable weight, shared by validation, the
  /// settle check and the commit path so they can never disagree.
  static double? parseWeight(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    if (value == null || value <= 0) return null;
    return value;
  }

  /// Feed one raw line in. Returns the normalized reading; callers check
  /// [isSettled] afterwards to decide whether to lock the weight in.
  ///
  /// A rejected line resets the run rather than counting toward it, so a
  /// scale dropping to zero between two bags cannot be mistaken for a settled
  /// weight.
  ScaleReading add(String raw) {
    final reading = normalize(raw);
    if (reading.rejected) {
      // An empty platform is exactly the release signal armAfterCommit waits
      // for, so clear that latch here rather than in reset().
      _awaitingRelease = false;
      _lastValue = null;
      _repeatCount = 0;
      return reading;
    }
    if (reading.value == _lastValue) {
      _repeatCount++;
    } else {
      _lastValue = reading.value;
      _repeatCount = 1;
    }
    return reading;
  }
}
