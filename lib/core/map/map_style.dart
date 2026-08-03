import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Base map styles the user can switch between, Google-Maps style.
enum MapStyle { standard, light, dark, satellite }

/// The map style shown before a preference is loaded / when none is saved.
const MapStyle kDefaultMapStyle = MapStyle.light;

/// Persists the chosen base-map style on the device so it survives logout /
/// app restarts and is restored every time the user opens a map.
class MapStylePrefs {
  static const _key = 'map_style';

  static Future<MapStyle> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString(_key);
      return MapStyle.values.firstWhere(
        (style) => style.name == name,
        orElse: () => kDefaultMapStyle,
      );
    } catch (_) {
      return kDefaultMapStyle;
    }
  }

  static Future<void> save(MapStyle style) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, style.name);
    } catch (_) {
      // Non-fatal: persistence is best-effort.
    }
  }
}

class _MapStyleSpec {
  final String label;
  final IconData icon;
  final String urlTemplate;
  final List<String> subdomains;
  const _MapStyleSpec(this.label, this.icon, this.urlTemplate, this.subdomains);
}

// Free, key-less raster tile sources (same ones Leaflet/flutter_map commonly use):
// - OpenStreetMap standard        (Default)
// - CARTO Positron / Dark Matter  (Light / Dark)
// - Esri World Imagery            (Satellite)
const Map<MapStyle, _MapStyleSpec> _kMapStyles = {
  MapStyle.standard: _MapStyleSpec(
    'Default',
    Icons.map_outlined,
    'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
    ['a', 'b', 'c'],
  ),
  MapStyle.light: _MapStyleSpec(
    'Light',
    Icons.light_mode_outlined,
    'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
    ['a', 'b', 'c', 'd'],
  ),
  MapStyle.dark: _MapStyleSpec(
    'Dark',
    Icons.dark_mode_outlined,
    'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
    ['a', 'b', 'c', 'd'],
  ),
  MapStyle.satellite: _MapStyleSpec(
    'Satellite',
    Icons.satellite_alt_outlined,
    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    [],
  ),
};

String mapStyleLabel(MapStyle style) =>
    (_kMapStyles[style] ?? _kMapStyles[MapStyle.standard]!).label;

/// A flutter_map [TileLayer] for the given base-map [style]. Drop this into a
/// FlutterMap's `children` in place of a hard-coded TileLayer.
TileLayer buildMapTileLayer(MapStyle style) {
  final spec = _kMapStyles[style] ?? _kMapStyles[MapStyle.standard]!;
  return TileLayer(
    urlTemplate: spec.urlTemplate,
    subdomains: spec.subdomains,
    userAgentPackageName: 'com.iwms.citizen.app',
  );
}

/// Floating layer picker (like Google Maps' map-type button). Tap to choose a
/// base map style; the selected one is checked.
class MapStyleToggle extends StatelessWidget {
  const MapStyleToggle({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final MapStyle selected;
  final ValueChanged<MapStyle> onChanged;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Material(
      color: Colors.white,
      elevation: 3,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: PopupMenuButton<MapStyle>(
        tooltip: 'Map type',
        icon: const Icon(Icons.layers_outlined, color: Colors.black87),
        position: PopupMenuPosition.under,
        onSelected: (style) {
          // Remember the choice so it's restored next time a map opens.
          MapStylePrefs.save(style);
          onChanged(style);
        },
        itemBuilder: (context) => MapStyle.values.map((style) {
          final spec = _kMapStyles[style]!;
          final isSelected = style == selected;
          return PopupMenuItem<MapStyle>(
            value: style,
            child: Row(
              children: [
                Icon(spec.icon,
                    size: 18, color: isSelected ? primary : Colors.black54),
                const SizedBox(width: 10),
                Text(
                  spec.label,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? primary : Colors.black87,
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.check, size: 16, color: primary),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
