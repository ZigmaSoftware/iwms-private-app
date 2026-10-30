import 'dart:async';

/// Fires when the backend refuses a driver write because the app is showing
/// an out-of-date trip: the trip was closed, or a Re-Trip / breakdown
/// approval moved the stop to a continuation trip. Trip screens listen and
/// reload so the driver lands on the current trip instead of retrying a
/// stale one.
class TripStaleSignal {
  TripStaleSignal._();

  /// Backend codes (`app/viewsets/operator_mobile/helpers.py`) meaning "your
  /// trip list is out of date".
  static const Set<String> codes = {'TRIP_CLOSED', 'STOP_CARRIED_OVER'};

  static final StreamController<String> _controller =
      StreamController<String>.broadcast();

  /// Emits the triggering code.
  static Stream<String> get events => _controller.stream;

  /// Checks an error response body and fires the signal if its `code` is one
  /// of [codes]. Returns whether it fired.
  static bool notifyIfStale(dynamic body) {
    final code = body is Map ? body['code']?.toString() : null;
    if (code == null || !codes.contains(code)) return false;
    _controller.add(code);
    return true;
  }
}
