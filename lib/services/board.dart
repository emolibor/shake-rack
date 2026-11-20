import 'package:uuid/uuid.dart';
import '../models/models.dart';
import 'store.dart';

/// Bir askılık: kartlar + kartlara gelecek madde şablonu.
///
/// - "Projeler" askılığı (isProjects): şablon sabit proje türleri, grupla
///   paylaşılır (Firebase).
/// - Özel askılıklar: adı ve şablonu kullanıcı belirler (ör. Reels →
///   Instagram, YouTube). SADECE bu telefonda saklanır, buluta gitmez.
/// Askılık türü: maddeli kartlar ya da sadece yazıdan ibaret notlar.
/// routines: not gibi serbest yazı, tikler her gece 02:00'de sıfırlanır.
enum BoardKind { items, notes, routines }

BoardKind _kindOf(Object? s) => BoardKind.values
    .firstWhere((k) => k.name == s, orElse: () => BoardKind.items);

/// Paylaşılan askılıkta bu telefonun rolü.
/// owner: paylaşan · editor: düzenleyebilir · viewer: sadece inceler
enum ShareRole { owner, editor, viewer }

class Board {
  static const projectsId = 'projects';
  static const _uuid = Uuid();

  final String id;
  String name;
  final bool isProjects;
  final BoardKind kind;
  List<String> template;
  List<CompanyCard> cards;

  /// Sahibi olan store; değişiklikler onun üzerinden kaydedilir.
  late RackStore store;

  // ---------- paylaşım ----------
  /// Paylaşım kodu (ör. "K7P2QX9M"); null = paylaşılmıyor.
  String? shareCode;
  ShareRole? role;

  /// Sahibin seçtiği izinler (paylaşılan herkes için).
  bool shareCanEdit = true;
  bool allowCopy = true;

  /// Paylaşan kişi paylaşımı kapattı → bu artık yerel kopya (bilgi bandı için).
  bool shareEnded = false;

  /// Yeni (onaylı) paylaşım sistemi mi; eski sürüm paylaşımları taşınır.
  bool shareV2 = false;

  /// Paylaşılan askılıktaki kişiler: profil kimliği → rol (owner/editor/viewer).
  Map<String, String> people = {};

  /// Paylaşılan özel askılığın işlem geçmişi (Projeler'inki store'da).
  List<Activity> log = [];

  /// Askılığı yönetebilir mi: silmek, adını / maddelerini değiştirmek,
  /// silinen kartı geri yüklemek. Ortak askılıkta sadece sahip.
  bool get canManage =>
      isProjects ? store.canManageProjects : (role == null || role == ShareRole.owner);

  bool get isShared => shareCode != null;
  bool get canEdit => role != ShareRole.viewer;
  bool get isOwnerOrLocal => role == null || role == ShareRole.owner;

  /// "K7P2-QX9M" gibi okunur kod.
  String get shareCodePretty {
    final c = shareCode;
    if (c == null) return '';
    if (c.length != 8) return c; // eski tip ekip kodu (ör. eski-ekip-kodu)
    return '${c.substring(0, 4)}-${c.substring(4)}';
  }

  Board({
    required this.id,
    required this.name,
    required this.isProjects,
    required this.template,
    this.kind = BoardKind.items,
    List<CompanyCard>? cards,
  }) : cards = cards ?? [];

  factory Board.projects() => Board(
        id: projectsId,
        name: 'Projeler',
        isProjects: true,
        template: List.of(kProjectTypes),
      );

  factory Board.custom(String name, List<String> template,
          {BoardKind kind = BoardKind.items}) =>
      Board(
        id: _uuid.v4(),
        name: name.trim(),
        isProjects: false,
        kind: kind,
        template: kind == BoardKind.items ? template : [],
      );

  /// Grupla paylaşılmayan, kimseyle paylaşılmamış askılık.
  bool get isPrivate => !isProjects && !isShared;
  /// Yazı kartları (not ve rutin): başlık/madde yok, sadece yazı + tik.
  bool get isNotes => kind == BoardKind.notes || kind == BoardKind.routines;
  bool get isRoutine => kind == BoardKind.routines;

  // ---------- rutinler ----------
  /// Rutin gününün sıfırlandığı saat.
  static const resetHour = 2;

