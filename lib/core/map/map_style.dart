import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Base map styles the user can switch between, Google-Maps style.
enum MapStyle { standard, light, dark, satellite }

/// The map style shown before a preference is loaded / when none is saved.
//
// Was MapStyle.light (CARTO Positron), but CARTO killed free anonymous
// access and Esri's key-less Light/Dark Canvas has real coverage gaps in
// India at close zoom (confirmed: empty "Map data not yet available" tiles
// over Bangalore at z18). OpenStreetMap standard has full coverage here, so
// it's the default until a paid tile provider (MapTiler/Stadia/etc.) is
// wired in — see the NOTE below on _kMapStyles.
const MapStyle kDefaultMapStyle = MapStyle.standard;

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

// Raster tile sources. All currently point at OpenStreetMap's standard
// tiles or Esri's key-less services — see the two NOTEs below for why, and
// what to fix once a proper paid tile key (MapTiler/Stadia/etc.) is set up.
//
// NOTE 1 (Light/Dark): previously CARTO Positron/Dark Matter
// (basemaps.cartocdn.com/{light,dark}_all). CARTO has retired free
// anonymous access to that CDN — every tile now comes back with an "API KEY
// REQUIRED" watermark instead of map data (confirmed directly against the
// CDN on 2026-08-27). Esri's key-less Light/Dark Gray Canvas was tried as a
// replacement but has real coverage gaps in India at close zoom (confirmed:
// blank "Map data not yet available" tiles over Bangalore at z18) — not
// usable for this app's actual routes. Both now fall back to OSM standard
// until a real paid provider is wired in.
//
// NOTE 2 (Standard/OSM in general): OpenStreetMap's tile servers actively
// rate-limit/block traffic that doesn't follow their usage policy
// (osm.wiki/Blocked) — a burst of requests during testing briefly returned
// a 418 "Access blocked" tile image instead of map data, though normal
// single-device traffic worked fine. OSM's own policy discourages embedding
// their tile servers directly in apps at any real scale, so this is a
// known risk for production traffic, not just a one-off. If map loads start
// silently failing/showing block tiles for users, this is why — the real
// fix is a paid tile provider (MapTiler has a generous free tier and is
// built for exactly this use case).
const Map<MapStyle, _MapStyleSpec> _kMapStyles = {
  MapStyle.standard: _MapStyleSpec(
    'Default',
    Icons.map_outlined,
    // No {s} subdomain: OSM deprecated the a/b/c load-balancing scheme
    // (github.com/openstreetmap/operations/issues/737) — flutter_map warns
    // on it, and it's exactly the kind of policy-non-compliant usage that
    // risks a 418 block.
    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    [],
  ),
  MapStyle.light: _MapStyleSpec(
    'Light',
    Icons.light_mode_outlined,
    // No {s} subdomain: OSM deprecated the a/b/c load-balancing scheme
    // (github.com/openstreetmap/operations/issues/737) — flutter_map warns
    // on it, and it's exactly the kind of policy-non-compliant usage that
    // risks a 418 block.
    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    [],
  ),
  MapStyle.dark: _MapStyleSpec(
    'Dark',
    Icons.dark_mode_outlined,
    // No {s} subdomain: OSM deprecated the a/b/c load-balancing scheme
    // (github.com/openstreetmap/operations/issues/737) — flutter_map warns
    // on it, and it's exactly the kind of policy-non-compliant usage that
    // risks a 418 block.
    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    [],
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
