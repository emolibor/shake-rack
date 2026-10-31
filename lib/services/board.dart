import 'package:uuid/uuid.dart';
import '../models/models.dart';
import 'store.dart';

/// Bir askılık: kartlar + kartlara gelecek madde şablonu.
///
/// - "Projeler" askılığı (isProjects): şablon sabit proje türleri, grupla
///   paylaşılır (Firebase).
/// - Özel askılıklar: adı ve şablonu kullanıcı belirler (ör. Reels →
///   Instagram, YouTube). SADECE bu telefonda saklanır, buluta gitmez.
class Board {
  static const projectsId = 'projects';
  static const _uuid = Uuid();

  final String id;
  String name;
  final bool isProjects;
  List<String> template;
  List<CompanyCard> cards;

  /// Sahibi olan store; değişiklikler onun üzerinden kaydedilir.
  late RackStore store;

  Board({
    required this.id,
    required this.name,
    required this.isProjects,
    required this.template,
    List<CompanyCard>? cards,
  }) : cards = cards ?? [];

  factory Board.projects() => Board(
        id: projectsId,
        name: 'Projeler',
        isProjects: true,
        template: List.of(kProjectTypes),
      );

  factory Board.custom(String name, List<String> template) => Board(
        id: _uuid.v4(),
        name: name.trim(),
        isProjects: false,
        template: template,
      );

  bool get isPrivate => !isProjects;

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
        'cards': cards.map((e) => e.toJson()).toList(),
      };

  factory Board.fromJson(Map<String, dynamic> j) => Board(
        id: j['id'],
        name: j['name'],
        isProjects: false,
        template: List<String>.from(j['template'] ?? const []),
        cards: (j['cards'] as List? ?? [])
            .map((e) => CompanyCard.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}
