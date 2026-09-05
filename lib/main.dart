import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:iwms_private_app/localization/app_localizations.dart';
import 'package:iwms_private_app/core/di.dart';
import 'package:iwms_private_app/core/push/push_notification_service.dart';
import 'package:iwms_private_app/logic/auth/auth_bloc.dart';
import 'package:iwms_private_app/logic/auth/auth_event.dart';
import 'package:iwms_private_app/logic/theme/theme_cubit.dart';
import 'package:iwms_private_app/logic/locale/locale_cubit.dart';
import 'package:iwms_private_app/router/app_router.dart';
import 'package:iwms_private_app/router/go_router_refresh_stream.dart';
import 'package:iwms_private_app/router/route_observer.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await setupDI();

  // Safe no-op until Firebase is configured (see push_notification_service.dart).
  try {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (_) {
    // Firebase not configured yet — nothing to do.
  }

  final authBloc = getIt<AuthBloc>();

  final appRouter = AppRouter(
    authBloc: authBloc,
    routeObserver: routeObserver,
    refreshListenable: GoRouterRefreshStream(authBloc.stream),
  );

  runApp(
    MyApp(
      appRouter: appRouter.router,
      authBloc: authBloc,
    ),
  );
}

/// Re-fetches permissions when the app returns to the foreground, so a change
/// an administrator makes in web takes effect without the user signing out.
class _PermissionRefreshOnResume extends StatefulWidget {
  const _PermissionRefreshOnResume({required this.child});

  final Widget child;

  @override
  State<_PermissionRefreshOnResume> createState() =>
      _PermissionRefreshOnResumeState();
}

class _PermissionRefreshOnResumeState extends State<_PermissionRefreshOnResume>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<AuthBloc>().add(AuthPermissionsRefreshRequested());
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class MyApp extends StatelessWidget {
  final GoRouter appRouter;
  final AuthBloc authBloc;

  const MyApp({
    super.key,
    required this.appRouter,
    required this.authBloc,
  });

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: authBloc),
        BlocProvider(create: (_) => ThemeCubit()),
        BlocProvider(create: (_) => LocaleCubit()), // ✅ FIX
      ],
      child: _PermissionRefreshOnResume(
        child: BlocBuilder<ThemeCubit, ThemeMode>(
          builder: (context, themeMode) {
            return MaterialApp.router(
              debugShowCheckedModeBanner: false,
              title: 'IWMS',
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [
                Locale('en'),
                Locale('hi'),
                Locale('ta'),
              ],
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: themeMode,
              routerConfig: appRouter,
            );
          },
        ),
      ),
    );
  }
}
