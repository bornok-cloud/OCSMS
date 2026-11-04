import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.windows) {
      return const FirebaseOptions(
        apiKey: "AIzaSyDdIwhtWtAGSB_qHYawjMSr8w_hJLQZVGg",
        appId: "1:474193859592:web:3c22532f846f8d2bceadbd",
        messagingSenderId: "474193859592",
        projectId: "appdev-8edd2",
        authDomain: "appdev-8edd2.firebaseapp.com",
        storageBucket: "appdev-8edd2.firebasestorage.app",
        measurementId: "G-JRTLL6SGC4",
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return const FirebaseOptions(
          apiKey: "AIzaSyBjzvC4BegGdQs1phjqm69YfdCfHboH_Z0",
          appId: "1:474193859592:android:afbb888edfd2f0e7ceadbd",
          messagingSenderId: "474193859592",
          projectId: "appdev-8edd2",
          storageBucket: "appdev-8edd2.firebasestorage.app",
        );
      default:
        throw UnsupportedError(
          "DefaultFirebaseOptions ay hindi pa configured para sa platform na ito.",
        );
    }
  }
}
