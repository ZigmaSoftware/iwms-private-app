import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which kind of collection the driver is working right now.
enum CollectionMode { household, bin }

/// The driver's selected collection mode — Household or Bin — persisted across
/// launches and toggled from the header. The Captain shell listens to [mode]
/// and rebuilds, so the carousel, home list, map and scan button all show only
/// the selected mode's trips.
///
/// Mirrors [CaptainThemeStore]'s notifier+SharedPreferences pattern so the shell
/// can listen with a `ValueListenableBuilder` exactly the same way.
class CollectionModeStore {
  CollectionModeStore._();

  static const String _prefsKey = 'driver_collection_mode';

  /// Default is bin collection (the app's original single-mode behaviour).
  static final ValueNotifier<CollectionMode> mode =
      ValueNotifier<CollectionMode>(CollectionMode.bin);

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString(_prefsKey);
      mode.value = CollectionMode.values.firstWhere(
        (m) => m.name == name,
        orElse: () => CollectionMode.bin,
      );
    } catch (_) {
      // Keep the default if prefs are unavailable.
    }
  }

  static Future<void> set(CollectionMode value) async {
    mode.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, value.name);
    } catch (_) {}
  }

  static bool get isHousehold => mode.value == CollectionMode.household;
}
