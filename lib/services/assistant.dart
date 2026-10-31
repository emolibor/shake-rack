import '../models/models.dart';
import 'store.dart';

/// Mesaj ekranındaki basit asistan. İnternet gerektirmez; soruları
/// anahtar kelimeyle anlar ve öncelik sırasına göre (ipteki sıra) cevaplar.
class RackAssistant {
  final RackStore store;
  RackAssistant(this.store);

  /// Sorudaki kelime → proje türü. "yangın" tek başına üç yangın projesini kapsar.
  static const Map<String, List<String>> _typeKeys = {
    'mimari': ['Mimari Proje'],
    'elektri': ['Elektrik Projesi'], // elektrik / elektriği / elektrikler
    'algilama': ['Yangın Algılama Projesi'],
    'sondurme': ['Yangın Söndürme Tesisatı Projesi'],
    'tesisat': ['Yangın Söndürme Tesisatı Projesi'],
    'sprink': ['Yangın Söndürme Tesisatı Projesi'],
    'havalandirma': ['Havalandırma Projesi'],
    'kacis': ['Yangın Kaçış Projesi'],
    'raf': ['Raf Yerleşim Projesi'],
    'paratoner': ['Paratoner Projesi'],
    'yildirim': ['Paratoner Projesi'],
  };

  /// Sorudan proje türlerini çıkar. Boş set = filtre yok.
  Set<String> _typesIn(String q) {
    final out = <String>{};
    _typeKeys.forEach((k, v) {
      if (_word(q, k)) out.addAll(v);
    });
    if (out.isEmpty && _word(q, 'yangin')) {
      out.addAll([
        'Yangın Algılama Projesi',
        'Yangın Söndürme Tesisatı Projesi',
        'Yangın Kaçış Projesi',
      ]);
    }
    return out;
  }

  /// Sorudan kişi çıkar: "benim/bende/bana" → bu telefonun sahibi, ya da kişi adı.
  String? _memberIn(String q) {
    for (final m in store.members) {
      final n = _norm(m.name).trim();
      if (n.isEmpty) continue;
      if (n.contains(' ') ? q.contains(n) : _word(q, n)) return m.id;
    }
    if (_word(q, 'benim') || _word(q, 'bende') || _word(q, 'bana')) {
      return store.currentMemberId;
    }
    return null;
  }

  String answer(String raw) {
    final q = _norm(raw);
    final types = _typesIn(q);
    final member = _memberIn(q);

    final asksDone = _has(q, ['tamamlanan', 'biten', 'bitti', 'bitirdik', 'yaptik', 'yapilan', 'cizilen', 'cizdik']);
    final asksLeft = _has(q, ['kalan', 'kaldi', 'ne kaldi', 'hangi proje', 'eksik', 'bitmeyen', 'yapilacak', 'cizilecek', 'bekleyen']);

    // firma adı geçiyorsa ("Atilla Tekstil'in elektriği kaldı mı") → o firmanın kartı
    for (final c in store.cards) {
      final n = _norm(c.name).trim();
      if (n.isNotEmpty && q.contains(n)) return _cardDetail(c);
    }

    if (asksLeft) return _remaining(types: types, member: member);
    if (asksDone && (types.isNotEmpty || member != null)) {
      return _doneItems(types: types, member: member);
    }
    if (asksDone) return _completed();
    // sadece tür ya da kişi yazıldıysa ("elektrik?", "arkadaşımda ne var") → kalanlar
    if (types.isNotEmpty) return _remaining(types: types, member: member);
    if (_has(q, ['ozet', 'durum', 'genel', 'nasil gidiyor'])) {
      return _summary();
    }
    if (_has(q, ['kim', 'kimde', 'kimin'])) {
      return _whoHasWhat();
    }
    if (_has(q, ['oncelik', 'ilk', 'sirada', 'once ne'])) {
      return _priority();
    }
    // sadece kişi geçtiyse ("arkadaşımda ne var") → o kişinin kalan işleri
    if (member != null) return _remaining(member: member);
    if (_has(q, ['merhaba', 'selam', 'hey', 'yardim', 'ne sorabilirim'])) {
      return _help;
    }
    return 'Anlamadım.\n\n$_help';
  }

