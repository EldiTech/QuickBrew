import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Generated configuration for QuickBrew.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDlxmUqWTadFACJvQEkZmwGpxz__3pnjkk',
    appId: '1:1039563573692:web:9ce2daf4373be768dfc3b9',
    messagingSenderId: '1039563573692',
    projectId: 'quick-brew-64673',
    authDomain: 'quick-brew-64673.firebaseapp.com',
    storageBucket: 'quick-brew-64673.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDlxmUqWTadFACJvQEkZmwGpxz__3pnjkk',
    appId: '1:1039563573692:android:9ce2daf4373be768dfc3b9',
    messagingSenderId: '1039563573692',
    projectId: 'quick-brew-64673',
    storageBucket: 'quick-brew-64673.firebasestorage.app',
  );
}
