import '../models/models.dart';
import 'report.dart';
import 'store.dart';

/// Mesaj ekranındaki basit asistan. İnternet gerektirmez; soruları
/// anahtar kelimeyle anlar ve öncelik sırasına göre (ipteki sıra) cevaplar.
class RackAssistant {
  final RackStore store;
  RackAssistant(this.store);

  /// Eş anlamlılar: sorudaki kelime → bu kelimeyi içeren proje türü kelimesi.
  static const Map<String, String> _synonyms = {
    'sprink': 'sondurme',
    'yildirim': 'paratoner',
  };

  static const _stop = {'projesi', 'proje', 'projeleri', 've', 'ile'};

  /// Bir kelimenin kökü: ekli halleri yakalamak için son harf atılır
  /// (elektrik → elektri: "elektriği" ✓, mimari → mimar: "mimarisi" ✓).
  static String _stem(String w) => w.length > 5 ? w.substring(0, w.length - 1) : w;

  /// Sorudan proje türlerini çıkar (Projeler askılığındaki GÜNCEL maddelerden).
  /// Boş set = filtre yok. Birden fazla türde geçen kelime ("yangın") hepsini
  /// kapsar; daha özel bir kelime ("algılama") varsa yalnız o tür seçilir.
  Set<String> _typesIn(String q) {
    final template = store.projects.template;
    final words = <String, List<String>>{}; // tür → kelimeler
    final freq = <String, int>{};
    for (final t in template) {
      final ws = _norm(t)
          .split(RegExp(r'[^a-z0-9]+'))
          .where((w) => w.length >= 3 && !_stop.contains(w))
          .toSet()
          .toList();
      words[t] = ws;
      for (final w in ws) {
        freq[w] = (freq[w] ?? 0) + 1;
      }
    }
    var qn = q;
    _synonyms.forEach((k, v) {
      if (_word(qn, k)) qn = '$qn $v';
    });

    final specific = <String>{};
    final shared = <String>{};
    words.forEach((t, ws) {
      for (final w in ws) {
        if (_word(qn, _stem(w))) {
          (freq[w]! > 1 ? shared : specific).add(t);
        }
      }
    });
    return specific.isNotEmpty ? specific : shared;
  }

  /// Sorudan kişi çıkar: "benim/bende/bana" → bu telefonun sahibi, ya da kişi adı.
  String? _memberIn(String q) {
    // uzun isim önce: "kullanıcı 12" sorusu "kullanıcı 1" ile karışmasın
    final sorted = [...store.members]
      ..sort((a, b) => b.name.length.compareTo(a.name.length));
    for (final m in sorted) {
      final n = _norm(m.name).trim();
      if (n.isEmpty) continue;
      if (RegExp('(^|[^a-z0-9])${RegExp.escape(n)}(?![0-9])').hasMatch(q)) {
        return m.id;
      }
    }
    if (_word(q, 'benim') || _word(q, 'bende') || _word(q, 'bana')) {
      return store.currentMemberId;
    }
    return null;
  }

  /// Son cevapta üretilen rapor (liste sorularında).
  Report? _report;

  // ----- kelime süzgeci ("tekstil geçenler", "mavi hariç") -----
  /// Firma adında/notunda geçmesi gereken kelimeler.
  List<String> _incFirm = [];
  /// Firma adında/notunda geçmemesi gereken kelimeler.
  List<String> _excFirm = [];
  /// Listeden çıkarılacak proje türleri ("elektrik hariç").
  Set<String> _excTypes = {};
  /// Raporda gösterilecek süzgeç açıklaması.
  List<String> _filterLabels = [];

  static const _incKeys = {
    'gecen', 'gecenler', 'gecenleri', 'gecenlerin', 'iceren', 'icerenler',
    'icerenleri', 'olan', 'olanlar', 'olanlari',
  };
  static const _excKeys = {
    'haric', 'harici', 'haricindekiler', 'haricinde', 'disinda', 'disindakiler',
    'disindakileri', 'gecmeyen', 'gecmeyenler', 'gecmeyenleri', 'icermeyen',
    'icermeyenler', 'icermeyenleri', 'olmayan', 'olmayanlar', 'olmayanlari',
  };
  /// Kelime ile anahtar arasında kalabilen dolgu kelimeleri.
  static const _fill = {
    'kelimesi', 'kelimeleri', 'kelime', 'ifadesi', 'yazisi', 'ismi', 'adi',
    'isminde', 'adinda', 'icinde', 'firma', 'firmalar', 'firmalari', 'proje',
    'projesi', 'projeleri',
  };
  static const _joiners = {'ve', 'veya', 'ya', 'da', 'ile', 'yada'};

