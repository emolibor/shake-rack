# Shake Rack

İpe asılı not kartlarıyla firma proje takibi (Flutter).

## Telefona kurulum (Android)

Her `main` push'unda GitHub Actions APK derler ve **Releases → "Shake Rack (son sürüm)"**
altına `shake-rack.apk` olarak koyar. Telefondan o dosyayı indirip aç, kur.
(İlk seferde "bilinmeyen kaynaklardan yüklemeye izin ver" demen gerekir.)

Elle yeniden derletmek için: **Actions → Android APK → Run workflow**.

### Otomatik güncelleme

Uygulama açılışta `releases/download/latest/version.json` dosyasına bakar; yeni sürüm varsa
"Güncelle" diyaloğu çıkar, APK'yı indirip Android kurulum ekranını açar. Elle kontrol:
**Ekip → Güncellemeleri denetle**. Bunun çalışması için repo **public** olmalı.

### İmza anahtarı

Güncellemelerin eski sürümün üzerine kurulabilmesi için her APK aynı anahtarla imzalanır.
Anahtar repoda değil, **Settings → Secrets and variables → Actions** altında
`SHAKE_RACK_SIGNING` adlı secret'ta durur (içerik: `şifre|keystore_base64`).
Secret yoksa derleme yapılır ama yayınlanmaz. Anahtarın yedeğini kaybetme: kaybolursa
telefonlardaki uygulamayı silip yeniden kurmak gerekir.

## Geliştirme (bilgisayarda)

```bash
git clone https://github.com/emolibor/shake-rack && cd shake-rack
# android/ios iskeletini üret (lib/ ve pubspec.yaml'a dokunmaz)
flutter create --org com.fourmis --project-name shake_rack --platforms android,ios .
flutter pub get
dart run flutter_launcher_icons
flutter run
```

## Yapı

| Dosya | İş |
|---|---|
| `lib/models/models.dart` | Proje türleri, kişi (renk), firma kartı |
| `lib/services/store.dart` | Tüm durum + telefona JSON kayıt (shared_preferences) |
| `lib/services/assistant.dart` | Mesaj ekranındaki soru-cevap mantığı |
| `lib/widgets/rope_card.dart` | İp, mandal, kağıt kart, askılık logosu |
| `lib/screens/rack_screen.dart` | Ana ekran: sürükle-bırak sıralama, tik, balon + konfeti |
| `lib/screens/card_edit_screen.dart` | Kart ekle/düzenle, proje seç, kişi ata, not |
| `lib/screens/completed_screen.dart` | Tamamlananlar |
| `lib/screens/chat_screen.dart` | Mesaj |
| `lib/screens/team_screen.dart` | Ekip: aktif kişi, isim, renk |

## Uygulama ikonu

`HangerLogo` widget'ı (rope_card.dart) askılık sembolünü çizer. Mağaza ikonu için aynı
şekli bir PNG'ye çevirip `flutter_launcher_icons` paketiyle uygulayabilirsin.

## İki telefon senkronu (Firebase)

Uygulama Firebase olmadan da çalışır (yerel mod). Ortak askılık için bir kere kurulum:

1. https://console.firebase.google.com → yeni proje (ör. `shake-rack`).
2. Sol menü **Firestore Database → Veritabanı oluştur** (production mode, bölge: europe-west).
3. **Kurallar** sekmesine bu klasördeki `firestore.rules` içeriğini yapıştır → Yayınla.
4. Bilgisayarında:
   ```bash
   npm install -g firebase-tools
   firebase login
   dart pub global activate flutterfire_cli
   cd shake_rack
   flutterfire configure        # Android + iOS seç → lib/firebase_options.dart üretilir
   flutter pub get
   flutter run
   ```
   Android'de `minSdkVersion` 21+ ve iOS'ta deployment target 13+ olmalı (flutterfire uyarırsa artır).
5. Uygulamada **Ekip** sekmesi → **Ortak askılık** → ikiniz de aynı kodu girin (ör. `fourmis-proje`) → Bağlan.

Çalışma mantığı: tüm kartlar `racks/{kod}` tek belgesinde tutulur, her değişiklik 300 ms
sonra buluta yazılır, karşı taraf canlı dinler. İnternet yoksa yerelde saklanır, gelince eşitlenir.
Hangi kişinin telefonu olduğu (Ekip → radyo seçimi) cihaza özeldir, buluta gitmez.

Kodu bilen herkes askılığı görebilir; kodu 6+ karakter ve tahmin edilmesi zor tut.
