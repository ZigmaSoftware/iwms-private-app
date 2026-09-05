import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:iwms_private_app/core/di.dart';
import 'package:iwms_private_app/core/network/permission_error.dart';
import 'package:iwms_private_app/data/repositories/auth_repository.dart';

Dio _cloneBaseDio() {
  final base = getIt<Dio>();
  base.options.headers.remove('Authorization');

  final headers = Map<String, dynamic>.from(base.options.headers);
  headers.remove('Authorization');

  final options = BaseOptions(
    baseUrl: base.options.baseUrl,
    connectTimeout: base.options.connectTimeout,
    receiveTimeout: base.options.receiveTimeout,
    sendTimeout: base.options.sendTimeout,
    headers: headers,
    contentType: base.options.contentType,
    responseType: base.options.responseType,
    followRedirects: base.options.followRedirects,
    validateStatus: base.options.validateStatus,
    receiveDataWhenStatusError: base.options.receiveDataWhenStatusError,
  );

  final dio = Dio(options);
  dio.interceptors.addAll(base.interceptors);
  // Name the missing permission in the log instead of leaving a bare 403.
  // A denied request and a broken endpoint used to look identical here.
  dio.interceptors.add(
    InterceptorsWrapper(
      onError: (error, handler) {
        final denied = asPermissionDenied(error);
        if (denied != null) {
          debugPrint(
            'Permission denied: ${error.requestOptions.method} '
            '${error.requestOptions.path} -> '
            'module=${denied.module} resource=${denied.resource} '
            'action=${denied.action}',
          );
        }
        handler.next(error);
      },
    ),
  );
  dio.httpClientAdapter = base.httpClientAdapter;
  return dio;
}

Future<Dio> authorizedDio() async {
  final dio = _cloneBaseDio();
  final authRepo = getIt<AuthRepository>();

  final user = await authRepo.getAuthenticatedUser();
  dio.options.headers['Content-Type'] = 'application/json';

  if (user?.authToken != null && user!.authToken!.isNotEmpty) {
    dio.options.headers['Authorization'] = 'Bearer ${user.authToken}';
  } else {
    dio.options.headers.remove('Authorization');
  }

  return dio;
}
