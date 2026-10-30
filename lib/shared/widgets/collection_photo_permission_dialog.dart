import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'package:iwms_private_app/core/ui/app_flash.dart';
import 'package:iwms_private_app/shared/services/collection_photo_proof_service.dart';

Future<void> handleCollectionPhotoProofFailure(
  BuildContext context,
  CollectionPhotoProofException error,
) async {
  if (error.recovery == CollectionPhotoProofRecovery.none) {
    AppFlash.error(context, error.message);
    return;
  }

  final openSettings = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFE7F7EE),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.location_on_rounded,
              color: Color(0xFF16824B),
              size: 27,
            ),
          ),
          title: const Text('Permission needed for proof'),
          content: Text(
            '${error.message}\n\nAfter enabling it, return and tap Capture again.',
            textAlign: TextAlign.center,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Not now'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.settings_rounded, size: 18),
              label: const Text('Open Settings'),
            ),
          ],
        ),
      ) ??
      false;

  if (!openSettings) return;
  if (error.recovery == CollectionPhotoProofRecovery.locationSettings) {
    await Geolocator.openLocationSettings();
  } else {
    await Geolocator.openAppSettings();
  }
}
