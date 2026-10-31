import 'package:flutter/material.dart';

/// Çizilebilecek proje türleri (sabit liste).
const List<String> kProjectTypes = [
  'Mimari Proje',
  'Elektrik Projesi',
  'Yangın Algılama Projesi',
  'Yangın Söndürme Tesisatı Projesi',
  'Havalandırma Projesi',
  'Yangın Kaçış Projesi',
  'Raf Yerleşim Projesi',
  'Paratoner Projesi',
];

/// Kısa adlar — kart üzerinde yer kazanmak için.
const Map<String, String> kShortNames = {
  'Mimari Proje': 'Mimari',
  'Elektrik Projesi': 'Elektrik',
  'Yangın Algılama Projesi': 'Yangın Algılama',
  'Yangın Söndürme Tesisatı Projesi': 'Yangın Söndürme',
  'Havalandırma Projesi': 'Havalandırma',
  'Yangın Kaçış Projesi': 'Yangın Kaçış',
  'Raf Yerleşim Projesi': 'Raf Yerleşim',
  'Paratoner Projesi': 'Paratoner',
};

/// Ekipteki kişi. Her kişinin kendi rengi var; tik ve kart rengi buradan gelir.
class Member {
  final String id;
  final String name;
  final Color color;
  final String emoji; // profil simgesi (arkadaşlar için), boş olabilir
  const Member(
      {required this.id, required this.name, required this.color, this.emoji = ''});

  /// Daire içinde gösterilecek: emoji ya da ismin baş harfi.
  String get badge => emoji.isNotEmpty
      ? emoji
      : (name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase());

  Member copyWith({String? name, Color? color, String? emoji}) => Member(
      id: id, name: name ?? this.name, color: color ?? this.color, emoji: emoji ?? this.emoji);

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'color': color.value, 'emoji': emoji};
  factory Member.fromJson(Map<String, dynamic> j) => Member(
      id: j['id'],
      name: j['name'] ?? '',
      color: Color(j['color'] ?? 0xFF8B6A3E),
      emoji: j['emoji'] ?? '');
}

/// Kullanıcı renkleri; yeni eklenen kullanıcı sıradakini alır.
const List<Color> kMemberPalette = [
  Color(0xFF2E7DE0), Color(0xFF2EA35A), Color(0xFFE0652E), Color(0xFF9B4DE0),
  Color(0xFFE02E7D), Color(0xFF14A3A3), Color(0xFFC9A200), Color(0xFF555555),
];

/// Varsayılan ekip: Kullanıcı 1 ve 2. Ekip sekmesinden eklenir / düzenlenir.
const List<Member> kDefaultMembers = [
  Member(id: 'me', name: 'Kullanıcı 1', color: Color(0xFF2E7DE0)),
  Member(id: 'friend', name: 'Kullanıcı 2', color: Color(0xFF2EA35A)),
];

/// Eski sürümlerdeki varsayılan adlar → yeni adlar.
const Map<String, String> kLegacyMemberNames = {
  'Ben': 'Kullanıcı 1',
  'Arkadaşım': 'Kullanıcı 2',
};

/// Bir firmanın altındaki tek bir proje kalemi.
class ProjectItem {
  String type; // yeniden adlandırılabilir
  bool done;
  String? doneBy; // tik atan kişinin id'si
  DateTime? doneAt;

  ProjectItem({required this.type, this.done = false, this.doneBy, this.doneAt});

  Map<String, dynamic> toJson() => {
        'type': type,
        'done': done,
        'doneBy': doneBy,
        'doneAt': doneAt?.toIso8601String(),
      };
  factory ProjectItem.fromJson(Map<String, dynamic> j) => ProjectItem(
        type: j['type'],
        done: j['done'] ?? false,
        doneBy: j['doneBy'],
        doneAt: j['doneAt'] != null ? DateTime.parse(j['doneAt']) : null,
      );
}

/// İpe asılı bir kart = bir firma.
class CompanyCard {
  final String id;
  String name;
  List<ProjectItem> items;
  String notes;
  String? assignedTo; // kartın tamamını kime verdiğin (kart rengi)
  bool completed;
  DateTime createdAt;
  DateTime? completedAt;

