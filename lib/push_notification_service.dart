import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'protocol_admin.dart' show SupabaseService;

/// Registers this device for push notifications (mission assignment alerts)
/// and keeps its FCM token in sync with Supabase. One current token per
/// user_id — overwritten on each registration, matching the single-device
/// assumption already used for tac_user_id/callsign uniqueness elsewhere.
///
/// Deliberately does NOT wire up FirebaseMessaging.onMessage (foreground
/// messages): while the app is open, the existing Realtime subscription in
/// _MainShellState already shows the Accept/Not Now dialog — a foreground
/// banner here would double-prompt. This service's only job is to get a
/// notification onto the device when the app is closed/backgrounded; once
/// the user taps it and the app opens, the existing, unchanged
/// _checkPendingMissionAssignment() startup check takes over.
class PushNotificationService {
  PushNotificationService._();
  static final instance = PushNotificationService._();

  bool _initialized = false;

  Future<void> initialize(String userId) async {
    if (userId.isEmpty || _initialized) return;
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      await FirebaseMessaging.instance.requestPermission();
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _register(userId, token);
      FirebaseMessaging.instance.onTokenRefresh.listen((t) => _register(userId, t));
      _initialized = true;
    } catch (_) {
      // Not configured yet (placeholder Firebase project values), no
      // connectivity, or permission denied — degrade silently, matching
      // every other "feature not set up yet" fallback in this app.
    }
  }

  Future<void> _register(String userId, String token) async {
    final ok = await SupabaseService.ensureInitialized();
    final client = SupabaseService.client;
    if (!ok || client == null) return;
    try {
      await client.from('device_push_tokens').upsert({
        'user_id': userId,
        'fcm_token': token,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id');
    } catch (_) {}
  }
}
