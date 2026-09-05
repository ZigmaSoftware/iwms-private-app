import 'package:equatable/equatable.dart';

class AppSurfaceAccess extends Equatable {
  final String key;
  final String label;
  final String route;
  final bool isDefault;

  const AppSurfaceAccess({
    required this.key,
    required this.label,
    required this.route,
    required this.isDefault,
  });

  factory AppSurfaceAccess.fromJson(Map<String, dynamic> json) {
    return AppSurfaceAccess(
      key: json['key']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      route: json['route']?.toString() ?? '',
      isDefault: json['isDefault'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'label': label,
      'route': route,
      'isDefault': isDefault,
    };
  }

  @override
  List<Object?> get props => [key, label, route, isDefault];
}

class PermissionLanding extends Equatable {
  final String? surfaceKey;
  final String? route;
  final String? moduleKey;
  final String? screenKey;

  const PermissionLanding({
    this.surfaceKey,
    this.route,
    this.moduleKey,
    this.screenKey,
  });

  factory PermissionLanding.fromJson(Map<String, dynamic> json) {
    return PermissionLanding(
      surfaceKey: json['surfaceKey']?.toString(),
      route: json['route']?.toString(),
      moduleKey: json['moduleKey']?.toString(),
      screenKey: json['screenKey']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'surfaceKey': surfaceKey,
      'route': route,
      'moduleKey': moduleKey,
      'screenKey': screenKey,
    };
  }

  @override
  List<Object?> get props => [surfaceKey, route, moduleKey, screenKey];
}

class PermissionBundle extends Equatable {
  final Map<String, dynamic> permissions;
  final Map<String, dynamic> permissionDetails;
  final Map<String, dynamic> columnPermissions;
  final List<Map<String, dynamic>> moduleAccess;
  final List<AppSurfaceAccess> appSurfaces;

  /// Apps this user may sign into, e.g. `['supervisor']`. Empty means the
  /// mobile sign-in was refused, so this should never be empty in the app.
  final List<String> appModules;

  /// Screens to render per app, keyed by module: `{'supervisor': ['supervisor.trips', ...]}`.
  ///
  /// The backend derives these from the same permissions the middleware
  /// enforces, so a visible tab and a 403 cannot disagree. A screen appears
  /// when its main list permission is granted; anything else it reads that
  /// the user cannot see is hidden inside the screen instead.
  final Map<String, List<String>> appScreens;

  /// True when the backend explicitly sent the `app_screens` field. This lets
  /// the app distinguish a modern strict response with zero screens from an old
  /// backend that did not know about app-screen gating yet.
  final bool receivedAppScreens;
  final PermissionLanding? landing;
  final String? permissionVersion;
  final String? generatedAt;
  final String? source;

  const PermissionBundle({
    required this.permissions,
    required this.permissionDetails,
    required this.columnPermissions,
    required this.moduleAccess,
    required this.appSurfaces,
    this.appModules = const [],
    this.appScreens = const {},
    this.receivedAppScreens = false,
    this.landing,
    this.permissionVersion,
    this.generatedAt,
    this.source,
  });

  const PermissionBundle.empty()
      : permissions = const {},
        permissionDetails = const {},
        columnPermissions = const {},
        moduleAccess = const [],
        appSurfaces = const [],
        appModules = const [],
        appScreens = const {},
        receivedAppScreens = false,
        landing = null,
        permissionVersion = null,
        generatedAt = null,
        source = null;

