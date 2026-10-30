import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart' as permissions;

enum CollectionPhotoProofRecovery { none, appSettings, locationSettings }

class CollectionPhotoProofException implements Exception {
  const CollectionPhotoProofException(
    this.message, {
    this.recovery = CollectionPhotoProofRecovery.none,
  });

  final String message;
  final CollectionPhotoProofRecovery recovery;

  @override
  String toString() => message;
}

class CollectionPhotoProof {
  const CollectionPhotoProof({
    required this.file,
    required this.latitude,
    required this.longitude,
    required this.accuracyMetres,
    required this.capturedAt,
    this.address,
  });

  final File file;
  final double latitude;
  final double longitude;
  final double accuracyMetres;
  final DateTime capturedAt;
  final String? address;
}

class CollectionPhotoProofService {
  const CollectionPhotoProofService();

  Future<void> ensureCaptureReady() async {
    var camera = await permissions.Permission.camera.status;
    if (camera.isDenied) {
      camera = await permissions.Permission.camera.request();
    }
    if (!camera.isGranted) {
      throw const CollectionPhotoProofException(
        'Camera permission is required to capture operational evidence.',
        recovery: CollectionPhotoProofRecovery.appSettings,
      );
    }
    await ensureLocationReady();
  }

  /// Run before presenting the camera. This keeps iOS from taking a photo and
  /// only then discovering that Location permission must be changed in
  /// Settings.
  Future<void> ensureLocationReady() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const CollectionPhotoProofException(
        'Turn on Location Services to capture collection proof.',
        recovery: CollectionPhotoProofRecovery.locationSettings,
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const CollectionPhotoProofException(
        'Location permission is required for geotagged collection photos.',
        recovery: CollectionPhotoProofRecovery.appSettings,
      );
    }
    if (permission == LocationPermission.deniedForever) {
      throw const CollectionPhotoProofException(
        'Enable location permission in Settings to capture collection proof.',
        recovery: CollectionPhotoProofRecovery.appSettings,
      );
    }
  }

  /// Captures a fresh GPS fix and burns the collection evidence into the
  /// pixels. Reverse geocoding is deliberately best-effort: coordinates are
  /// the authoritative proof and must still work without network access.
  Future<CollectionPhotoProof> stamp({
    required File source,
    required String wasteType,
    required String stopLabel,
    String? assignmentId,
    double? weightKg,
  }) async {
    final position = await _freshPosition();
    final capturedAt = DateTime.now();
    final address = await _reverseGeocode(position);
    final outputPath = p.join(
      source.parent.path,
      'collection_proof_${capturedAt.microsecondsSinceEpoch}.jpg',
    );

    await stampWithMetadata(
      sourcePath: source.path,
      outputPath: outputPath,
      wasteType: wasteType,
      stopLabel: stopLabel,
      assignmentId: assignmentId,
      weightKg: weightKg,
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMetres: position.accuracy,
      capturedAt: capturedAt,
      address: address,
    );
    try {
      if (source.path != outputPath) await source.delete();
    } catch (_) {
      // The stamped proof is complete; source-cache cleanup is best-effort.
    }

    return CollectionPhotoProof(
      file: File(outputPath),
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMetres: position.accuracy,
      capturedAt: capturedAt,
      address: address,
    );
  }

  /// Public for deterministic tests and for future import/gallery workflows.
  static Future<void> stampWithMetadata({
    required String sourcePath,
    required String outputPath,
    required String wasteType,
    required String stopLabel,
    required double latitude,
    required double longitude,
    required double accuracyMetres,
    required DateTime capturedAt,
    String? assignmentId,
    double? weightKg,
    String? address,
  }) async {
    await Isolate.run(() {
      final bytes = File(sourcePath).readAsBytesSync();
      var image = img.decodeImage(bytes);
      if (image == null) {
        throw const CollectionPhotoProofException(
          'The captured image could not be processed. Please retake it.',
        );
      }

      image = img.bakeOrientation(image);
      if (image.width > 1600 || image.height > 1600) {
        image = img.copyResize(
          image,
          width: image.width >= image.height ? 1600 : null,
          height: image.height > image.width ? 1600 : null,
          interpolation: img.Interpolation.average,
        );
      }

      _drawProof(
        image,
        wasteType: wasteType,
        stopLabel: stopLabel,
        assignmentId: assignmentId,
        weightKg: weightKg,
        latitude: latitude,
        longitude: longitude,
        accuracyMetres: accuracyMetres,
        capturedAt: capturedAt,
        address: address,
      );
      File(outputPath).writeAsBytesSync(img.encodeJpg(image, quality: 84));
    });
  }

  Future<Position> _freshPosition() async {
    await ensureLocationReady();

    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } on TimeoutException {
      final cached = await Geolocator.getLastKnownPosition();
      final age = cached == null
          ? null
          : DateTime.now().difference(cached.timestamp).abs();
      if (cached != null &&
          age != null &&
          age <= const Duration(minutes: 5) &&
          cached.accuracy <= 100) {
        return cached;
      }
      throw const CollectionPhotoProofException(
        'Could not get an accurate GPS fix. Move outdoors and try again.',
      );
    } catch (_) {
      throw const CollectionPhotoProofException(
        'Could not read the current location. Check GPS and try again.',
      );
    }
  }

  Future<String?> _reverseGeocode(Position position) async {
    try {
      final places = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      ).timeout(const Duration(seconds: 4));
      if (places.isEmpty) return null;
      final place = places.first;
      final parts = <String>[
        place.street ?? '',
        place.subLocality ?? '',
        place.locality ?? '',
        place.administrativeArea ?? '',
        place.postalCode ?? '',
      ].map((value) => value.trim()).where((value) => value.isNotEmpty);
      final unique = <String>[];
      for (final part in parts) {
        if (!unique.any((value) => value.toLowerCase() == part.toLowerCase())) {
          unique.add(part);
        }
      }
      return unique.isEmpty ? null : unique.join(', ');
    } catch (_) {
      return null;
    }
  }

  static void _drawProof(
    img.Image image, {
    required String wasteType,
    required String stopLabel,
    required double latitude,
    required double longitude,
    required double accuracyMetres,
    required DateTime capturedAt,
    String? assignmentId,
    double? weightKg,
    String? address,
  }) {
    final wide = image.width >= 1000;
    final headingFont = wide ? img.arial48 : img.arial24;
    final bodyFont = wide ? img.arial24 : img.arial14;
    final margin = wide ? 34 : 20;
    final gap = wide ? 12 : 7;
    final radius = wide ? 22 : 14;
    final bodyLine = bodyFont.lineHeight + gap;
    final headingLine = headingFont.lineHeight + gap;
    final addressText = _ascii(address?.trim() ?? '');
    final lineCount = addressText.isEmpty ? 3 : 4;
    final panelHeight = margin + headingLine + (bodyLine * lineCount) + margin;
    final panelTop =
        (image.height - panelHeight - margin).clamp(0, image.height);

    final dark = img.ColorRgba8(11, 22, 18, 220);
    final white = img.ColorRgb8(255, 255, 255);
    final muted = img.ColorRgb8(211, 225, 217);
    final accent = _accentFor(wasteType);

    img.fillRect(
      image,
      x1: margin,
      y1: panelTop,
      x2: image.width - margin,
      y2: image.height - margin,
      radius: radius,
      color: dark,
    );
    img.fillRect(
      image,
      x1: margin,
      y1: panelTop,
      x2: margin + (wide ? 9 : 6),
      y2: image.height - margin,
      radius: radius,
      color: accent,
    );

    final waste = _fit(
      _ascii(wasteType).toUpperCase(),
      headingFont,
      image.width - (margin * 4),
    );
    final pillPadX = wide ? 24 : 14;
    final pillPadY = wide ? 14 : 9;
    final pillWidth = _textWidth(waste, headingFont) + (pillPadX * 2);
    final pillHeight = headingFont.lineHeight + (pillPadY * 2);
    final pillX = image.width - margin - pillWidth;
    img.fillRect(
      image,
      x1: pillX,
      y1: margin,
      x2: image.width - margin,
      y2: margin + pillHeight,
      radius: pillHeight ~/ 2,
      color: accent,
    );
    img.drawString(
      image,
      waste,
      font: headingFont,
      x: pillX + pillPadX,
      y: margin + pillPadY,
      color: img.ColorRgb8(7, 20, 15),
    );

    final textX = margin + (wide ? 28 : 18);
    final maxWidth = image.width - textX - (margin * 2);
    var y = panelTop + (wide ? 24 : 14);
    img.drawString(
      image,
      'IWMS COLLECTION PROOF',
      font: headingFont,
      x: textX,
      y: y,
      color: white,
    );
    y += headingLine;

    final contextBits = <String>[
      'Stop: ${_ascii(stopLabel)}',
      if (assignmentId != null && assignmentId.trim().isNotEmpty)
        'Trip: ${_ascii(assignmentId.trim())}',
      if (weightKg != null) '${weightKg.toStringAsFixed(2)} kg',
    ];
    _drawLine(
        image, contextBits.join(' | '), bodyFont, textX, y, maxWidth, white);
    y += bodyLine;
    _drawLine(
      image,
      '${DateFormat('dd MMM yyyy | hh:mm:ss a').format(capturedAt)} ${capturedAt.timeZoneName}',
      bodyFont,
      textX,
      y,
      maxWidth,
      muted,
    );
    y += bodyLine;
    _drawLine(
      image,
      'GPS ${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)} | +/-${accuracyMetres.round()} m',
      bodyFont,
      textX,
      y,
      maxWidth,
      muted,
    );
    if (addressText.isNotEmpty) {
      y += bodyLine;
      _drawLine(
        image,
        'Address: $addressText',
        bodyFont,
        textX,
        y,
        maxWidth,
        muted,
      );
    }
  }

  static img.Color _accentFor(String wasteType) {
    final value = wasteType.toLowerCase();
    if (value.contains('wet') || value.contains('organic')) {
      return img.ColorRgb8(52, 211, 153);
    }
    if (value.contains('dry') || value.contains('recycl')) {
      return img.ColorRgb8(251, 191, 36);
    }
    if (value.contains('hazard') || value.contains('sanitary')) {
      return img.ColorRgb8(248, 113, 113);
    }
    return img.ColorRgb8(103, 232, 249);
  }

  static void _drawLine(
    img.Image image,
    String value,
    img.BitmapFont font,
    int x,
    int y,
    int maxWidth,
    img.Color color,
  ) {
    img.drawString(
      image,
      _fit(_ascii(value), font, maxWidth),
      font: font,
      x: x,
      y: y,
      color: color,
    );
  }

  static String _fit(String value, img.BitmapFont font, int maxWidth) {
    if (_textWidth(value, font) <= maxWidth) return value;
    var shortened = value;
    while (
        shortened.isNotEmpty && _textWidth('$shortened...', font) > maxWidth) {
      shortened = shortened.substring(0, shortened.length - 1);
    }
    return '$shortened...';
  }

  static int _textWidth(String value, img.BitmapFont font) {
    var width = 0;
    for (final code in value.codeUnits) {
      width += font.characters[code]?.xAdvance ?? font.base ~/ 2;
    }
    return width;
  }

  static String _ascii(String value) => value
      .replaceAll(RegExp(r'[^\x20-\x7E]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