  /// Geri alınabilir silme: silinen kart gizlenir, Geçmiş'ten geri yüklenir.
  bool deleted;
  DateTime? deletedAt;

  CompanyCard({
    required this.id,
    required this.name,
    required this.items,
    this.notes = '',
    this.assignedTo,
    this.completed = false,
    DateTime? createdAt,
    this.completedAt,
    this.deleted = false,
    this.deletedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  List<ProjectItem> get remaining => items.where((i) => !i.done).toList();
  bool get allDone => items.isNotEmpty && items.every((i) => i.done);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'items': items.map((e) => e.toJson()).toList(),
        'notes': notes,
        'assignedTo': assignedTo,
        'completed': completed,
        'createdAt': createdAt.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        if (deleted) 'deleted': true,
        if (deletedAt != null) 'deletedAt': deletedAt!.toIso8601String(),
      };
  factory CompanyCard.fromJson(Map<String, dynamic> j) => CompanyCard(
        id: j['id'],
        name: j['name'],
        items: (j['items'] as List).map((e) => ProjectItem.fromJson(e)).toList(),
        notes: j['notes'] ?? '',
        assignedTo: j['assignedTo'],
        completed: j['completed'] ?? false,
        createdAt: DateTime.parse(j['createdAt']),
        completedAt:
            j['completedAt'] != null ? DateTime.parse(j['completedAt']) : null,
        deleted: j['deleted'] ?? false,
        deletedAt: j['deletedAt'] != null ? DateTime.parse(j['deletedAt']) : null,
      );
}

/// Ortak askılıklarda yapılan bir işlem (Geçmiş sekmesi için).
class Activity {
  final String id;
  final DateTime at;
  final String by; // profil kimliği
  final String byName;
  final int byColor;
  final String byEmoji;
  final String boardId;
  final String boardName;
  final String action; // tick, untick, complete, reopen, add, edit, delete, restore
  final String cardId;
  final String card;
  final String item;

  const Activity({
    required this.id,
    required this.at,
    required this.by,
    required this.byName,
    required this.byColor,
    this.byEmoji = '',
    required this.boardId,
    required this.boardName,
    required this.action,
    required this.cardId,
    required this.card,
    this.item = '',
  });

  /// "Atilla Tekstil · Elektrik tiklendi"
  String get text {
    final c = card.length > 60 ? '${card.substring(0, 60)}…' : card;
    switch (action) {
      case 'tick':
        return '$c · $item tiklendi';
      case 'untick':
        return '$c · $item tiki kaldırıldı';
      case 'complete':
        return '$c tamamlandı 🎉';
      case 'reopen':
        return '$c ipe geri asıldı';
      case 'add':
        return '$c eklendi';
      case 'edit':
        return '$c düzenlendi';
      case 'delete':
        return '$c silindi';
      case 'restore':
        return '$c geri yüklendi';
      default:
        return '$c · $action';
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'at': at.toIso8601String(),
        'by': by,
        'byName': byName,
        'byColor': byColor,
        'byEmoji': byEmoji,
        'boardId': boardId,
        'boardName': boardName,
        'action': action,
        'cardId': cardId,
        'card': card,
        'item': item,
      };

  factory Activity.fromJson(Map<String, dynamic> j) => Activity(
        id: '${j['id'] ?? ''}',
        at: DateTime.tryParse('${j['at']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
        by: '${j['by'] ?? ''}',
        byName: '${j['byName'] ?? ''}',
        byColor: (j['byColor'] as num?)?.toInt() ?? 0xFF8B6A3E,
        byEmoji: '${j['byEmoji'] ?? ''}',
        boardId: '${j['boardId'] ?? ''}',
        boardName: '${j['boardName'] ?? ''}',
        action: '${j['action'] ?? ''}',
        cardId: '${j['cardId'] ?? ''}',
        card: '${j['card'] ?? ''}',
        item: '${j['item'] ?? ''}',
      );
}