  factory PermissionBundle.fromApi(Map<String, dynamic> json) {
    final rawPermissions = _mapOrEmpty(json['permissions']);
    final rawPermissionDetails = _mapOrEmpty(json['permission_details']);
    final rawColumnPermissions = _mapOrEmpty(json['column_permissions']);
    final rawModuleAccess = _listOfMaps(json['module_access']);
    final rawSurfaces = (json['app_surfaces'] as List?)
            ?.whereType<Map>()
            .map((item) =>
                AppSurfaceAccess.fromJson(Map<String, dynamic>.from(item)))
            .toList() ??
        const <AppSurfaceAccess>[];
    final rawLanding = json['landing'] is Map<String, dynamic>
        ? PermissionLanding.fromJson(json['landing'] as Map<String, dynamic>)
        : json['landing'] is Map
            ? PermissionLanding.fromJson(
                Map<String, dynamic>.from(json['landing'] as Map))
            : null;

    final rawModules = (json['app_modules'] as List?)
            ?.map((item) => item?.toString() ?? '')
            .where((item) => item.isNotEmpty)
            .toList() ??
        const <String>[];

    final rawScreens = <String, List<String>>{};
    final screensJson = json['app_screens'];
    final receivedScreens = json.containsKey('app_screens');
    if (screensJson is Map) {
      screensJson.forEach((key, value) {
        if (value is List) {
          rawScreens[key.toString()] = value
              .map((item) => item?.toString() ?? '')
              .where((item) => item.isNotEmpty)
              .toList();
        }
      });
    }

    return PermissionBundle(
      permissions: rawPermissions,
      permissionDetails: rawPermissionDetails,
      columnPermissions: rawColumnPermissions,
      moduleAccess: rawModuleAccess,
      appSurfaces: rawSurfaces,
      appModules: rawModules,
      appScreens: rawScreens,
      receivedAppScreens: receivedScreens,
      landing: rawLanding,
      permissionVersion: json['permission_version']?.toString(),
      generatedAt: json['generated_at']?.toString(),
      source: json['source']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'permissions': permissions,
      'permission_details': permissionDetails,
      'column_permissions': columnPermissions,
      'module_access': moduleAccess,
      'app_surfaces': appSurfaces.map((item) => item.toJson()).toList(),
      'app_modules': appModules,
      'app_screens': appScreens,
      'received_app_screens': receivedAppScreens,
      'landing': landing?.toJson(),
      'permission_version': permissionVersion,
      'generated_at': generatedAt,
      'source': source,
    };
  }

  /// Whether [screenKey] (e.g. `supervisor.trips`) should be rendered.
  ///
  /// A user whose old backend bundle carries no `app_screens` field at all is
  /// treated as allowed for compatibility. A modern strict backend sends the
  /// field even when the answer is empty, and that must fail closed.
  bool canSeeScreen(String screenKey) {
    if (!receivedAppScreens) return true;

    final target = _normalizeKey(screenKey);
    for (final screens in appScreens.values) {
      for (final granted in screens) {
        if (_normalizeKey(granted) == target) return true;
      }
    }
    return false;
  }

  /// Screens granted for one app, in backend order.
  List<String> screensFor(String moduleKey) =>
      appScreens[moduleKey] ?? const <String>[];

  /// Whether the backend told us anything about screens. Screens that must
  /// fail closed can check this before trusting [canSeeScreen].
  bool get hasScreenData => receivedAppScreens;

  bool get isEmpty =>
      permissions.isEmpty &&
      permissionDetails.isEmpty &&
      columnPermissions.isEmpty &&
      moduleAccess.isEmpty &&
      appSurfaces.isEmpty &&
      appModules.isEmpty &&
      permissionVersion == null &&
      generatedAt == null &&
      !receivedAppScreens;

  AppSurfaceAccess? get defaultSurface {
    if (appSurfaces.isEmpty) return null;
    for (final surface in appSurfaces) {
      if (surface.isDefault) return surface;
    }
    return appSurfaces.first;
  }

  bool hasAppSurface(String surfaceKey) {
    final target = _normalizeKey(surfaceKey);
    return appSurfaces.any((surface) => _normalizeKey(surface.key) == target);
  }

  bool hasPermission(
    String moduleName,
    String screenName, {
    String action = 'view',
  }) {
    final targetModule = _normalizeKey(moduleName);
    final targetScreen = _normalizeKey(screenName);
    final targetAction = _normalizeKey(action);

    for (final entry in permissions.entries) {
      if (_normalizeKey(entry.key) != targetModule) {
        continue;
      }

      final screens = entry.value;
      if (screens is! Map) {
        return false;
      }

      for (final screenEntry in screens.entries) {
        if (_normalizeKey(screenEntry.key.toString()) != targetScreen) {
          continue;
        }

        final actions = screenEntry.value;
        if (actions is! List) {
          return false;
        }

        return actions.any(
          (candidate) =>
              _normalizeKey(candidate?.toString() ?? '') == targetAction,
        );
      }
    }

    return false;
  }

  static Map<String, dynamic> _mapOrEmpty(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return <String, dynamic>{};
  }

  static List<Map<String, dynamic>> _listOfMaps(dynamic value) {
    if (value is! List) {
      return const <Map<String, dynamic>>[];
    }
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static String _normalizeKey(String value) {
    final lower = value.trim().toLowerCase();
    if (lower.isEmpty) return '';
    return lower.replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(
          RegExp(r'-+'),
          '-',
        );
  }

  @override
  List<Object?> get props => [
        permissions,
        permissionDetails,
        columnPermissions,
        moduleAccess,
        appSurfaces,
        appModules,
        appScreens,
        receivedAppScreens,
        landing,
        permissionVersion,
        generatedAt,
        source,
      ];
}
