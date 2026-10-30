import 'package:dio/dio.dart';

/// Turns a bare 403 into something a user can act on.
///
/// A denied request used to surface as a generic failure, which meant a
/// missing permission looked identical to a broken screen — the only way to
/// tell them apart was reading the server log. The backend's 403 body carries
/// the module, resource and action it refused, so name the screen and say who
/// can fix it.
class PermissionDeniedException implements Exception {
  const PermissionDeniedException({
    required this.message,
    this.module,
    this.resource,
    this.action,
  });

  final String message;
  final String? module;
  final String? resource;
  final String? action;

  @override
  String toString() => message;
}

/// A denied response from ModulePermissionMiddleware, or null if [error] is
/// any other failure.
PermissionDeniedException? asPermissionDenied(Object error) {
  if (error is! DioException) return null;
  if (error.response?.statusCode != 403) return null;

  final data = error.response?.data;
  final body = data is Map ? Map<String, dynamic>.from(data) : const {};

  final module = body['module']?.toString();
  final resource = body['resource']?.toString();
  final action = body['action']?.toString();

  final screen =
      _screenLabel(resource) ?? _screenLabel(module) ?? 'this screen';
  final verb = switch (action) {
    'add' || 'edit' || 'delete' => 'make changes here',
    _ => 'open $screen',
  };

  return PermissionDeniedException(
    message: "You don't have permission to $verb. "
        'Ask your administrator to grant it in Staff Access Configuration.',
    module: module,
    resource: resource,
    action: action,
  );
}

/// The user-facing message for [error], whatever kind of failure it is.
String describeRequestFailure(Object error,
    {String fallback = 'Something went wrong.'}) {
  final denied = asPermissionDenied(error);
  if (denied != null) return denied.message;

  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'The server took too long to respond. Check your connection and try again.';
      case DioExceptionType.connectionError:
        return 'Cannot reach the server. Check your connection and try again.';
      default:
        final code = error.response?.statusCode;
        if (code == 401) {
          return 'Your session has expired. Sign in again.';
        }
        if (code != null && code >= 500) {
          return 'The server had a problem handling that. Try again shortly.';
        }
    }
  }
  return fallback;
}

/// "daily-trip-assignments" -> "Daily Trip Assignments"
String? _screenLabel(String? raw) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) return null;

  final words = value
      .replaceAll(RegExp(r'[-_]+'), ' ')
      .replaceAllMapped(
        RegExp(r'(?<=[a-z])(?=[A-Z])'),
        (_) => ' ',
      )
      .split(' ')
      .where((word) => word.isNotEmpty)
      .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase());

  return words.isEmpty ? null : words.join(' ');
}