  /// "içinde tekstil geçenleri listele", "mavi ve kuzey hariç", "'örnek a' geçmeyenler"
  /// gibi ifadeleri bulur, süzgece çevirir ve sorudan çıkarır (geri kalan soru
  /// tür/kişi aramasına gider).
  String _parseFilters(String q) {
    _incFirm = [];
    _excFirm = [];
    _excTypes = {};
    _filterLabels = [];
    final inc = <String>[], exc = <String>[];

    // tırnaklı ifade: "mavi ambalaj" geçenler
    q = q.replaceAllMapped(
        RegExp('["“”\'‘’]([^"“”\'‘’]{2,})["“”\'‘’]\\s+([a-z]+)'), (m) {
      final key = m[2]!;
      if (_incKeys.contains(key)) {
        inc.add(m[1]!.trim());
        return ' ';
      }
      if (_excKeys.contains(key)) {
        exc.add(m[1]!.trim());
        return ' ';
      }
      return m[0]!;
    });

    // ek kesme işareti: "mavi'yi" → "mavi"
    final toks = q
        .replaceAll(RegExp("['’][a-z]*"), '')
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final drop = <int>{};
    for (var i = 0; i < toks.length; i++) {
      final isInc = _incKeys.contains(toks[i]);
      final isExc = _excKeys.contains(toks[i]);
      if (!isInc && !isExc) continue;
      // "olan" tek başına çok genel: sadece önünde dolgu/kelime varsa ve
      // "kalan/biten olan" değilse say
      final terms = <String>[];
      var j = i - 1;
      final used = <int>{i};
      while (j >= 0 && _fill.contains(toks[j])) {
        used.add(j);
        j--;
      }
      while (j >= 0) {
        final w = toks[j];
        if (_fill.contains(w) || _incKeys.contains(w) || _excKeys.contains(w)) break;
        terms.add(w);
        used.add(j);
        j--;
        // "x ve y", "x veya y", "x ya da y"
        var k = j;
        while (k >= 0 && _joiners.contains(toks[k])) {
          k--;
        }
        if (k == j || k < 0) break;
        for (var m = k + 1; m <= j; m++) {
          used.add(m);
        }
        j = k;
      }
      terms.removeWhere((w) =>
          w.length < 2 ||
          const {'kalan', 'biten', 'bitmis', 'kalmis', 'hangi', 'icinde'}.contains(w));
      if (terms.isEmpty) continue;
      (isInc ? inc : exc).addAll(terms.reversed);
      drop.addAll(used);
    }
    if (inc.isEmpty && exc.isEmpty) return q;

    // süzgeci ayır: firma adında geçiyorsa firma süzgeci, değilse proje türü
    for (final w in inc) {
      if (_firmMatchesAny(w)) {
        _incFirm.add(w);
        _filterLabels.add('"$w" geçenler');
      } else if (_typesIn(w).isNotEmpty) {
        // tür adı → normal tür süzgecine bırak (sorunun içinde kalsın)
        continue;
      } else {
        _incFirm.add(w); // hiç eşleşmese de dürüstçe "yok" desin
        _filterLabels.add('"$w" geçenler');
      }
    }
    for (final w in exc) {
      final types = _firmMatchesAny(w) ? <String>{} : _typesIn(w);
      if (types.isNotEmpty) {
        _excTypes.addAll(types);
        _filterLabels.add('${_typesLabel(types)} hariç');
      } else {
        _excFirm.add(w);
        _filterLabels.add('"$w" hariç');
      }
    }
    // tür olarak "geçen" kelimeler soruda kalsın, gerisini çıkar
    final keepTypeWords = inc.where((w) => !_incFirm.contains(w)).toSet();
    final rest = <String>[];
    for (var i = 0; i < toks.length; i++) {
      if (!drop.contains(i) || keepTypeWords.contains(toks[i])) rest.add(toks[i]);
    }
    return rest.join(' ');
  }

  bool get _hasFilter =>
      _incFirm.isNotEmpty || _excFirm.isNotEmpty || _excTypes.isNotEmpty;

  /// Firma adı + notunun normalize hali.
  static String _firmText(CompanyCard c) => _norm('${c.name} ${c.notes}');

