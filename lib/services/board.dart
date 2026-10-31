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
enum BoardKind { items, notes }

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
        template: kind == BoardKind.notes ? [] : template,
      );

  bool get isPrivate => !isProjects;
  bool get isNotes => kind == BoardKind.notes;

  /// Kart başlığı etiketi: projelerde firma, özelde serbest başlık.
  String get cardTitleLabel => isProjects ? 'Firma adı' : 'Başlık';
  String get itemsLabel => isProjects ? 'Çizilecek projeler' : 'Maddeler';

  List<CompanyCard> get active => cards.where((c) => !c.completed).toList();
  List<CompanyCard> get completed => cards.where((c) => c.completed).toList()
    ..sort((a, b) =>
        (b.completedAt ?? b.createdAt).compareTo(a.completedAt ?? a.createdAt));

  void _commit() => store.boardChanged(this);

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
    _commit();
  }

  void deleteCard(CompanyCard card) {
    cards.remove(card);
    _commit();
  }

  /// Aktif kartlar arasında sırayı değiştir (öncelik).
  void reorderActive(int oldIndex, int newIndex) {
    final act = active;
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = act.removeAt(oldIndex);
    act.insert(newIndex, moved);
    final done = cards.where((c) => c.completed).toList();
    cards = [...act, ...done];
    _commit();
  }

  /// Tik at / kaldır. Hepsi bittiyse true döner (konfeti için).
  bool toggleItem(CompanyCard card, ProjectItem item) {
    item.done = !item.done;
    if (item.done) {
      item.doneBy = store.currentMemberId;
      item.doneAt = DateTime.now();
    } else {
      item.doneBy = null;
      item.doneAt = null;
    }
    final finished = card.allDone;
    _commit();
    return finished;
  }

  /// Not askılığında: notun üzerine tik. Tiklenince Tamamlananlar'a geçer.
  /// Tamamlandıysa true döner.
  bool toggleNote(CompanyCard card) {
    card.completed = !card.completed;
    card.completedAt = card.completed ? DateTime.now() : null;
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
    _commit();
  }

  void reopen(CompanyCard card) {
    card.completed = false;
    card.completedAt = null;
    _commit();
  }

  // ---------- kayıt (yalnızca özel askılıklar için yerel JSON) ----------
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'template': template,
        'kind': kind.name,
        'cards': cards.map((e) => e.toJson()).toList(),
      };

  factory Board.fromJson(Map<String, dynamic> j) => Board(
        id: j['id'],
        name: j['name'],
        isProjects: false,
        template: List<String>.from(j['template'] ?? const []),
        kind: j['kind'] == 'notes' ? BoardKind.notes : BoardKind.items,
        cards: (j['cards'] as List? ?? [])
            .map((e) => CompanyCard.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}
