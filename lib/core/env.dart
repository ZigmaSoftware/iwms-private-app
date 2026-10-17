import 'package:flutter/foundation.dart';

/// Environment-style flags for build-time configuration.
/// Set via `--dart-define` when running or building:
///   flutter run --dart-define=VITE_PROD=true --dart-define=VITE_ENFORCE_PERMISSIONS=false --dart-define=VITE_PRIVATE_API_LOCAL=http://115.245.93.26:4216/api/v1
const bool kProd = bool.fromEnvironment(
  'VITE_PROD',
  defaultValue: kReleaseMode,
);
const bool kEnforcePermissions =
    bool.fromEnvironment('VITE_ENFORCE_PERMISSIONS', defaultValue: true);

// ── Supervisor waste KPI cards ──────────────────────────────────────────────
// Which pair(s) of breakdown cards the supervisor's waste summary shows under
// the Total card. They are independent, so any combination works:
//
//   both true   → Bin/Household row on top, Wet/Dry row beneath (default)
//   only one    → that single row
//   both false  → Total card alone (its tap-through breakdown still works)
//
// Toggle at build time, e.g.
//   flutter run --dart-define=VITE_SHOW_WET_DRY_CARDS=false
//   flutter run --dart-define=VITE_SHOW_BIN_HOUSEHOLD_CARDS=false
//
/// Show the "Wet Waste" / "Dry Waste" cards (split by waste TYPE).
const bool kShowWetDryKpiCards =
    bool.fromEnvironment('VITE_SHOW_WET_DRY_CARDS', defaultValue: true);

/// Show the "Bin Collection" / "Households" cards (split by collection STREAM).
const bool kShowBinHouseholdKpiCards =
    bool.fromEnvironment('VITE_SHOW_BIN_HOUSEHOLD_CARDS', defaultValue: false);

const String _defaultPrivateApiBase = 'http://115.245.93.26:4216/api/v1';
const String _defaultPrivateBackendOrigin = 'http://115.245.93.26:4216';



// const String _defaultPrivateApiBase = 'http://192.168.3.120:8000/api/v1';
// const String _defaultPrivateBackendOrigin = 'http://192.168.3.120:8000';

// Override the private backend bases via dart-define if needed.
const String _localApiOverride = String.fromEnvironment(
  'VITE_PRIVATE_API_LOCAL',
  defaultValue: _defaultPrivateApiBase,
);
const String _prodApiOverride = String.fromEnvironment(
  'VITE_PRIVATE_API_PROD',
  defaultValue: _defaultPrivateApiBase,
);

const String kApiBase = kProd ? _prodApiOverride : _localApiOverride;

/// Base path for the grouped router endpoints (no `/desktop` segment in v1).
const String kDesktopBase = '$kApiBase/';

// Shared third-party API values (single place for build-time overrides).
const String kOrsApiKey = String.fromEnvironment(
  'VITE_ORS_API_KEY',
  defaultValue:
      'eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6IjU3MzI5ZTM0NjM3YTQ2N2ZhZDYwMDM0ZmQ3ZDk0NTc3IiwiaCI6Im11cm11cjY0In0=',
);

const String kVehicleLiveApiBaseUrl = String.fromEnvironment(
  'VITE_VEHICLE_API_BASE_URL',
  defaultValue: 'https://api.vamosys.com/mobile/getGrpDataForTrustedClients',
);

const String kVehicleProviderName = String.fromEnvironment(
  'VITE_VEHICLE_PROVIDER_NAME',
  defaultValue: 'BLUEPLANET',
);

const String kVehicleFCode = String.fromEnvironment(
  'VITE_VEHICLE_FCODE',
  defaultValue: 'VAM',
);

const String kOperatorProfileBaseUrl = String.fromEnvironment(
  'VITE_PRIVATE_BACKEND_ORIGIN',
  defaultValue: _defaultPrivateBackendOrigin,
);

// MapTiler powers the Light/Dark basemap styles (see core/map/map_style.dart)
// — CARTO retired free anonymous tile access and Esri's key-less Canvas
// tiles have coverage gaps in India, so this is the real fix, not a
// fallback. Free-tier key from https://cloud.maptiler.com/account/keys/.
const String kMapTilerApiKey = String.fromEnvironment(
  'VITE_MAPTILER_API_KEY',
  defaultValue: 'UqY8ZGGSQrQPGUjvuBOc',
);
