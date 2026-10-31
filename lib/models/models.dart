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
  const Member({required this.id, required this.name, required this.color});

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'color': color.value};
  factory Member.fromJson(Map<String, dynamic> j) =>
      Member(id: j['id'], name: j['name'], color: Color(j['color']));
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
  final String type;
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

  CompanyCard({
    required this.id,
    required this.name,
    required this.items,
    this.notes = '',
    this.assignedTo,
    this.completed = false,
    DateTime? createdAt,
    this.completedAt,
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
      );
}
