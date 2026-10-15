import 'package:dio/dio.dart';

import 'package:iwms_private_app/core/api_config.dart';
import 'package:iwms_private_app/core/network/authorized_dio.dart';

/// How attendance face capture is configured, as declared by the server.
///
/// The backend chooses its face engine (CompreFace or InsightFace) in its own
/// `.env` via `FACE_RECOGNITION_PROVIDER`. The register/recognise API contract
/// is identical for both, so the app does not need this to *work* — it reads
/// it so a provider switch, a retuned threshold or an outage is reflected in
/// the UI without shipping a new build.
class FaceConfig {
  const FaceConfig({
    required this.provider,
    required this.ready,
    this.reason,
    this.guidance,
    this.minFacePixels = 0,
    this.registerSingleFaceRequired = true,
  });

  /// Which engine the server is running, e.g. `compreface` / `insightface`.
  /// Informational — the app calls the same endpoints either way.
  final String provider;

  /// False when the engine is down or misconfigured server-side. Lets the app
  /// say so before the user bothers taking a selfie.
  final bool ready;

  /// Why it isn't ready, when the server chose to say.
  final String? reason;

  /// Capture instruction to show the user, worded by the server so it can
  /// match whichever engine is active.
  final String? guidance;

  final int minFacePixels;
  final bool registerSingleFaceRequired;

  /// Assumed when the server cannot be reached or is an older build without
  /// the endpoint. Deliberately `ready: true` — attendance predates this
  /// endpoint and must keep working against a backend that doesn't serve it,
  /// so a missing config never blocks a punch. The server re-checks anyway.
  static const FaceConfig fallback = FaceConfig(
    provider: 'unknown',
    ready: true,
    guidance:
        'Face the camera in good light, with only your face in frame.',
  );

  factory FaceConfig.fromJson(Map<String, dynamic> json) {
    final capture = json['capture'];
    final captureMap =
        capture is Map ? Map<String, dynamic>.from(capture) : const <String, dynamic>{};
    return FaceConfig(
      provider: json['provider']?.toString() ?? 'unknown',
      // Absent `ready` means an older backend that predates the field; treat
      // it as usable rather than locking users out of attendance.
      ready: json['ready'] == null ? true : json['ready'] == true,
      reason: json['reason']?.toString(),
      guidance: captureMap['guidance']?.toString() ?? fallback.guidance,
      minFacePixels:
          int.tryParse(captureMap['min_face_pixels']?.toString() ?? '') ?? 0,
      registerSingleFaceRequired:
          captureMap['register_single_face_required'] != false,
    );
  }
}

/// Reads (and caches) the server's face configuration.
///
/// Cached for the life of the process because it changes only when someone
/// edits the backend `.env` and restarts it; [refresh] forces a re-read.
class FaceConfigRepository {
  FaceConfigRepository({Future<Dio> Function()? dioProvider})
      : _dioProvider = dioProvider ?? authorizedDio;

  final Future<Dio> Function() _dioProvider;

  static FaceConfig? _cached;
  static Future<FaceConfig>? _inFlight;

  /// The server's config, or [FaceConfig.fallback] if it can't be read.
  ///
  /// Never throws: attendance has to keep working against an older backend
  /// or a flaky connection, so any failure degrades to the permissive
  /// fallback rather than blocking the screen that asked.
  Future<FaceConfig> load({bool refresh = false}) {
    if (!refresh && _cached != null) return Future.value(_cached);

    // Share one request: the punch and register screens can both ask on the
    // same frame, and there is no reason to fetch this twice.
    final existing = _inFlight;
    if (!refresh && existing != null) return existing;

    final future = _fetch();
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
  }

  Future<FaceConfig> _fetch() async {
    try {
      final dio = await _dioProvider();
      final res = await dio.get(ApiConfig.attendanceFaceConfig);
      final data = res.data;
      if (data is Map) {
        final config = FaceConfig.fromJson(Map<String, dynamic>.from(data));
        _cached = config;
        return config;
      }
    } catch (_) {
      // Falls through to the fallback below — see the doc comment on `load`.
    }
    return FaceConfig.fallback;
  }

  /// Drops the cached value (used after a failed punch, so a provider that
  /// has just been switched or brought back up is picked up promptly).
  static void invalidate() {
    _cached = null;
    _inFlight = null;
  }
}
