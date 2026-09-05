import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:iwms_private_app/core/api_config.dart';
import 'package:iwms_private_app/core/di.dart';
import 'package:iwms_private_app/core/network/auth_dio.dart';
import 'package:iwms_private_app/core/network/auth_token_provider.dart';
import 'package:iwms_private_app/shared/services/notification_service.dart';

/// Instant, backend-triggered push notifications for the citizen app — e.g.
/// "your waste was just collected" the moment a driver marks it, even if the
/// app is backgrounded or closed.
///
/// This is entirely self-gating: [initAndRegister] silently no-ops if
/// Firebase hasn't been configured for this app yet (no
/// `android/app/google-services.json`), so the rest of the app is completely
/// unaffected either way. Once Firebase is configured, this "just works" with
/// no other code changes needed — see android/app/google-services.json setup
/// notes in android/app/build.gradle.kts.
///
/// Display reuses the citizen module's existing [NotificationService] (same
/// `iwms_default_channel`), so a push looks identical to the local
/// notifications the app already shows elsewhere.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  bool _firebaseReady = false;
  String? _lastRegistrationFingerprint;

  /// Call once after login (or app start, if already logged in). Requests
  /// notification permission, gets the device's FCM token, registers it with
  /// the backend, and wires foreground display + token refresh. Safe to call
  /// multiple times.
  ///
  /// [registerUrl] defaults to the citizen registration endpoint; pass
  /// `ApiConfig.registerStaffFcmToken` for driver/operator/supervisor logins.
  Future<void> initAndRegister({
    String registerUrl = ApiConfig.registerFcmToken,
  }) async {
    if (!await _ensureFirebaseInitialized()) return;

    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      await _resetTokenOnceForCurrentFirebaseProject(messaging);

      final token = await messaging.getToken();
      if (token != null) await _registerToken(token, registerUrl);

      messaging.onTokenRefresh.listen((t) => _registerToken(t, registerUrl));

      // Foreground: FCM doesn't auto-show a system notification while the app
      // is open, so display it ourselves via the existing local-notification
      // channel — the same one the rest of the citizen app already uses.
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final title = message.notification?.title ?? 'IWMS';
        final body = message.notification?.body ?? '';
        if (body.isEmpty) return;
        getIt<NotificationService>()
            .showAssignmentNotification(title: title, message: body);
      });
    } catch (e, st) {
      debugPrint('[push] initAndRegister failed (non-fatal): $e\n$st');
    }
  }

  Future<bool> _ensureFirebaseInitialized() async {
    if (_firebaseReady) return true;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _firebaseReady = true;
      return true;
    } catch (e) {
      // Expected until a real Firebase project (google-services.json) is
      // wired up — push notifications are simply disabled until then.
      debugPrint(
          '[push] Firebase not configured yet — push notifications disabled: $e');
      return false;
    }
  }

  Future<void> _resetTokenOnceForCurrentFirebaseProject(
    FirebaseMessaging messaging,
  ) async {
    try {
      final options = Firebase.app().options;
      final projectKey = options.messagingSenderId;
      final prefs = await SharedPreferences.getInstance();
      final resetKey = 'push.fcmTokenReset.$projectKey';
      if (prefs.getBool(resetKey) == true) return;

      await messaging.deleteToken();
      _lastRegistrationFingerprint = null;
      await prefs.setBool(resetKey, true);
      debugPrint('[push] FCM token reset for Firebase project $projectKey.');
    } catch (e) {
      debugPrint('[push] FCM token reset skipped (non-fatal): $e');
    }
  }

  Future<void> _registerToken(String token, String registerUrl) async {
    try {
      final authToken = await AuthTokenProvider.getToken() ?? '';
      final fingerprint = '$registerUrl|$authToken|$token';
      if (_lastRegistrationFingerprint == fingerprint) return;
      await AuthDio.dio.post(
        registerUrl,
        data: {'fcm_token': token},
      );
      _lastRegistrationFingerprint = fingerprint;
      debugPrint('[push] FCM token registered with backend.');
    } catch (e) {
      debugPrint('[push] Failed to register FCM token (non-fatal): $e');
    }
  }

  void resetSession() {
    _lastRegistrationFingerprint = null;
  }
}

/// Background/terminated-app message handler. Must be a top-level function
/// (or static) and registered before `runApp` via
/// `FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler)`.
/// FCM shows the system tray notification automatically for messages that
/// include a `notification` payload (which is what the backend sends), so
/// this handler only needs to exist — no manual display logic required.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (_) {
    // Firebase not configured — nothing to do.
  }
}
