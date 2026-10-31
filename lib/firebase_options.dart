// GEÇİCİ DOSYA — `flutterfire configure` komutu bunu kendi projenin
// gerçek anahtarlarıyla üzerine yazar. Bu hâliyle Firebase başlatılamaz,
// uygulama yerel modda çalışır.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    throw UnsupportedError(
      'firebase_options.dart henüz üretilmedi. README: flutterfire configure',
    );
  }
}
