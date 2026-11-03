import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shake_rack/services/assistant.dart';
import 'package:shake_rack/services/report.dart';
import 'package:shake_rack/services/store.dart';

/// Mesaj ekranındaki soruların doğru süzüldüğünü kontrol eder.
void main() {
  late RackStore store;
  late RackAssistant bot;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = RackStore();
    // Sıra = öncelik: Örnek, Mavi Ambalaj, Kuzey Lojistik
    final ornek = store.addCard('Örnek Tekstil',
        ['Mimari Proje', 'Elektrik Projesi', 'Yangın Algılama Projesi']);
    store.addCard('Mavi Ambalaj', ['Elektrik Projesi', 'Raf Yerleşim Projesi'],
        assignedTo: 'friend');
    store.addCard('Kuzey Lojistik', ['Mimari Proje', 'Paratoner Projesi']);
    // Örnek'nın elektriğini Kullanıcı 1 çizdi
    store.toggleItem(ornek, ornek.items[1]);
    bot = RackAssistant(store);
  });

  void show(String q) {
    // ignore: avoid_print
    print('\n> $q\n${bot.answer(q)}');
  }

  test('elektrik projesi kalanlar sadece Mavi Ambalaj', () {
    const q = 'hangi firmaların elektrik projeleri kaldı';
    show(q);
    final a = bot.answer(q);
    expect(a, contains('Mavi Ambalaj'));
    expect(a, isNot(contains('Örnek')));
    expect(a, isNot(contains('Kuzey')));
  });

  test('büyük harf ve Türkçe karakter', () {
    final a = bot.answer('HANGİ FİRMALARIN ELEKTRİĞİ KALDI?');
    expect(a, contains('Mavi Ambalaj'));
    expect(a, isNot(contains('Örnek')));
  });

  test('mimari kalanlar öncelik sırasıyla', () {
    final a = bot.answer('mimari projesi kalan firmalar');
    show('mimari projesi kalan firmalar');
    expect(a.indexOf('Örnek'), lessThan(a.indexOf('Kuzey')));
    expect(a, isNot(contains('Mavi Ambalaj')));
  });

  test('yangın tek başına tüm yangın projelerini kapsar', () {
    final a = bot.answer('yangın projeleri ne durumda kalan');
    expect(a, contains('Örnek'));
    expect(a, isNot(contains('Mavi Ambalaj')));
  });

  test('"tarafından" raf sanılmaz, kullanıcı adıyla süzer', () {
    final a = bot.answer('Kullanıcı 2 tarafından çizilecek kalan işler');
    show('Kullanıcı 2 tarafından çizilecek kalan işler');
    expect(a, contains('Mavi Ambalaj'));
    expect(a, isNot(contains('Örnek')));
  });

  test('biten elektrik projeleri', () {
    final a = bot.answer('hangi firmaların elektriği bitti');
    show('hangi firmaların elektriği bitti');
    expect(a, contains('Örnek'));
    expect(a, isNot(contains('Mavi Ambalaj')));
  });

  test('firma adı → kart detayı', () {
    final a = bot.answer("Örnek Tekstil'in elektriği kaldı mı");
    expect(a, contains('✅ Elektrik Projesi'));
    expect(a, contains('⬜ Mimari Proje'));
  });

  test('genel kalanlar hepsini listeler', () {
    final a = bot.answer('hangi projeler kaldı');
    show('hangi projeler kaldı');
    expect(a, contains('Örnek'));
    expect(a, contains('Mavi Ambalaj'));
    expect(a, contains('Kuzey'));
  });

  test('paratoner hiç kalmadıysa söyler', () {
    final kuzey = store.active.firstWhere((c) => c.name == 'Kuzey Lojistik');
    store.toggleItem(kuzey, kuzey.items[1]);
    final a = bot.answer('paratoner kalan var mı');
    show('paratoner kalan var mı');
    expect(a, contains('kalmadı'));
  });

  group('Tasarlanmış liste (rapor)', () {
    test('kalanlar raporu: sıra, kalan etiketler, ilerleme, kişi', () {
      final r = bot.reply('hangi projeler kaldı').report!;
      expect(r.title, 'Kalan Projeler');
      expect(r.style, ReportStyle.remaining);
      expect(r.rows.map((e) => e.title), ['Örnek Tekstil', 'Mavi Ambalaj', 'Kuzey Lojistik']);
      final ornek = r.rows.first;
      expect(ornek.items, ['Mimari', 'Yangın Algılama']); // elektrik bitti
      expect(ornek.done, 1);
      expect(ornek.total, 3);
      expect(r.rows[1].owner, 'Kullanıcı 2');
      expect(r.summary, '3 firma · 6 proje kaldı');
    });

    test('süzülmüş rapor başlığı ve metin çıktısı', () {
      final r = bot.reply('hangi firmaların elektrik projeleri kaldı').report!;
      expect(r.title, 'Kalan Elektrik Projeleri');
      expect(r.subtitle, startsWith('Elektrik'));
      expect(r.rows.single.title, 'Mavi Ambalaj');
      final txt = r.toText();
      expect(txt, startsWith('*Kalan Elektrik Projeleri*'));
      expect(txt, contains('1. *Mavi Ambalaj* (Kullanıcı 2)'));
      expect(r.fileBase, startsWith('kalan-elektrik-projeleri-'));
    });

    test('bitenler raporu yeşil stilde', () {
      final r = bot.reply('hangi firmaların elektriği bitti').report!;
      expect(r.style, ReportStyle.done);
      expect(r.rows.single.title, 'Örnek Tekstil');
    });

    test('sohbet cevaplarında rapor yok', () {
      expect(bot.reply('merhaba').report, isNull);
      expect(bot.reply("Örnek Tekstil'in durumu").report, isNull);
    });
  });
}
