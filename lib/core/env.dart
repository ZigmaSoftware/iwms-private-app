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

const String _defaultPrivateApiBase = 'http://115.245.93.26:4216/api/v1';
const String _defaultPrivateBackendOrigin = 'http://115.245.93.26:4216';

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


