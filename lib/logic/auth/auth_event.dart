abstract class AuthEvent {}

class AuthStatusChecked extends AuthEvent {}

class AuthCitizenLoginRequested extends AuthEvent {
  final String username;
  final String password;

  AuthCitizenLoginRequested({required this.username, required this.password});
}

class AuthCitizenRegisterRequested extends AuthEvent {
  final String fullName;

  AuthCitizenRegisterRequested({required this.fullName});
}

class AuthLogoutRequested extends AuthEvent {}

class AuthOperatorLoginRequested extends AuthEvent {
  final String operatorId;
  final String userName;

  AuthOperatorLoginRequested({required this.operatorId, required this.userName});
}

/// Re-fetch the permission bundle without touching the session.
///
/// Fired when the app returns to the foreground, so a change an administrator
/// made in web lands without the user having to sign out and back in. Unlike
/// [AuthStatusChecked] this never logs anyone out — a refresh that fails
/// leaves the cached bundle in place.
class AuthPermissionsRefreshRequested extends AuthEvent {}
