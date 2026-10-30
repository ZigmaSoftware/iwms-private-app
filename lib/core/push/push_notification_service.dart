import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:iwms_private_app/core/api_config.dart';
import 'package:iwms_private_app/core/di.dart';
import 'package:iwms_private_app/core/network/auth_dio.dart';
import 'package:iwms_private_app/core/network/auth_token_provider.dart';
import 'package:iwms_private_app/shared/services/notification_service.dart';
import 'package:iwms_private_app/modules/module1_citizen/citizen/dashboard/notifications/controllers/notification_controller.dart';
import 'package:iwms_private_app/modules/module1_citizen/citizen/dashboard/notifications/models/citizen_alert.dart';

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

  final _events = StreamController<Map<String, dynamic>>.broadcast();

  /// The `data` payload of every push received while the app is in the
  /// foreground (e.g. `{'event': 'customer_available', ...}`), so open
  /// screens can refresh themselves instead of waiting for a pull-to-refresh.
  Stream<Map<String, dynamic>> get events => _events.stream;

  bool _firebaseReady = false;
  bool _listenersAttached = false;
  String? _activeRegisterUrl;
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
    _activeRegisterUrl = registerUrl;

    try {
      final messaging = FirebaseMessaging.instance;
      final permission = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      _attachListeners(messaging);
      if (permission.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('[push] Notification permission denied by the user.');
        return;
      }
      await _resetTokenOnceForCurrentFirebaseProject(messaging);

      final token = await _getTokenWhenReady(messaging);
      if (token != null) await _registerTokenWithRetry(token, registerUrl);
    } catch (e, st) {
      debugPrint('[push] initAndRegister failed (non-fatal): $e\n$st');
    }
  }

  void _attachListeners(FirebaseMessaging messaging) {
    if (_listenersAttached) return;
    _listenersAttached = true;

    messaging.onTokenRefresh.listen((token) {
      final url = _activeRegisterUrl;
      if (url != null) unawaited(_registerTokenWithRetry(token, url));
    });

    // FCM does not show notification payloads automatically in foreground.
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      if (_activeRegisterUrl == null) return;
      if (message.data.isNotEmpty) {
        _events.add(Map<String, dynamic>.from(message.data));
      }
      final title = message.notification?.title ?? 'IWMS';
      final body = message.notification?.body ?? '';
      if (body.isEmpty) return;
      final service = getIt<NotificationService>();
      await service.initialize();
      if (_activeRegisterUrl == ApiConfig.registerFcmToken) {
        getIt<NotificationController>().addAlert(CitizenAlert(
          title: title,
          message: body,
          timestamp: DateTime.now(),
        ));
      } else {
        await service.showAssignmentNotification(title: title, message: body);
      }
    });
  }

  Future<String?> _getTokenWhenReady(FirebaseMessaging messaging) async {
    // On Apple platforms FCM cannot issue a token until APNs has completed
    // registration. Calling getToken too early throws apns-token-not-set and,
    // previously, permanently skipped registration for that login session.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      for (var attempt = 0; attempt < 12; attempt++) {
        if (await messaging.getAPNSToken() != null) break;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      if (await messaging.getAPNSToken() == null) {
        debugPrint('[push] APNs token was not available after 6 seconds.');
        return null;
      }
    }
    return messaging.getToken();
  }

  Future<void> _registerTokenWithRetry(
    String token,
    String registerUrl,
  ) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      if (await _registerToken(token, registerUrl)) return;
      await Future<void>.delayed(Duration(seconds: 1 << attempt));
    }
  }

  /// Revalidates token ownership after the app returns from the background.
  Future<void> refreshRegistration() async {
    final registerUrl = _activeRegisterUrl;
    if (registerUrl == null || !await _ensureFirebaseInitialized()) return;
    try {
      final token = await _getTokenWhenReady(FirebaseMessaging.instance);
      if (token != null) await _registerTokenWithRetry(token, registerUrl);
    } catch (e) {
      debugPrint('[push] Token refresh failed (non-fatal): $e');
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

  Future<bool> _registerToken(String token, String registerUrl) async {
    try {
      final authToken = await AuthTokenProvider.getToken() ?? '';
      final fingerprint = '$registerUrl|$authToken|$token';
      if (_lastRegistrationFingerprint == fingerprint) return true;
      await AuthDio.dio.post(
        registerUrl,
        data: {'fcm_token': token},
      );
      _lastRegistrationFingerprint = fingerprint;
      debugPrint('[push] FCM token registered with backend.');
      return true;
    } catch (e) {
      debugPrint('[push] Failed to register FCM token (non-fatal): $e');
      return false;
    }
  }

  void resetSession() {
    _activeRegisterUrl = null;
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
