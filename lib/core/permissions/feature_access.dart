import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:iwms_private_app/data/models/permission_bundle.dart';
import 'package:iwms_private_app/logic/auth/auth_bloc.dart';
import 'package:iwms_private_app/logic/auth/auth_state.dart';

/// Reads the signed-in user's granted app screens out of [AuthBloc].
///
/// A modern strict backend sends an explicit app-screen list. Missing screens
/// fail closed; only [PermissionBundle.canSeeScreen] keeps compatibility for an
/// older backend that never sent the field.
extension FeatureAccess on BuildContext {
  PermissionBundle? get permissionBundle {
    final state = read<AuthBloc>().state;
    return state is AuthStateAuthenticated ? state.permissionBundle : null;
  }

  /// Whether this screen is available to the signed-in user.
  bool canSeeScreen(String screenKey) =>
      permissionBundle?.canSeeScreen(screenKey) ?? false;

  /// Whether the user holds [action] on a specific module/screen.
  ///
  /// Use this for buttons inside a screen — "can this supervisor approve a
  /// re-trip" — where the answer is one permission rather than a whole screen.
  bool canDo(String module, String screen, {String action = 'edit'}) =>
      permissionBundle?.hasPermission(module, screen, action: action) ?? false;
}

/// Renders [child] only when [screen] is granted.
///
/// Hides rather than disables: a control the user can never enable is a dead
/// end, and an administrator is the only one who can change the answer.
class ScreenGate extends StatelessWidget {
  const ScreenGate({
    super.key,
    required this.screen,
    required this.child,
    this.fallback,
  });

  final String screen;
  final Widget child;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    final granted = context.permissionBundle?.canSeeScreen(screen) ?? false;
    return granted ? child : (fallback ?? const SizedBox.shrink());
  }
}