  static bool _contains(String text, String term) {
    if (text.contains(term)) return true;
    final st = _stem(term);
    return st.length >= 3 &&
        text.split(RegExp(r'[^a-z0-9]+')).any((w) => w.startsWith(st));
  }

  bool _firmMatchesAny(String term) =>
      store.cards.any((c) => _contains(_firmText(c), term));

  /// Kart kelime süzgecinden geçiyor mu?
  bool _cardOk(CompanyCard c) {
    final t = _firmText(c);
    return _incFirm.every((w) => _contains(t, w)) &&
        !_excFirm.any((w) => _contains(t, w));
  }

  /// Proje türü süzgeci (sorulan türler + hariç tutulanlar).
  bool _typeOk(String type, Set<String> types) =>
      (types.isEmpty || types.contains(type)) && !_excTypes.contains(type);

  /// Metin + (varsa) tasarlanmış rapor.
  AssistantReply reply(String raw) {
    _report = null;
    final text = _answer(raw);
    return AssistantReply(text, _report);
  }

  /// Sadece metin cevabı.
  String answer(String raw) => reply(raw).text;

  String _answer(String raw) {
    if (store.projectsHidden) {
      return 'Sohbet, Projeler askılığındaki işleri listeliyor ve şu an o askılık yok.\n\n'
          'Proje takibi yapmak istersen: Askılık → + Yeni → "Ekip projeleri".';
    }
    final q = _parseFilters(_norm(raw));
    final types = _typesIn(q);
    final member = _memberIn(q);

    final asksDone = _has(q, ['tamamlanan', 'biten', 'bitti', 'bitirdik', 'yaptik', 'yapilan', 'cizilen', 'cizdik']);
    final asksLeft = _has(q, ['kalan', 'kaldi', 'ne kaldi', 'hangi proje', 'eksik', 'bitmeyen', 'yapilacak', 'cizilecek', 'bekleyen']);

    // firma adı geçiyorsa ("Örnek Tekstil'in elektriği kaldı mı") → o firmanın kartı
    if (!_hasFilter) {
      for (final c in store.cards) {
        final n = _norm(c.name).trim();
        if (n.isNotEmpty && q.contains(n)) return _cardDetail(c);
      }
    }

    if (asksLeft) return _remaining(types: types, member: member);
    if (asksDone && (types.isNotEmpty || member != null)) {
      return _doneItems(types: types, member: member);
    }
    if (asksDone) return _completed();
    // sadece tür ya da kişi yazıldıysa ("elektrik?", "arkadaşımda ne var") → kalanlar
    if (types.isNotEmpty) return _remaining(types: types, member: member);
    // sadece kelime süzgeci ("tekstil geçenleri listele") → kalanlar
    if (_hasFilter) return _remaining(member: member);
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
    final names = store.projects.template
        .where(types.contains)
        .map((t) => kShortNames[t] ?? t)
        .toList();
    if (names.length <= 1) return names.join();
    return '${names.sublist(0, names.length - 1).join(', ')} ve ${names.last}';
  }

  String _remaining({Set<String> types = const {}, String? member}) {
    final who = store.memberById(member);
    final rows = <String>[];
    final reportRows = <ReportRow>[];
    var total = 0;
    for (final c in store.active) {
      if (member != null && c.assignedTo != member) continue;
      if (!_cardOk(c)) continue;
      final rem = c.remaining.where((e) => _typeOk(e.type, types)).toList();
      if (rem.isEmpty) continue;
      // aynı süzgeçteki biten projeler de raporda yeşil görünsün
      final fin = c.items.where((e) => e.done && _typeOk(e.type, types)).toList();
      total += rem.length;
      final owner = store.memberById(c.assignedTo);
      // tek tür sorulduysa tür adını tekrar yazmaya gerek yok
      final detail = (types.length == 1
              ? ''
              : ': ${rem.map((e) => kShortNames[e.type] ?? e.type).join(', ')}') +
          (fin.isEmpty
              ? ''
              : ' (bitti: ${fin.map((e) => kShortNames[e.type] ?? e.type).join(', ')})');
      final ownerTxt = (owner != null && member == null) ? ' (${owner.name})' : '';
      rows.add('${rows.length + 1}. ${c.name}$ownerTxt$detail');
      reportRows.add(ReportRow(
        title: c.name,
        owner: owner?.name,
        ownerColor: owner?.color,
        items: rem.map((e) => kShortNames[e.type] ?? e.type).toList(),
        doneItems: fin.map((e) => kShortNames[e.type] ?? e.type).toList(),
        done: c.items.where((e) => e.done).length,
        total: c.items.length,
      ));
    }

    final what = types.isEmpty ? 'proje' : '${_typesLabel(types)} projesi';
    final whose = who != null ? '${who.name} için ' : '';
    final fl = _filterLabels.isEmpty ? '' : ' (${_filterLabels.join(', ')})';
    if (rows.isEmpty) {
      if (_hasFilter) return 'Bu süzgece uyan kalan $what yok$fl.';
      return types.isEmpty && who == null
          ? 'İpte kalan iş yok, her şey tamam! 🎉'
          : _cap('$whose$what kalmadı 🎉');
    }
    final head = types.isEmpty && who == null && !_hasFilter
        ? 'Öncelik sırana göre kalanlar:'
        : _cap('$whose$what kalan firmalar$fl (öncelik sırasıyla):');
    final filters = [
      if (types.isNotEmpty) _typesLabel(types),
      if (who != null) who.name,
      ..._filterLabels,
    ];
    _report = Report(
      title: types.isEmpty ? 'Kalan Projeler' : 'Kalan ${_typesLabel(types)} Projeleri',
      subtitle: filters.isEmpty
          ? 'Tüm firmalar · öncelik sırasıyla'
          : '${filters.join(' · ')} · öncelik sırasıyla',
      summary: '${rows.length} firma · $total proje kaldı',
      rows: reportRows,
    );
    return '$head\n${rows.join('\n')}\n\nToplam ${rows.length} firma, $total $what.';
  }

