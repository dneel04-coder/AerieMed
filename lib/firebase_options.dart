// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Hand-written (not FlutterFire-CLI-generated, since `flutterfire configure`
/// needs an interactive `firebase login` this environment can't perform).
/// Firebase project: res-q-ruck. Both Android and iOS values are real (from
/// google-services.json / GoogleService-Info.plist). Push notifications
/// won't actually be delivered on iOS until the APNs key is uploaded in
/// Firebase Console and the entitlements/Info.plist wiring is added (held
/// back until Push Notifications capability is enabled on the App ID).
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web — this app has no web target.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are only configured for android and ios — '
          'lib/main_admin.dart (Windows/macOS Command Console) never imports '
          'this file, so this branch should be unreachable in practice.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyD7AYRlxKVcRDxovzQeRQx-88bLpYMygS0',
    appId: '1:66964126543:android:40b8124c9076308289e33a',
    messagingSenderId: '66964126543',
    projectId: 'res-q-ruck',
    storageBucket: 'res-q-ruck.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBcXp0JN7asBQSdbJbc4wjKE4h9C6kWCHc',
    appId: '1:66964126543:ios:25f2f134d2716a4b89e33a',
    messagingSenderId: '66964126543',
    projectId: 'res-q-ruck',
    storageBucket: 'res-q-ruck.firebasestorage.app',
    iosBundleId: 'com.peninsulathreat.resqruck',
  );
}
