import '../models/models.dart';
import 'store.dart';

/// Mesaj ekranındaki basit asistan. İnternet gerektirmez; soruları
/// anahtar kelimeyle anlar ve öncelik sırasına göre (ipteki sıra) cevaplar.
class RackAssistant {
  final RackStore store;
  RackAssistant(this.store);

  String answer(String raw) {
    final q = _norm(raw);

    if (_has(q, ['kalan', 'kaldi', 'ne kaldi', 'hangi proje', 'eksik', 'bitmeyen', 'yapilacak'])) {
      return _remaining();
    }
    if (_has(q, ['tamamlanan', 'biten', 'bitti', 'bitirdik', 'yaptik'])) {
      return _completed();
    }
    if (_has(q, ['ozet', 'durum', 'genel', 'nasil gidiyor'])) {
      return _summary();
    }
    if (_has(q, ['kim', 'kimde', 'kimin'])) {
      return _whoHasWhat();
    }
    if (_has(q, ['oncelik', 'ilk', 'sirada', 'once ne'])) {
      return _priority();
    }
    // firma adı geçiyor mu?
    for (final c in store.cards) {
      if (q.contains(_norm(c.name))) return _cardDetail(c);
    }
    if (_has(q, ['merhaba', 'selam', 'hey'])) {
      return 'Selam! Şunları sorabilirsin:\n• Hangi projeler kaldı?\n• Neler tamamlandı?\n• Genel durum ne?\n• Kimde hangi iş var?\n• Sıradaki ne?\n• Bir firma adı yaz, detayını vereyim.';
    }
    return 'Anlamadım. "Hangi projeler kaldı?", "Neler tamamlandı?", "Durum ne?", "Kimde ne var?" diye sorabilir ya da bir firma adı yazabilirsin.';
  }

  // ----- cevaplar -----

  String _remaining() {
    final act = store.active.where((c) => c.remaining.isNotEmpty).toList();
    if (act.isEmpty) return 'İpte kalan iş yok, her şey tamam! 🎉';
    final b = StringBuffer('Öncelik sırana göre kalanlar:\n');
    var i = 1;
    var total = 0;
    for (final c in act) {
      final rem = c.remaining.map((e) => kShortNames[e.type] ?? e.type).join(', ');
      total += c.remaining.length;
      final who = store.memberById(c.assignedTo);
      b.writeln('$i. ${c.name}${who != null ? ' (${who.name})' : ''}: $rem');
      i++;
    }
    b.write('\nToplam ${act.length} firma, $total proje kaldı.');
    return b.toString();
  }

  String _completed() {
    final done = store.completed;
    if (done.isEmpty) return 'Henüz tamamlanan firma yok.';
    final b = StringBuffer('Tamamlananlar (${done.length}):\n');
    for (final c in done) {
      b.writeln('• ${c.name} — ${c.items.length} proje');
    }
    return b.toString();
  }

  String _summary() {
    final act = store.active;
    final remItems = act.fold<int>(0, (s, c) => s + c.remaining.length);
    final doneItems = store.cards
        .fold<int>(0, (s, c) => s + c.items.where((i) => i.done).length);
    final b = StringBuffer();
    b.writeln('İpte ${act.length} firma asılı, ${store.completed.length} firma tamamlandı.');
    b.writeln('Kalan proje: $remItems · Biten proje: $doneItems');
    if (act.isNotEmpty) {
      b.writeln('\nSıradaki: ${act.first.name} → ${act.first.remaining.map((e) => kShortNames[e.type]).join(', ')}');
    }
    // kişi bazlı
    for (final m in store.members) {
      final n = store.cards
          .fold<int>(0, (s, c) => s + c.items.where((i) => i.doneBy == m.id).length);
      b.writeln('${m.name}: $n proje çizdi');
    }
    return b.toString().trim();
  }

  String _whoHasWhat() {
    final b = StringBuffer();
    for (final m in store.members) {
      final mine = store.active.where((c) => c.assignedTo == m.id).toList();
      b.writeln('${m.name}:');
      if (mine.isEmpty) {
        b.writeln('  —');
      } else {
        for (final c in mine) {
          b.writeln('  • ${c.name}: ${c.remaining.map((e) => kShortNames[e.type]).join(', ')}');
        }
      }
    }
    final unassigned = store.active.where((c) => c.assignedTo == null).toList();
    if (unassigned.isNotEmpty) {
      b.writeln('Atanmamış: ${unassigned.map((c) => c.name).join(', ')}');
    }
    return b.toString().trim();
  }

  String _priority() {
    final act = store.active;
    if (act.isEmpty) return 'Sırada bir şey yok.';
    final top = act.take(3).toList();
    final b = StringBuffer('İlk sıradakiler:\n');
    for (var i = 0; i < top.length; i++) {
      b.writeln('${i + 1}. ${top[i].name} → ${top[i].remaining.map((e) => kShortNames[e.type]).join(', ')}');
    }
    return b.toString().trim();
  }

  String _cardDetail(CompanyCard c) {
    final b = StringBuffer('${c.name}${c.completed ? ' (tamamlandı)' : ''}\n');
    for (final it in c.items) {
      final who = store.memberById(it.doneBy);
      b.writeln('${it.done ? '✅' : '⬜'} ${it.type}${who != null ? ' — ${who.name}' : ''}');
    }
    if (c.notes.isNotEmpty) b.writeln('\nNot: ${c.notes}');
    return b.toString().trim();
  }

  // ----- yardımcılar -----
  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll('ı', 'i')
      .replaceAll('ş', 's')
      .replaceAll('ğ', 'g')
      .replaceAll('ü', 'u')
      .replaceAll('ö', 'o')
      .replaceAll('ç', 'c')
      .replaceAll('İ', 'i');

  static bool _has(String q, List<String> keys) =>
      keys.any((k) => q.contains(_norm(k)));
}
