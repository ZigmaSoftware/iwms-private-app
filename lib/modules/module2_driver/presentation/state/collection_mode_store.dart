import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum CollectionMode { household, bin }

class CollectionModeStore {
  CollectionModeStore._();

  static const String _prefsKey = 'driver_collection_mode';

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
    } catch (_) {}
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
