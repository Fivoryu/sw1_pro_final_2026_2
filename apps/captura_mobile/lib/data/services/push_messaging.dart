import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// The slice of Firebase Cloud Messaging the app needs, so the registration
/// logic can be tested without Firebase.
abstract class PushMessaging {
  /// Asks the user for notification permission; true when notices can be shown.
  Future<bool> requestPermission();

  /// The registration token of this installation, or null when unavailable.
  Future<String?> obtainToken();

  /// Emits a new token whenever FCM rotates it.
  Stream<String> get tokenRefreshes;
}

/// [PushMessaging] backed by `firebase_messaging`.
class FirebasePushMessaging implements PushMessaging {
  FirebasePushMessaging._();

  /// Initializes Firebase from the platform configuration (`google-services.json`).
  /// Returns null when Firebase is not configured, so the app still runs
  /// without push notifications.
  static Future<FirebasePushMessaging?> initialize() async {
    try {
      await Firebase.initializeApp();
      return FirebasePushMessaging._();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> requestPermission() async {
    final settings = await FirebaseMessaging.instance.requestPermission();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  // `getToken` and `onTokenRefresh` are deprecated in favour of `register()` and
  // `onRegistered`, which yield a Firebase Installation ID. The backend sends
  // with the FCM HTTP v1 `token` field, which is documented for registration
  // tokens, so the classic API stays until an installation ID is verified there.
  @override
  // ignore: deprecated_member_use
  Future<String?> obtainToken() => FirebaseMessaging.instance.getToken();

  @override
  Stream<String> get tokenRefreshes =>
      // ignore: deprecated_member_use
      FirebaseMessaging.instance.onTokenRefresh;
}
