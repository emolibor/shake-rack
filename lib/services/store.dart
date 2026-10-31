import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import 'board.dart';

/// Tüm uygulama durumu.
///
/// - Her değişiklik önce yerelde (shared_preferences) saklanır → çevrimdışı çalışır.
/// - **Projeler** askılığı ve kullanıcı listesi, bir "askılık kodu" girildiyse
///   Firestore'da `racks/{kod}` belgesine yazılır → grup aynı ipi görür.
/// - **Özel askılıklar** yalnızca bu telefonda saklanır; buluta hiç gönderilmez.
class RackStore extends ChangeNotifier {
  static const _kCards = 'cards_v1'; // Projeler askılığının kartları
  static const _kCustom = 'custom_boards_v1'; // özel askılıklar (yerel)
  static const _kProjectTypes = 'project_types_v1'; // Projeler maddeleri
  static const _kMembers = 'members_v1';
  static const _kCurrent = 'current_member_v1';
  static const _kRackCode = 'rack_code_v1';
  static const _kDeviceId = 'device_id_v1';

  final _uuid = const Uuid();

  /// Bu cihaza özel kimlik — kendi yazdığımız güncellemeyi tanımak için.
  String deviceId = '';

  late final Board projects = Board.projects()..store = this;
  List<Board> custom = [];
  List<Member> members = List.of(kDefaultMembers);
  String currentMemberId = 'me';

  /// Sekme sırası: Projeler + özel askılıklar.
  List<Board> get boards => [projects, ...custom];
  Board? boardById(String id) =>
      boards.cast<Board?>().firstWhere((b) => b!.id == id, orElse: () => null);

  // Projeler askılığına kısayollar (asistan ve eski kod için)
  List<CompanyCard> get cards => projects.cards;
  List<CompanyCard> get active => projects.active;
  List<CompanyCard> get completed => projects.completed;
  CompanyCard addCard(String name, List<String> types, {String? assignedTo}) =>
      projects.addCard(name, types, assignedTo: assignedTo);
  bool toggleItem(CompanyCard card, ProjectItem item) =>
      projects.toggleItem(card, item);

  /// Paylaşılan askılık kodu (ör. "fourmis-2026"). Boşsa sadece yerel.
  String rackCode = '';
  bool firebaseReady = false; // Firebase.initializeApp başarılı mı
  bool get syncing => firebaseReady && rackCode.isNotEmpty;
  String syncStatus = 'Yerel';

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  int _revision = 0;
  Timer? _debounce;

  Member get me => members.firstWhere((m) => m.id == currentMemberId,
      orElse: () => members.first);
  Member? memberById(String? id) => id == null
      ? null
      : members.cast<Member?>().firstWhere((m) => m!.id == id, orElse: () => null);

