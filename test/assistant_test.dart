import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shake_rack/services/assistant.dart';
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
    // Atilla'nın elektriğini "Ben" çizdi
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

  test('"tarafından" raf sanılmaz', () {
    final a = bot.answer('arkadaşım tarafından çizilecek kalan işler');
    show('arkadaşım tarafından çizilecek kalan işler');
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
}
