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
    // Sıra = öncelik: Atilla, Cupplast, Demir Lojistik
    final atilla = store.addCard('Atilla Tekstil',
        ['Mimari Proje', 'Elektrik Projesi', 'Yangın Algılama Projesi']);
    store.addCard('Cupplast', ['Elektrik Projesi', 'Raf Yerleşim Projesi'],
        assignedTo: 'friend');
    store.addCard('Demir Lojistik', ['Mimari Proje', 'Paratoner Projesi']);
    // Atilla'nın elektriğini Kullanıcı 1 çizdi
    store.toggleItem(atilla, atilla.items[1]);
    bot = RackAssistant(store);
  });

  void show(String q) {
    // ignore: avoid_print
    print('\n> $q\n${bot.answer(q)}');
  }

  test('elektrik projesi kalanlar sadece Cupplast', () {
    const q = 'hangi firmaların elektrik projeleri kaldı';
    show(q);
    final a = bot.answer(q);
    expect(a, contains('Cupplast'));
    expect(a, isNot(contains('Atilla')));
    expect(a, isNot(contains('Demir')));
  });

  test('büyük harf ve Türkçe karakter', () {
    final a = bot.answer('HANGİ FİRMALARIN ELEKTRİĞİ KALDI?');
    expect(a, contains('Cupplast'));
    expect(a, isNot(contains('Atilla')));
  });

  test('mimari kalanlar öncelik sırasıyla', () {
    final a = bot.answer('mimari projesi kalan firmalar');
    show('mimari projesi kalan firmalar');
    expect(a.indexOf('Atilla'), lessThan(a.indexOf('Demir')));
    expect(a, isNot(contains('Cupplast')));
  });

  test('yangın tek başına tüm yangın projelerini kapsar', () {
    final a = bot.answer('yangın projeleri ne durumda kalan');
    expect(a, contains('Atilla'));
    expect(a, isNot(contains('Cupplast')));
  });

  test('"tarafından" raf sanılmaz, kullanıcı adıyla süzer', () {
    final a = bot.answer('Kullanıcı 2 tarafından çizilecek kalan işler');
    show('Kullanıcı 2 tarafından çizilecek kalan işler');
    expect(a, contains('Cupplast'));
    expect(a, isNot(contains('Atilla')));
  });

  test('biten elektrik projeleri', () {
    final a = bot.answer('hangi firmaların elektriği bitti');
    show('hangi firmaların elektriği bitti');
    expect(a, contains('Atilla'));
    expect(a, isNot(contains('Cupplast')));
  });

  test('firma adı → kart detayı', () {
    final a = bot.answer("Atilla Tekstil'in elektriği kaldı mı");
    expect(a, contains('✅ Elektrik Projesi'));
    expect(a, contains('⬜ Mimari Proje'));
  });

  test('genel kalanlar hepsini listeler', () {
    final a = bot.answer('hangi projeler kaldı');
    show('hangi projeler kaldı');
    expect(a, contains('Atilla'));
    expect(a, contains('Cupplast'));
    expect(a, contains('Demir'));
  });

  test('paratoner hiç kalmadıysa söyler', () {
    final demir = store.active.firstWhere((c) => c.name == 'Demir Lojistik');
    store.toggleItem(demir, demir.items[1]);
    final a = bot.answer('paratoner kalan var mı');
    show('paratoner kalan var mı');
    expect(a, contains('kalmadı'));
  });

  group('Tasarlanmış liste (rapor)', () {
    test('kalanlar raporu: sıra, kalan etiketler, ilerleme, kişi', () {
      final r = bot.reply('hangi projeler kaldı').report!;
      expect(r.title, 'Kalan Projeler');
      expect(r.style, ReportStyle.remaining);
      expect(r.rows.map((e) => e.title), ['Atilla Tekstil', 'Cupplast', 'Demir Lojistik']);
      final atilla = r.rows.first;
      expect(atilla.items, ['Mimari', 'Yangın Algılama']); // elektrik bitti
      expect(atilla.done, 1);
      expect(atilla.total, 3);
      expect(r.rows[1].owner, 'Kullanıcı 2');
      expect(r.summary, '3 firma · 6 proje kaldı');
    });

    test('süzülmüş rapor başlığı ve metin çıktısı', () {
      final r = bot.reply('hangi firmaların elektrik projeleri kaldı').report!;
      expect(r.title, 'Kalan Elektrik Projeleri');
      expect(r.subtitle, startsWith('Elektrik'));
      expect(r.rows.single.title, 'Cupplast');
      final txt = r.toText();
      expect(txt, startsWith('*Kalan Elektrik Projeleri*'));
      expect(txt, contains('1. *Cupplast* (Kullanıcı 2)'));
      expect(r.fileBase, startsWith('kalan-elektrik-projeleri-'));
    });

    test('bitenler raporu yeşil stilde', () {
      final r = bot.reply('hangi firmaların elektriği bitti').report!;
      expect(r.style, ReportStyle.done);
      expect(r.rows.single.title, 'Atilla Tekstil');
    });

    test('sohbet cevaplarında rapor yok', () {
      expect(bot.reply('merhaba').report, isNull);
      expect(bot.reply("Atilla Tekstil'in durumu").report, isNull);
    });
  });
}