  // ---------- yükleme / kayıt ----------

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final c = p.getString(_kCards);
    if (c != null) {
      projects.cards =
          (jsonDecode(c) as List).map((e) => CompanyCard.fromJson(e)).toList();
    }
    final pt = p.getStringList(_kProjectTypes);
    if (pt != null && pt.isNotEmpty) projects.template = pt;
    final cb = p.getString(_kCustom);
    if (cb != null) {
      custom = (jsonDecode(cb) as List)
          .map((e) => Board.fromJson(Map<String, dynamic>.from(e))..store = this)
          .toList();
    }
    final m = p.getString(_kMembers);
    if (m != null) {
      members = (jsonDecode(m) as List).map((e) => Member.fromJson(e)).toList();
    }
    final renamed = _migrateMemberNames();
    currentMemberId = p.getString(_kCurrent) ?? 'me';
    if (memberById(currentMemberId) == null) currentMemberId = members.first.id;
    rackCode = p.getString(_kRackCode) ?? '';
    deviceId = p.getString(_kDeviceId) ?? '';
    if (deviceId.isEmpty) {
      deviceId = _uuid.v4();
      await p.setString(_kDeviceId, deviceId);
    }
    if (renamed) await _saveLocal();
    notifyListeners();
    if (rackCode.isNotEmpty) _listen();
  }

  /// "Ben"/"Arkadaşım" gibi eski varsayılan adları "Kullanıcı 1/2" yap.
  bool _migrateMemberNames() {
    var changed = false;
    for (var i = 0; i < members.length; i++) {
      final n = kLegacyMemberNames[members[i].name];
      if (n != null) {
        members[i] = Member(id: members[i].id, name: n, color: members[i].color);
        changed = true;
      }
    }
    return changed;
  }

  Future<void> _saveLocal() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _kCards, jsonEncode(projects.cards.map((e) => e.toJson()).toList()));
    await p.setStringList(_kProjectTypes, projects.template);
    await p.setString(
        _kCustom, jsonEncode(custom.map((e) => e.toJson()).toList()));
    await p.setString(
        _kMembers, jsonEncode(members.map((e) => e.toJson()).toList()));
    await p.setString(_kCurrent, currentMemberId);
    await p.setString(_kRackCode, rackCode);
  }

  /// Grupla paylaşılan veri. Özel askılıklar burada YOK.
  Map<String, dynamic> sharedJson() => {
        'cards': projects.cards.map((e) => e.toJson()).toList(),
        'members': members.map((e) => e.toJson()).toList(),
        'projectTypes': projects.template,
      };

  Map<String, dynamic> _toCloud() => {
        ...sharedJson(),
        'revision': _revision,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': deviceId,
      };

  void _applyCloud(Map<String, dynamic> d) {
    projects.cards = (d['cards'] as List? ?? [])
        .map((e) => CompanyCard.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final pt = d['projectTypes'] as List?;
    if (pt != null && pt.isNotEmpty) {
      projects.template = pt.map((e) => e.toString()).toList();
    }
    final ms = d['members'] as List?;
    if (ms != null && ms.isNotEmpty) {
      members =
          ms.map((e) => Member.fromJson(Map<String, dynamic>.from(e))).toList();
    }
    _revision = (d['revision'] as int?) ?? _revision;
  }

  DocumentReference<Map<String, dynamic>> get _doc =>
      FirebaseFirestore.instance.collection('racks').doc(rackCode);

  /// Yazmaları 300 ms toplayıp tek seferde gönderir (hızlı tik atmalarda).
  void _pushCloud() {
    if (!syncing) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      _revision++;
      try {
        await _doc.set(_toCloud(), SetOptions(merge: true));
        syncStatus = 'Eşitlendi';
      } catch (e) {
        syncStatus = 'Bağlantı yok (yerelde saklandı)';
      }
      notifyListeners();
    });
  }

  void _listen() {
    _sub?.cancel();
    if (!syncing) return;
    syncStatus = 'Bağlanıyor…';
    notifyListeners();
    _sub = _doc.snapshots().listen((snap) async {
      if (!snap.exists) {
        // Kod ilk kez kullanılıyor → yereldeki veriyi buluta taşı.
        await _doc.set(_toCloud());
        syncStatus = 'Eşitlendi';
        notifyListeners();
        return;
      }
      final d = snap.data()!;
      // Kendi yazdığımız sürümü geri okuma; diğer telefonun yazdığını uygula.
      // Bizim gönderilmeyi bekleyen değişikliğimiz varsa onu ezme.
      final pending = _debounce?.isActive ?? false;
      if (d['updatedBy'] != deviceId && !pending) {
        _applyCloud(d);
        if (_migrateMemberNames()) _pushCloud();
        if (memberById(currentMemberId) == null) {
          currentMemberId = members.first.id;
        }
        await _saveLocal();
      }
      syncStatus = snap.metadata.isFromCache ? 'Çevrimdışı' : 'Eşitlendi';
      notifyListeners();
    }, onError: (_) {
      syncStatus = 'Hata: Firestore kuralları / internet';
      notifyListeners();
    });
  }

  /// Askılık koduna katıl veya ayrıl (boş kod = sadece yerel).
  Future<void> setRackCode(String code) async {
    rackCode =
        code.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9\-_]'), '-');
    await _saveLocal();
    _sub?.cancel();
    _sub = null;
    if (rackCode.isEmpty) {
      syncStatus = 'Yerel';
      notifyListeners();
      return;
    }
    _listen();
  }

  /// Board değişince çağrılır. Sadece Projeler buluta gider.
  void boardChanged(Board b) {
    notifyListeners();
    _saveLocal();
    if (b.isProjects) _pushCloud();
  }

  // ---------- özel askılıklar ----------
  Board addBoard(String name, List<String> template,
      {BoardKind kind = BoardKind.items}) {
    final b = Board.custom(name, template, kind: kind)..store = this;
    custom.add(b);
    boardChanged(b);
    return b;
  }

  /// Askılığı güncelle. Projeler'in adı sabit, maddeleri düzenlenebilir
  /// (grupla eşitlenir). renames: şablonda adı değişen maddeler (eski → yeni),
  /// kartlardaki aynı maddeler de yeniden adlandırılır.
  void updateBoard(Board b,
      {String? name, List<String>? template, Map<String, String> renames = const {}}) {
    if (!b.isProjects && name != null && name.trim().isNotEmpty) {
      b.name = name.trim();
    }
    if (template != null && template.isNotEmpty) b.template = template;
    b.applyRenames(renames);
    boardChanged(b);
  }

  void deleteBoard(Board b) {
    if (b.isProjects) return;
    custom.remove(b);
    boardChanged(b);
  }

  // ---------- ekip ----------
  void setCurrentMember(String id) {
    currentMemberId = id;
    notifyListeners();
    _saveLocal(); // kişi seçimi cihaza özel, buluta gitmez
  }

  void _membersChanged() {
    notifyListeners();
    _saveLocal();
    _pushCloud();
  }

  /// Sıradaki numarayla "Kullanıcı N" ekler.
  Member addMember() {
    var n = members.length + 1;
    final names = members.map((m) => m.name).toSet();
    while (names.contains('Kullanıcı $n')) {
      n++;
    }
    final used = members.map((m) => m.color.value).toSet();
    final color = kMemberPalette.firstWhere((c) => !used.contains(c.value),
        orElse: () => kMemberPalette[members.length % kMemberPalette.length]);
    final m = Member(id: _uuid.v4(), name: 'Kullanıcı $n', color: color);
    members.add(m);
    _membersChanged();
    return m;
  }

  /// Kullanıcıyı sil. Son kullanıcı silinemez. Atandığı kartlar boşa düşer.
  bool removeMember(String id) {
    if (members.length <= 1) return false;
    members.removeWhere((m) => m.id == id);
    for (final c in projects.cards) {
      if (c.assignedTo == id) c.assignedTo = null;
    }
    if (currentMemberId == id) currentMemberId = members.first.id;
    _membersChanged();
    return true;
  }

  void updateMember(String id, {String? name, Color? color}) {
    final i = members.indexWhere((m) => m.id == id);
    if (i < 0) return;
    members[i] = Member(
      id: id,
      name: (name == null || name.trim().isEmpty) ? members[i].name : name.trim(),
      color: color ?? members[i].color,
    );
    _membersChanged();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _debounce?.cancel();
    super.dispose();
  }
}
