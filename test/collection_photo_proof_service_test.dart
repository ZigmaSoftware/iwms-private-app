import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:iwms_private_app/shared/services/collection_photo_proof_service.dart';

void main() {
  test('burns proof into the image without covering its centre', () async {
    final directory = await Directory.systemTemp.createTemp('iwms-proof-test');
    addTearDown(() => directory.delete(recursive: true));

    final source = File('${directory.path}/source.jpg');
    final output = File('${directory.path}/proof.jpg');
    final blank = img.Image(width: 1200, height: 1600)
      ..clear(img.ColorRgb8(150, 150, 150));
    await source.writeAsBytes(img.encodeJpg(blank, quality: 95));

    await CollectionPhotoProofService.stampWithMetadata(
      sourcePath: source.path,
      outputPath: output.path,
      wasteType: 'Wet Waste',
      stopLabel: 'Household 140',
      assignmentId: 'TRIP-2026-001',
      weightKg: 22,
      latitude: 26.846694,
      longitude: 80.946166,
      accuracyMetres: 8,
      capturedAt: DateTime(2026, 10, 14, 11, 42, 5),
      address: 'Ward B, Lucknow, Uttar Pradesh 226001',
    );
    expect(await output.exists(), isTrue);
    final stamped = img.decodeJpg(await output.readAsBytes());
    expect(stamped, isNotNull);
    expect(stamped!.width, 1200);
    expect(stamped.height, 1600);

    // The middle remains photographic evidence; overlays stay at the edges.
    final centre = stamped.getPixel(600, 700);
    expect(centre.r, closeTo(150, 8));
    expect(centre.g, closeTo(150, 8));
    expect(centre.b, closeTo(150, 8));

    // Top-right waste badge and bottom proof panel are physically encoded.
    final badge = stamped.getPixel(1100, 60);
    expect((badge.g - badge.r).abs(), greaterThan(20));
    final panel = stamped.getPixel(100, 1500);
    expect(panel.r, lessThan(130));
    expect(panel.g, lessThan(140));
  });
}