  // ----- cevaplar -----

  /// "Elektrik", "Yangın Algılama ve Elektrik" gibi okunur başlık.
  String _typesLabel(Set<String> types) {
    final names = kProjectTypes
        .where(types.contains)
        .map((t) => kShortNames[t] ?? t)
        .toList();
    if (names.length <= 1) return names.join();
    return '${names.sublist(0, names.length - 1).join(', ')} ve ${names.last}';
  }

  String _remaining({Set<String> types = const {}, String? member}) {
    final who = store.memberById(member);
    final rows = <String>[];
    var total = 0;
    for (final c in store.active) {
      if (member != null && c.assignedTo != member) continue;
      final rem = c.remaining
          .where((e) => types.isEmpty || types.contains(e.type))
          .toList();
      if (rem.isEmpty) continue;
      total += rem.length;
      final owner = store.memberById(c.assignedTo);
      // tek tür sorulduysa tür adını tekrar yazmaya gerek yok
      final detail = types.length == 1
          ? ''
          : ': ${rem.map((e) => kShortNames[e.type] ?? e.type).join(', ')}';
      final ownerTxt = (owner != null && member == null) ? ' (${owner.name})' : '';
      rows.add('${rows.length + 1}. ${c.name}$ownerTxt$detail');
    }

    final what = types.isEmpty ? 'proje' : '${_typesLabel(types)} projesi';
    final whose = who != null ? '${who.name} için ' : '';
    if (rows.isEmpty) {
      return types.isEmpty && who == null
          ? 'İpte kalan iş yok, her şey tamam! 🎉'
          : _cap('$whose$what kalmadı 🎉');
    }
    final head = types.isEmpty && who == null
        ? 'Öncelik sırana göre kalanlar:'
        : _cap('$whose$what kalan firmalar (öncelik sırasıyla):');
    return '$head\n${rows.join('\n')}\n\nToplam ${rows.length} firma, $total $what.';
  }

  /// Belirli tür/kişi için çizilmiş projeler (aktif ve tamamlanan kartlarda).
  String _doneItems({Set<String> types = const {}, String? member}) {
    final who = store.memberById(member);
    final rows = <String>[];
    for (final c in store.cards) {
      final done = c.items
          .where((e) =>
              e.done &&
              (types.isEmpty || types.contains(e.type)) &&
              (member == null || e.doneBy == member))
          .toList();
      if (done.isEmpty) continue;
      final detail = done.map((e) {
        final by = member == null ? store.memberById(e.doneBy) : null;
        return '${kShortNames[e.type] ?? e.type}${by != null ? ' — ${by.name}' : ''}';
      }).join(', ');
      rows.add('• ${c.name}: $detail');
    }
    final what = types.isEmpty ? 'proje' : '${_typesLabel(types)} projesi';
    final whose = who != null ? '${who.name} tarafından ' : '';
    if (rows.isEmpty) return 'Henüz ${whose}çizilmiş $what yok.';
    return _cap('${whose}çizilen $what (${rows.length} firma):\n${rows.join('\n')}');
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

  static const _help = 'Şunları sorabilirsin:\n'
      '• Hangi projeler kaldı?\n'
      '• Hangi firmaların elektrik projesi kaldı?\n'
      '• Yangın projeleri kalan firmalar?\n'
      '• Arkadaşımın mimari projeleri kaldı mı?\n'
      '• Hangi firmaların algılaması bitti?\n'
      '• Neler tamamlandı? · Durum ne? · Kimde ne var?\n'
      '• Firma adı yaz, detayını vereyim.';

  static String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// Kelime başı eşleşmesi: "elektriği" → elektrik ✓, "tarafından" → raf ✗
  static bool _word(String q, String key) =>
      RegExp('(^|[^a-z0-9])${RegExp.escape(key)}').hasMatch(q);

  // ----- yardımcılar -----
  static String _norm(String s) => s
      .replaceAll('İ', 'i')
      .replaceAll('I', 'ı')
      .toLowerCase()
      .replaceAll('̇', '') // "i̇" birleşik noktayı at
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