  /// Belirli tür/kişi için çizilmiş projeler (aktif ve tamamlanan kartlarda).
  String _doneItems({Set<String> types = const {}, String? member}) {
    final who = store.memberById(member);
    final rows = <String>[];
    final reportRows = <ReportRow>[];
    var count = 0;
    for (final c in store.cards) {
      if (!_cardOk(c)) continue;
      final done = c.items
          .where((e) =>
              e.done &&
              _typeOk(e.type, types) &&
              (member == null || e.doneBy == member))
          .toList();
      if (done.isEmpty) continue;
      final detail = done.map((e) {
        final by = member == null ? store.memberById(e.doneBy) : null;
        return '${kShortNames[e.type] ?? e.type}${by != null ? ' — ${by.name}' : ''}';
      }).join(', ');
      rows.add('• ${c.name}: $detail');
      count += done.length;
      final owner = store.memberById(c.assignedTo);
      reportRows.add(ReportRow(
        title: c.name,
        owner: owner?.name,
        ownerColor: owner?.color,
        items: done.map((e) => kShortNames[e.type] ?? e.type).toList(),
        done: c.items.where((e) => e.done).length,
        total: c.items.length,
      ));
    }
    final what = types.isEmpty ? 'proje' : '${_typesLabel(types)} projesi';
    final whose = who != null ? '${who.name} tarafından ' : '';
    if (rows.isEmpty) return 'Henüz ${whose}çizilmiş $what yok.';
    _report = Report(
      title: types.isEmpty ? 'Çizilen Projeler' : 'Çizilen ${_typesLabel(types)} Projeleri',
      subtitle: [
        who != null ? '${who.name} tarafından' : 'Tüm firmalar',
        ..._filterLabels,
      ].join(' · '),
      summary: '${rows.length} firma · $count proje çizildi',
      rows: reportRows,
      style: ReportStyle.done,
    );
    return _cap('${whose}çizilen $what (${rows.length} firma):\n${rows.join('\n')}');
  }

  String _completed() {
    final done = store.completed.where(_cardOk).toList();
    if (done.isEmpty) {
      return _hasFilter
          ? 'Bu süzgece uyan tamamlanan firma yok.'
          : 'Henüz tamamlanan firma yok.';
    }
    _report = Report(
      title: 'Tamamlanan Firmalar',
      subtitle: ['Tüm projeleri bitenler', ..._filterLabels].join(' · '),
      summary: '${done.length} firma tamamlandı',
      style: ReportStyle.done,
      rows: [
        for (final c in done)
          ReportRow(
            title: c.name,
            owner: store.memberById(c.assignedTo)?.name,
            ownerColor: store.memberById(c.assignedTo)?.color,
            items: c.items.map((e) => kShortNames[e.type] ?? e.type).toList(),
            done: c.items.length,
            total: c.items.length,
          ),
      ],
    );
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
      '• Adında "tekstil" geçenleri listele\n'
      '• "Mavi" hariç kalanlar · Elektrik hariç kalanlar\n'
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
