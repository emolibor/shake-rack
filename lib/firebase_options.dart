// Firebase ayarları — google-services.json (shake-rack projesi) değerlerinden.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return android;
    }
    // iOS / web henüz eklenmedi → uygulama yerel modda çalışır.
    throw UnsupportedError('Bu platform için Firebase ayarı yok.');
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBSOhGTXR83mlRLoKpc3cOG6dRFqdRegKU',
    appId: '1:495109861227:android:16b6be3cc0f7ea38a7662e',
    messagingSenderId: '495109861227',
    projectId: 'shake-rack',
    storageBucket: 'shake-rack.firebasestorage.app',
  );
}
