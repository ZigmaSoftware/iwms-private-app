import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android declares camera and foreground location for evidence capture',
      () async {
    final manifest = await File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsString();

    expect(manifest, contains('android.permission.CAMERA'));
    expect(manifest, contains('android.permission.ACCESS_COARSE_LOCATION'));
    expect(manifest, contains('android.permission.ACCESS_FINE_LOCATION'));
    expect(
        manifest, isNot(contains('android.permission.WRITE_EXTERNAL_STORAGE')));

    final service = await File(
      'lib/shared/services/collection_photo_proof_service.dart',
    ).readAsString();
    expect(service, contains('Permission.camera.request()'));
    expect(service, contains('Geolocator.requestPermission()'));
  });
}