  /// Şu anki rutin gününün başlangıcı: bugün 02:00, saat 02:00'den önceyse dün 02:00.
  static DateTime routineDayStart([DateTime? now]) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day, resetHour);
    return n.isBefore(today)
        ? DateTime(n.year, n.month, n.day - 1, resetHour)
        : today;
  }

  /// Bir sonraki sıfırlama anı.
  static DateTime nextRoutineReset([DateTime? now]) {
    final s = routineDayStart(now);
    return DateTime(s.year, s.month, s.day + 1, resetHour);
  }

  /// Rutin bugün yapıldı mı?
  bool checkedToday(CompanyCard c, [DateTime? now]) {
    final at = c.checkedAt;
    if (at == null) return false;
    final start = routineDayStart(now);
    return !at.isBefore(start) && at.isBefore(nextRoutineReset(now));
  }

  /// Bugün yapılan / toplam rutin.
  (int, int) routineProgress([DateTime? now]) {
    final l = live;
    return (l.where((c) => checkedToday(c, now)).length, l.length);
  }

  /// Sekmedeki sayı: rutinde bugün kalanlar, diğerlerinde ipteki kartlar.
  int get badgeCount {
    if (!isRoutine) return active.length;
    final (d, t) = routineProgress();
    return t - d;
  }

  /// Rutine tik at / kaldır. Bugünün hepsi bittiyse true (konfeti için).
  bool toggleRoutine(CompanyCard card, [DateTime? now]) {
    final on = !checkedToday(card, now);
    card.checkedAt = on ? (now ?? DateTime.now()) : null;
    _log(on ? 'tick' : 'untick', card, 'bugün');
    _commit();
    final (d, t) = routineProgress(now);
    return on && t > 0 && d == t;
  }

  /// Kart başlığı etiketi: projelerde firma, özelde serbest başlık.
  String get cardTitleLabel => isProjects ? 'Firma adı' : 'Başlık';
  String get itemsLabel => isProjects ? 'Çizilecek projeler' : 'Maddeler';

  /// Silinmemiş kartlar.
  List<CompanyCard> get live => cards.where((c) => !c.deleted).toList();
  List<CompanyCard> get active =>
      cards.where((c) => !c.completed && !c.deleted).toList();
  List<CompanyCard> get completed =>
      cards.where((c) => c.completed && !c.deleted).toList()
    ..sort((a, b) =>
        (b.completedAt ?? b.createdAt).compareTo(a.completedAt ?? a.createdAt));

  void _commit() {
    if (!canEdit) return; // sadece inceleme: hiçbir değişiklik kaydedilmez
    store.boardChanged(this);
  }

  void _log(String action, CompanyCard card, [String item = '']) {
    if (!canEdit) return;
    store.logActivity(this, action, card, item);
  }

  static String _short(String t) => kShortNames[t] ?? t;

  // ---------- kartlar ----------
  CompanyCard addCard(String name, List<String> types,
      {String? assignedTo, String notes = ''}) {
    final card = CompanyCard(
      id: _uuid.v4(),
      name: name.trim(),
      items: types.map((t) => ProjectItem(type: t)).toList(),
      assignedTo: assignedTo,
      notes: notes,
    );
    cards.add(card);
    _log('add', card);
    _commit();
    return card;
  }

  void updateCard(CompanyCard card,
      {String? name,
      List<String>? types,
      String? notes,
      String? assignedTo,
      bool clearAssignee = false}) {
    if (name != null) card.name = name.trim();
    if (notes != null) card.notes = notes;
    if (clearAssignee) {
      card.assignedTo = null;
    } else if (assignedTo != null) {
      card.assignedTo = assignedTo;
    }
    if (types != null) {
      // mevcut tikleri koru, yeni maddeleri ekle, kaldırılanları sil
      final old = {for (final i in card.items) i.type: i};
      card.items = types.map((t) => old[t] ?? ProjectItem(type: t)).toList();
    }
    _log('edit', card);
    _commit();
  }

  /// Geri alınabilir silme: kart gizlenir, Geçmiş'ten geri yüklenebilir.
  void deleteCard(CompanyCard card) {
    // kimseyle paylaşılmayan askılıkta kalıcı sil (geri yükleyecek geçmiş yok)
    final sharedBoard = isProjects ? store.projectsLinked : isShared;
    if (!sharedBoard) {
      cards.remove(card);
      _commit();
      return;
    }
    card.deleted = true;
    card.deletedAt = DateTime.now();
    _log('delete', card);
    _commit();
  }

  /// Silinen kartı geri getir (askılığı yöneten kişi).
  bool restoreCard(CompanyCard card) {
    if (!canManage || !card.deleted) return false;
    card.deleted = false;
    card.deletedAt = null;
    _log('restore', card);
    _commit();
    return true;
  }

  /// Silinen kartı kalıcı olarak kaldır (askılığı yöneten kişi).
  bool purgeCard(CompanyCard card) {
    if (!canManage || !card.deleted) return false;
    cards.remove(card);
    _commit();
    return true;
  }

  CompanyCard? cardById(String id) =>
      cards.cast<CompanyCard?>().firstWhere((c) => c!.id == id, orElse: () => null);

  /// Aktif kartlar arasında sırayı değiştir (öncelik).
  void reorderActive(int oldIndex, int newIndex) {
    final act = active;
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = act.removeAt(oldIndex);
    act.insert(newIndex, moved);
    final rest = cards.where((c) => c.completed || c.deleted).toList();
    cards = [...act, ...rest];
    _commit();
  }

  /// Tik at / kaldır. Hepsi bittiyse true döner (konfeti için).
  bool toggleItem(CompanyCard card, ProjectItem item) {
    item.done = !item.done;
    if (item.done) {
      // paylaşılan askılıkta tiki profil kimliğiyle işaretle (rengi herkeste doğru çıksın)
      item.doneBy = isShared && !isProjects && store.profile.id.isNotEmpty
          ? store.profile.id
          : store.currentMemberId;
      item.doneAt = DateTime.now();
    } else {
      item.doneBy = null;
      item.doneAt = null;
    }
    _log(item.done ? 'tick' : 'untick', card, _short(item.type));
    final finished = card.allDone;
    _commit();
    return finished;
  }

  /// Not askılığında: notun üzerine tik. Tiklenince Tamamlananlar'a geçer.
  /// Tamamlandıysa true döner.
  bool toggleNote(CompanyCard card) {
    card.completed = !card.completed;
    card.completedAt = card.completed ? DateTime.now() : null;
    _log(card.completed ? 'complete' : 'reopen', card);
    _commit();
    return card.completed;
  }

  /// Şablondaki maddelerin adı değişince kartlardaki aynı maddeleri de
  /// yeniden adlandırır (tikler korunur). renames: eskiAd → yeniAd
  void applyRenames(Map<String, String> renames) {
    if (renames.isEmpty) return;
    for (final c in cards) {
      for (final it in c.items) {
        final n = renames[it.type];
        if (n != null) it.type = n;
      }
    }
  }

  void markCompleted(CompanyCard card) {
    card.completed = true;
    card.completedAt = DateTime.now();
    _log('complete', card);
    _commit();
  }

  void reopen(CompanyCard card) {
    card.completed = false;
    card.completedAt = null;
    _log('reopen', card);
    _commit();
  }

  // ---------- kayıt (yalnızca özel askılıklar için yerel JSON) ----------
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'template': template,
        'kind': kind.name,
        'cards': cards.map((e) => e.toJson()).toList(),
        'shareCode': shareCode,
        'role': role?.name,
        'shareCanEdit': shareCanEdit,
        'allowCopy': allowCopy,
        'shareEnded': shareEnded,
        'shareV2': shareV2,
        'people': people,
        'log': log.map((e) => e.toJson()).toList(),
      };

  /// Buluttaki paylaşım belgesine giden içerik.
  Map<String, dynamic> sharePayload() => {
        'name': name,
        'kind': kind.name,
        'template': template,
        'cards': cards.map((e) => e.toJson()).toList(),
      };

  /// Diğer telefondan gelen içeriği uygula.
  void applyShared(Map<String, dynamic> d) {
    name = (d['name'] as String?) ?? name;
    template = List<String>.from(d['template'] ?? template);
    cards = (d['cards'] as List? ?? [])
        .map((e) => CompanyCard.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Paylaşım belgesinden yeni askılık (kopya ya da canlı bağlantı için).
  factory Board.fromShare(Map<String, dynamic> d) => Board(
        id: _uuid.v4(),
        name: (d['name'] as String?) ?? 'Paylaşılan askılık',
        isProjects: false,
        kind: _kindOf(d['kind']),
        template: List<String>.from(d['template'] ?? const []),
        cards: (d['cards'] as List? ?? [])
            .map((e) => CompanyCard.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );

  factory Board.fromJson(Map<String, dynamic> j) => Board(
        id: j['id'],
        name: j['name'],
        isProjects: false,
        template: List<String>.from(j['template'] ?? const []),
        kind: _kindOf(j['kind']),
        cards: (j['cards'] as List? ?? [])
            .map((e) => CompanyCard.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      )
        ..shareCode = j['shareCode']
        ..role = ShareRole.values
            .cast<ShareRole?>()
            .firstWhere((r) => r!.name == j['role'], orElse: () => null)
        ..shareCanEdit = j['shareCanEdit'] ?? true
        ..allowCopy = j['allowCopy'] ?? true
        ..shareEnded = j['shareEnded'] ?? false
        ..shareV2 = j['shareV2'] ?? false
        ..people = Map<String, String>.from(j['people'] ?? const {})
        ..log = (j['log'] as List? ?? [])
            .map((e) => Activity.fromJson(Map<String, dynamic>.from(e)))
            .toList();
}
