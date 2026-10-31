import 'dart:async';
import 'dart:convert';
import 'dart:math';
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
  static const _kBoardOrder = 'board_order_v1'; // sekme sırası (bu telefona özel)
  static const _kMembers = 'members_v1';
  static const _kCurrent = 'current_member_v1';
  static const _kRackCode = 'rack_code_v1';
  static const _kDeviceId = 'device_id_v1';
  static const _kProjectsHidden = 'projects_hidden_v1';
  static const _kProjectsName = 'projects_name_v1';
  static const _kProfile = 'profile_v1';
  static const _kFriends = 'friends_v1';

  final _uuid = const Uuid();

  /// Bu cihaza özel kimlik — kendi yazdığımız güncellemeyi tanımak için.
  String deviceId = '';

  late final Board projects = Board.projects()..store = this;
  List<Board> custom = [];
  List<Member> members = List.of(kDefaultMembers);
  String currentMemberId = 'me';

  /// Sekme sırası (id listesi). Listede olmayanlar sona eklenir.
  List<String> boardOrder = [];

  /// Projeler askılığı bu telefonda kaldırıldı mı (proje işi olmayanlar için).
  bool projectsHidden = false;

  /// Bu telefonun sahibinin profili (arkadaşlar bunu görür).
  Member profile = Member(id: '', name: '', color: kMemberPalette[0], emoji: '🙂');
  bool get hasProfile => profile.name.trim().isNotEmpty;

  /// Askılık paylaştığın / askılığına katıldığın kişiler.
  Map<String, Member> friends = {};

  /// Sekmeler, kullanıcının sürükleyerek verdiği sırayla.
  List<Board> get boards {
    final all = [if (!projectsHidden) projects, ...custom];
    final rank = <String, int>{
      for (var k = 0; k < all.length; k++)
        all[k].id: boardOrder.contains(all[k].id)
            ? boardOrder.indexOf(all[k].id)
            : boardOrder.length + k,
    };
    return all..sort((a, b) => rank[a.id]!.compareTo(rank[b.id]!));
  }

  /// Sekmeyi sürükleyip bıraktı: yeni sırayı kaydet.
  void reorderBoards(int oldIndex, int newIndex) {
    final list = boards;
    if (newIndex > oldIndex) newIndex -= 1;
    list.insert(newIndex, list.removeAt(oldIndex));
    boardOrder = list.map((b) => b.id).toList();
    notifyListeners();
    _saveLocal();
  }
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
  /// Proje ekibi üyesi, kendi profilin ya da bir arkadaş.
  Member? memberById(String? id) {
    if (id == null) return null;
    for (final m in members) {
      if (m.id == id) return m;
    }
    if (id == profile.id) return profile;
    return friends[id];
  }

  // ---------- yükleme / kayıt ----------

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final c = p.getString(_kCards);
    if (c != null) {
      projects.cards =
          (jsonDecode(c) as List).map((e) => CompanyCard.fromJson(e)).toList();
    }
    boardOrder = p.getStringList(_kBoardOrder) ?? [];
    projectsHidden = p.getBool(_kProjectsHidden) ?? false;
    projects.name = p.getString(_kProjectsName) ?? projects.name;
    final pr = p.getString(_kProfile);
    if (pr != null) profile = Member.fromJson(jsonDecode(pr));
    if (profile.id.isEmpty) {
      profile = Member(id: _uuid.v4(), name: '', color: profile.color, emoji: profile.emoji);
      await p.setString(_kProfile, jsonEncode(profile.toJson()));
    }
    final fr = p.getString(_kFriends);
    if (fr != null) {
      friends = {
        for (final e in jsonDecode(fr) as List)
          (e['id'] as String): Member.fromJson(Map<String, dynamic>.from(e))
      };
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
    for (final b in custom) {
      if (b.isShared) _listenShared(b);
    }
    _listenProfile();
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
    await p.setStringList(_kBoardOrder, boardOrder);
    await p.setBool(_kProjectsHidden, projectsHidden);
    await p.setString(_kProjectsName, projects.name);
    await p.setString(_kProfile, jsonEncode(profile.toJson()));
    await p.setString(
        _kFriends, jsonEncode(friends.values.map((e) => e.toJson()).toList()));
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
        'projectsName': projects.name,
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
    final pn = d['projectsName'] as String?;
    if (pn != null && pn.trim().isNotEmpty) projects.name = pn;
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

  /// Board değişince çağrılır. Projeler grup belgesine, paylaşılan özel
  /// askılıklar kendi paylaşım belgesine gider; diğerleri sadece yerelde kalır.
  void boardChanged(Board b) {
    notifyListeners();
    _saveLocal();
    if (b.isProjects) _pushCloud();
    if (b.isShared && b.canEdit && custom.contains(b)) _pushShared(b);
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
    if (name != null && name.trim().isNotEmpty) b.name = name.trim();
    if (template != null && template.isNotEmpty) b.template = template;
    b.applyRenames(renames);
    boardChanged(b);
  }

  /// Askılığı sil. Paylaşan sahipse paylaşım da kapanır; alıcıysa sadece
  /// kendi telefonundan çıkar.
  Future<void> deleteBoard(Board b) async {
    if (b.isProjects) return hideProjects();
    if (b.isShared && b.role == ShareRole.owner) await stopSharing(b);
    if (b.isShared && b.role != ShareRole.owner) await _leaveMembers(b);
    _unlistenShared(b);
    custom.remove(b);
    boardOrder.remove(b.id);
    notifyListeners();
    await _saveLocal();
  }

  // ---------- askılık paylaşma ----------
  // Paylaşılan askılık, Firestore'da racks/share_<kod> belgesinde durur
  // (mevcut güvenlik kuralının içinde kalır). Kodu bilen katılabilir.

  static const _codeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final Map<String, StreamSubscription> _shareSubs = {};
  final Map<String, Timer> _shareTimers = {};

  static String newShareCode([Random? rnd]) {
    final r = rnd ?? Random.secure();
    return List.generate(8, (_) => _codeChars[r.nextInt(_codeChars.length)]).join();
  }

  /// Kullanıcının yazdığı kodu sadeleştir: "k7p2-qx9m " → "K7P2QX9M"
  static String normalizeCode(String s) =>
      s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  DocumentReference<Map<String, dynamic>> _shareDoc(String code) =>
      FirebaseFirestore.instance
          .collection('racks')
          .doc('share_${code.toLowerCase()}');

  /// Askılığı paylaş (ya da izinlerini güncelle). Kodu döner.
  Future<String> shareBoard(Board b,
      {required bool canEdit, required bool allowCopy}) async {
    if (!firebaseReady) {
      throw StateError('Paylaşım için internet / Firebase gerekli.');
    }
    b.shareCode ??= newShareCode();
    b.role = ShareRole.owner;
    b.shareCanEdit = canEdit;
    b.allowCopy = allowCopy;
    b.shareEnded = false;
    await _shareDoc(b.shareCode!).set({
      ...b.sharePayload(),
      'permission': canEdit ? 'edit' : 'view',
      'allowCopy': allowCopy,
      'owner': profile.id,
      'ownerName': hasProfile ? profile.name : me.name,
      'members': {profile.id: _meEntry(ShareRole.owner)},
      'updatedBy': deviceId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)); // merge: katılanların üye kaydı silinmesin
    b.people[profile.id] = ShareRole.owner.name;
    _listenShared(b);
    notifyListeners();
    await _saveLocal();
    return b.shareCode!;
  }

  /// Paylaşımı kapat (sahip). Alıcılarda askılık yerel kopyaya dönüşür.
  Future<void> stopSharing(Board b) async {
    final code = b.shareCode;
    if (code == null) return;
    _unlistenShared(b);
    if (b.role == ShareRole.owner && firebaseReady) {
      try {
        await _shareDoc(code).delete();
      } catch (_) {}
    }
    b.shareCode = null;
    b.role = null;
    notifyListeners();
    await _saveLocal();
  }

  /// Kodla paylaşılan askılığın içeriğini getir (önizleme). Yoksa null.
  Future<Map<String, dynamic>?> fetchShared(String rawCode) async {
    final code = normalizeCode(rawCode);
    if (code.length != 8) return null;
    final snap = await _shareDoc(code).get();
    if (!snap.exists) return null;
    return {...snap.data()!, 'code': code};
  }

  /// Paylaşılan askılığa canlı bağlan (izne göre düzenleyici / izleyici).
  Board joinShared(Map<String, dynamic> data) {
    final code = data['code'] as String;
    final existing = custom.cast<Board?>()
        .firstWhere((x) => x!.shareCode == code, orElse: () => null);
    if (existing != null) return existing;
    final b = Board.fromShare(data)..store = this;
    b.shareCode = code;
    b.shareCanEdit = data['permission'] != 'view';
    b.role = b.shareCanEdit ? ShareRole.editor : ShareRole.viewer;
    b.allowCopy = data['allowCopy'] ?? false;
    custom.add(b);
    _absorbMembers(b, data['members']);
    b.people[profile.id] = b.role!.name;
    if (firebaseReady) {
      _shareDoc(code)
          .set({'members': {profile.id: _meEntry(b.role!)}}, SetOptions(merge: true))
          .catchError((_) {});
    }
    _listenShared(b);
    notifyListeners();
    _saveLocal();
    return b;
  }

  /// Paylaşılan askılığın bağımsız kopyasını kendi askılıklarına ekle.
  Board copyShared(Map<String, dynamic> data, {String? name}) {
    final b = Board.fromShare(data)..store = this;
    if (name != null) b.name = name;
    custom.add(b);
    notifyListeners();
    _saveLocal();
    return b;
  }

  void _unlistenShared(Board b) {
    _shareSubs.remove(b.id)?.cancel();
    _shareTimers.remove(b.id)?.cancel();
  }

  void _pushShared(Board b) {
    if (!firebaseReady || b.shareCode == null) return;
    _shareTimers[b.id]?.cancel();
    _shareTimers[b.id] = Timer(const Duration(milliseconds: 400), () async {
      final code = b.shareCode;
      if (code == null) return;
      try {
        await _shareDoc(code).set({
          ...b.sharePayload(),
          if (b.role == ShareRole.owner) ...{
            'permission': b.shareCanEdit ? 'edit' : 'view',
            'allowCopy': b.allowCopy,
          },
          'updatedBy': deviceId,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {/* çevrimdışı: Firestore kuyruğa alır */}
    });
  }

  void _listenShared(Board b) {
    if (!firebaseReady || b.shareCode == null) return;
    _unlistenShared(b);
    _shareSubs[b.id] = _shareDoc(b.shareCode!).snapshots().listen((snap) async {
      if (!snap.exists) {
        if (b.role != ShareRole.owner) {
          // paylaşan kapattı → artık bu telefonda bağımsız kopya
          _unlistenShared(b);
          b.shareCode = null;
          b.role = null;
          b.shareEnded = true;
          notifyListeners();
          await _saveLocal();
        }
        return;
      }
      final pending = _shareTimers[b.id]?.isActive ?? false;
      applySharedSnapshot(b, snap.data()!, pending: pending);
      await _saveLocal();
    });
  }

  /// Paylaşım belgesindeki son durumu askılığa uygula: içerik, izinler, üyeler.
  void applySharedSnapshot(Board b, Map<String, dynamic> d, {bool pending = false}) {
    if (d['updatedBy'] != deviceId && !pending) b.applyShared(d);
    if (b.role != ShareRole.owner) {
      b.shareCanEdit = d['permission'] != 'view';
      b.role = b.shareCanEdit ? ShareRole.editor : ShareRole.viewer;
      b.allowCopy = d['allowCopy'] ?? false;
    }
    _absorbMembers(b, d['members']);
    notifyListeners();
  }

  /// Belgedeki üyeleri askılığa yaz; kendin dışındakileri arkadaş listesine ekle.
  void _absorbMembers(Board b, dynamic raw) {
    if (raw is! Map) return;
    final people = <String, String>{};
    raw.forEach((id, v) {
      if (v is! Map) return;
      people['$id'] = '${v['role'] ?? 'editor'}';
      if (id == profile.id) return;
      friends['$id'] = Member(
        id: '$id',
        name: '${v['name'] ?? ''}',
        color: Color((v['color'] as num?)?.toInt() ?? 0xFF8B6A3E),
        emoji: '${v['emoji'] ?? ''}',
      );
    });
    b.people = people;
  }

  Map<String, dynamic> _meEntry(ShareRole role) => {
        'name': profile.name,
        'color': profile.color.value,
        'emoji': profile.emoji,
        'role': role.name,
      };

  /// Alıcı askılıktan ayrılınca üye listesinden çıkar.
  Future<void> _leaveMembers(Board b) async {
    if (!firebaseReady || b.shareCode == null) return;
    try {
      await _shareDoc(b.shareCode!).update({'members.${profile.id}': FieldValue.delete()});
    } catch (_) {}
  }

  // ---------- Projeler askılığı (isteğe bağlı) ----------

  /// Projeler askılığını bu telefondan kaldır. Ekip koduna bağlı değilse
  /// içeriği de temizlenir; bağlıysa ekibin verisine dokunulmaz.
  Future<void> hideProjects() async {
    projectsHidden = true;
    if (!syncing) {
      projects.cards = [];
      projects.template = List.of(kProjectTypes);
      projects.name = 'Projeler';
    }
    boardOrder.remove(projects.id);
    notifyListeners();
    await _saveLocal();
  }

  /// Projeler askılığını geri ekle.
  Board showProjects() {
    projectsHidden = false;
    notifyListeners();
    _saveLocal();
    return projects;
  }

  // ---------- profil ve arkadaşlar ----------

  DocumentReference<Map<String, dynamic>> _profileDoc(String id) =>
      FirebaseFirestore.instance.collection('racks').doc('user_$id');
  StreamSubscription? _profileSub;
  final Set<String> _joiningInvites = {};

  Future<void> updateProfile({String? name, Color? color, String? emoji}) async {
    profile = profile.copyWith(name: name?.trim(), color: color, emoji: emoji);
    notifyListeners();
    await _saveLocal();
    if (!firebaseReady || !hasProfile) return;
    try {
      await _profileDoc(profile.id).set({
        'name': profile.name,
        'color': profile.color.value,
        'emoji': profile.emoji,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      // paylaşılan askılıklardaki kendi kaydını da güncelle
      for (final b in custom.where((b) => b.isShared)) {
        final role = b.role ?? ShareRole.editor;
        await _shareDoc(b.shareCode!)
            .set({'members': {profile.id: _meEntry(role)}}, SetOptions(merge: true));
      }
    } catch (_) {}
  }

  /// Kendi profil belgemi dinle: arkadaşların gönderdiği ortak askılık
  /// davetleri buraya düşer ve otomatik katılınır.
  void _listenProfile() {
    if (!firebaseReady || profile.id.isEmpty) return;
    _profileSub?.cancel();
    _profileSub = _profileDoc(profile.id).snapshots().listen((snap) async {
      final inbox = (snap.data()?['inbox'] as List?) ?? const [];
      for (final inv in inbox) {
        if (inv is! Map) continue;
        final code = '${inv['code'] ?? ''}';
        if (code.isEmpty || _joiningInvites.contains(code)) continue;
        _joiningInvites.add(code);
        try {
          final already = custom.any((b) => b.shareCode == code);
          if (!already) {
            final data = await fetchShared(code);
            if (data != null) joinShared(data);
          }
          await _profileDoc(profile.id)
              .update({'inbox': FieldValue.arrayRemove([inv])});
        } catch (_) {
        } finally {
          _joiningInvites.remove(code);
        }
      }
    }, onError: (_) {});
  }

  /// Arkadaşla ortak askılık: gerekirse paylaşır, arkadaşın gelen kutusuna
  /// davet bırakır. Arkadaşın uygulaması açıkken askılık onda kendiliğinden belirir.
  Future<void> inviteFriend(Board b, Member friend) async {
    if (!firebaseReady) throw StateError('İnternet / Firebase bağlantısı yok.');
    if (!b.isShared) await shareBoard(b, canEdit: true, allowCopy: true);
    await _profileDoc(friend.id).set({
      'inbox': FieldValue.arrayUnion([
        {
          'code': b.shareCode,
          'from': profile.id,
          'fromName': profile.name,
          'board': b.name,
        }
      ]),
    }, SetOptions(merge: true));
  }

  /// Bu arkadaşla ortak olan askılıklar.
  List<Board> boardsWith(String friendId) =>
      custom.where((b) => b.people.containsKey(friendId)).toList();

  void removeFriend(String id) {
    friends.remove(id);
    notifyListeners();
    _saveLocal();
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
    _profileSub?.cancel();
    for (final s in _shareSubs.values) {
      s.cancel();
    }
    for (final t in _shareTimers.values) {
      t.cancel();
    }
    _sub?.cancel();
    _debounce?.cancel();
    super.dispose();
  }
}
