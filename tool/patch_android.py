"""CI'da `flutter create` sonrası Android iskeletini Shake Rack için ayarlar.

- minSdk 23 (Firebase)
- uygulama adı "Shake Rack"
- INTERNET + REQUEST_INSTALL_PACKAGES izinleri (uygulama içi güncelleme)
- release derlemesini sabit imza anahtarıyla (android/app/upload.jks) imzalar

Bir adım uygulanamazsa hata verip derlemeyi durdurur; böylece yanlış imzalı
APK hiçbir zaman yayınlanmaz (yanlış imza = telefonda güncelleme kurulamaz).
"""
import pathlib
import re
import sys

app = pathlib.Path("android/app")


def fail(msg):
    print(f"::error::{msg}")
    sys.exit(1)


# ---------- build.gradle(.kts) ----------
kts = app / "build.gradle.kts"
groovy = app / "build.gradle"
gradle = kts if kts.exists() else groovy
if not gradle.exists():
    fail("android/app/build.gradle(.kts) bulunamadı")
t = gradle.read_text()

t = t.replace("minSdk = flutter.minSdkVersion", "minSdk = 23")
t = t.replace("minSdkVersion flutter.minSdkVersion", "minSdkVersion 23")

if "upload.jks" not in t:
    if gradle is kts:
        block = '''    signingConfigs {
        create("release") {
            storeFile = file("upload.jks")
            storePassword = System.getenv("SR_STORE_PASSWORD")
            keyAlias = "shakerack"
            keyPassword = System.getenv("SR_STORE_PASSWORD")
        }
    }

'''
        new, n = re.subn(r'signingConfig = signingConfigs\.getByName\("debug"\)',
                         'signingConfig = signingConfigs.getByName("release")', t)
    else:
        block = '''    signingConfigs {
        release {
            storeFile file("upload.jks")
            storePassword System.getenv("SR_STORE_PASSWORD")
            keyAlias "shakerack"
            keyPassword System.getenv("SR_STORE_PASSWORD")
        }
    }

'''
        new, n = re.subn(r'signingConfig signingConfigs\.debug',
                         'signingConfig signingConfigs.release', t)
    if n == 0:
        fail("release imza satırı bulunamadı (Flutter şablonu değişmiş olabilir)")
    idx = new.find("    buildTypes {")
    if idx < 0:
        fail("buildTypes bloğu bulunamadı")
    t = new[:idx] + block + new[idx:]

# Yerel kütüphaneleri sıkıştırarak paketle → indirme boyutu ~%40 küçülür
if "useLegacyPackaging" not in t:
    pack = ('''    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

''' if gradle is kts else '''    packagingOptions {
        jniLibs {
            useLegacyPackaging true
        }
    }

''')
    idx = t.find("    buildTypes {")
    if idx < 0:
        fail("buildTypes bloğu bulunamadı (sıkıştırma eklenemedi)")
    t = t[:idx] + pack + t[idx:]

gradle.write_text(t)
print(f"✓ {gradle}: minSdk 23 + sabit imza + sıkıştırılmış kütüphaneler")

# ---------- AndroidManifest.xml ----------
mf = app / "src/main/AndroidManifest.xml"
m = mf.read_text()
m = re.sub(r'android:label="[^"]*"', 'android:label="Shake Rack"', m)
perms = [
    "android.permission.INTERNET",
    "android.permission.REQUEST_INSTALL_PACKAGES",
]
for p in perms:
    if p not in m:
        m = m.replace("<application", f'<uses-permission android:name="{p}"/>\n    <application', 1)
# Davet bağlantısı: shakerack://join?k=KOD uygulamayı açar
if 'android:scheme="shakerack"' not in m:
    link = '''            <intent-filter>
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="shakerack" android:host="join"/>
            </intent-filter>
            <meta-data android:name="flutter_deeplinking_enabled" android:value="false"/>
'''
    i = m.find("</activity>")
    if i < 0:
        fail("MainActivity bulunamadı (davet bağlantısı eklenemedi)")
    m = m[:i] + link + "        " + m[i:]
mf.write_text(m)
print("✓ AndroidManifest: ad + izinler + davet bağlantısı")

# ---------- iOS görünen ad ----------
plist = pathlib.Path("ios/Runner/Info.plist")
if plist.exists():
    s = plist.read_text()
    s = re.sub(r'(<key>CFBundleDisplayName</key>\s*<string>)[^<]*', r'\1Shake Rack', s)
    plist.write_text(s)
    print("✓ iOS görünen ad")
