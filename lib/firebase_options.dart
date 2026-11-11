// Firebase ayarları — google-services.json (shake-rack projesi) değerlerinden.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    if (defaultTargetPlatform == TargetPlatform.android) return android;
    // iOS yerel uygulaması yok (iPhone'da web sürümü kullanılıyor).
    throw UnsupportedError('Bu platform için Firebase ayarı yok.');
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBSOhGTXR83mlRLoKpc3cOG6dRFqdRegKU',
    appId: '1:495109861227:android:16b6be3cc0f7ea38a7662e',
    messagingSenderId: '495109861227',
    projectId: 'shake-rack',
    storageBucket: 'shake-rack.firebasestorage.app',
  );

  /// Web sürümü (iPhone vb.): https://emolibor.github.io/shake-rack/app/
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBakj2xq_EduIktEKvGO8lc2V9SvugWemM',
    appId: '1:495109861227:web:77def1a56195141ca7662e',
    messagingSenderId: '495109861227',
    projectId: 'shake-rack',
    authDomain: 'shake-rack.firebaseapp.com',
    storageBucket: 'shake-rack.firebasestorage.app',
    measurementId: 'G-2HGLBZ8YEN',
  );
}
