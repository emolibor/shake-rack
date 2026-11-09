import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import 'board.dart';

/// Tüm uygulama durumu.
///
/// - Her değişiklik önce yerelde (shared_preferences) saklanır → çevrimdışı çalışır.
/// - **Projeler** yöneticinin askılığıdır; yönetici kişi kişi görme/düzenleme
///   yetkisi verir (sunucu kuralları uygular).
/// - **Özel askılıklar** yalnızca bu telefonda saklanır; paylaşılırsa her
///   katılım için yönetici onayı gerekir. Yönetici içeriklerini göremez.
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
  static const _kProjectsOwner = 'projects_owner_v1';
  static const _kProjectsLog = 'projects_log_v1';
  static const _kHistorySeen = 'history_seen_v1';
  static const _kDoneSeen = 'done_seen_v1';
  static const _kProjectsUsed = 'projects_used_v1';
  static const _kProjectsPerm = 'projects_perm_v1';
  static const _kProjectsCopy = 'projects_copy_v1';
  static const _kAdminKey = 'admin_key_v1';
  static const _kLegacyPending = 'legacy_projects_pending_v1';
  static const _kProjectsAccess = 'projects_access_v1';

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

  /// Bu telefonda Projeler daha önce kullanıldı mı (yeni kurulumda hayır →
  /// "Ekip projeleri" seçeneği ve Mesaj sekmesi gösterilmez).
  bool projectsEverUsed = false;

  /// Projeler paylaşımının izinleri (sahip belirler, belgeden okunur).
  String projectsPermission = 'edit';
  bool projectsAllowCopy = true;

  /// Proje kodunun sahibi (profil kimliği). Sadece sahip askılığı yönetir:
  /// adını, proje türlerini, ekip kullanıcılarını değiştirir, silinenleri geri yükler.
  String? projectsOwner;

  /// Projeler'i (ad, türler, ekip) sadece yönetici yönetir; bulutla eşitlenmeyen
  /// yerel bir Projeler'i sahibi yönetir.
  bool get canManageProjects => isAdmin || !projectsLinked;

  /// Projeler askılığının işlem geçmişi (ekip koduyla eşitlenir).
  List<Activity> projectsLog = [];

  /// Geçmiş sekmesine en son ne zaman bakıldı (rozet için).
  DateTime historySeenAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Bitenler sekmesine en son ne zaman bakıldı.
  DateTime doneSeenAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Son bakıştan beri tamamlanan kart sayısı (Bitenler rozeti).
  int get unseenCompleted => boards
      .expand((b) => b.completed)
      .where((c) => c.completedAt != null && c.completedAt!.isAfter(doneSeenAt))
      .length;

  void markDoneSeen() {
    doneSeenAt = DateTime.now();
    notifyListeners();
    SharedPreferences.getInstance()
        .then((p) => p.setString(_kDoneSeen, doneSeenAt.toIso8601String()));
  }

  /// Diğer kullanıcıların, son bakıştan beri yaptığı işlem sayısı.
  int get unseenActivities => activities
      .where((a) => a.by != profile.id && a.at.isAfter(historySeenAt))
      .length;

  void markHistorySeen() {
    historySeenAt = DateTime.now();
    notifyListeners();
    SharedPreferences.getInstance()
        .then((p) => p.setString(_kHistorySeen, historySeenAt.toIso8601String()));
  }

  /// Tüm ortak askılıkların geçmişi, yeniden eskiye.
  List<Activity> get activities {
    final all = <Activity>[
      if (!projectsHidden) ...projectsLog,
      for (final b in custom) ...b.log,
    ]..sort((a, b) => b.at.compareTo(a.at));
    return all;
  }

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
  List<CompanyCard> get cards => projects.live;
  List<CompanyCard> get active => projects.active;
  List<CompanyCard> get completed => projects.completed;
  CompanyCard addCard(String name, List<String> types, {String? assignedTo}) =>
      projects.addCard(name, types, assignedTo: assignedTo);
  bool toggleItem(CompanyCard card, ProjectItem item) =>
      projects.toggleItem(card, item);

  /// Eski sürümün ekip kodu (sadece taşıma için okunur).
  String rackCode = '';
  bool firebaseReady = false; // Firebase.initializeApp başarılı mı
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
    // Yeni kurulum: hiç veri yok → Projeler gizli başlar (sıradan kullanıcı).
    final fresh = !p.containsKey(_kCards) &&
        !p.containsKey(_kRackCode) &&
        !p.containsKey(_kProjectsHidden);
    projectsHidden = p.getBool(_kProjectsHidden) ?? fresh;
    projectsEverUsed = p.getBool(_kProjectsUsed) ?? !fresh;
    projectsPermission = p.getString(_kProjectsPerm) ?? 'edit';
    projectsAllowCopy = p.getBool(_kProjectsCopy) ?? true;
    projects.name = p.getString(_kProjectsName) ?? projects.name;
    projectsOwner = p.getString(_kProjectsOwner);
    historySeenAt = DateTime.tryParse(p.getString(_kHistorySeen) ?? '') ?? historySeenAt;
    final ds = DateTime.tryParse(p.getString(_kDoneSeen) ?? '');
    if (ds != null) {
      doneSeenAt = ds;
    } else {
      // ilk açılış: eski tamamlananlar rozet olarak sayılmasın
      doneSeenAt = DateTime.now();
      await p.setString(_kDoneSeen, doneSeenAt.toIso8601String());
    }
    final pl = p.getString(_kProjectsLog);
    if (pl != null) projectsLog = _parseLog(jsonDecode(pl));
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
    adminKey = p.getString(_kAdminKey);
    legacyProjectsPending = p.getBool(_kLegacyPending) ?? false;
    projectsAccess = p.getString(_kProjectsAccess) ?? 'none';
    deviceId = p.getString(_kDeviceId) ?? '';
    if (deviceId.isEmpty) {
      deviceId = _uuid.v4();
      await p.setString(_kDeviceId, deviceId);
    }
    _syncProjectsShareState();
    if (renamed || fresh) await _saveLocal();
    notifyListeners();
    unawaited(_startCloud());
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

  /// Kayıtları birleştir: art arda gelen değişiklikler (hızlı tikler, eşitleme)
  /// tek bir yazmada toplanır → daha az disk işi, takılma yok.
  Future<void>? _savePending;
  Future<void> _saveLocal() => _savePending ??= Future(() async {
        _savePending = null;
        try {
          await _writeLocal();
        } catch (e) {
          debugPrint('Yerel kayıt başarısız: $e');
        }
      });

  Future<void> _writeLocal() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _kCards, jsonEncode(projects.cards.map((e) => e.toJson()).toList()));
    await p.setStringList(_kProjectTypes, projects.template);
    await p.setStringList(_kBoardOrder, boardOrder);
    await p.setBool(_kProjectsHidden, projectsHidden);
    await p.setBool(_kProjectsUsed, projectsEverUsed);
    await p.setString(_kProjectsPerm, projectsPermission);
    await p.setBool(_kProjectsCopy, projectsAllowCopy);
    await p.setString(_kProjectsName, projects.name);
    if (projectsOwner == null) {
      await p.remove(_kProjectsOwner);
    } else {
      await p.setString(_kProjectsOwner, projectsOwner!);
    }
    await p.setString(
        _kProjectsLog, jsonEncode(projectsLog.map((e) => e.toJson()).toList()));
    await p.setString(_kProfile, jsonEncode(profile.toJson()));
    await p.setString(
        _kFriends, jsonEncode(friends.values.map((e) => e.toJson()).toList()));
    await p.setString(
        _kCustom, jsonEncode(custom.map((e) => e.toJson()).toList()));
    await p.setString(
        _kMembers, jsonEncode(members.map((e) => e.toJson()).toList()));
    await p.setString(_kCurrent, currentMemberId);
    await p.setString(_kRackCode, rackCode);
    if (adminKey == null) {
      await p.remove(_kAdminKey);
    } else {
      await p.setString(_kAdminKey, adminKey!);
    }
    await p.setBool(_kLegacyPending, legacyProjectsPending);
    await p.setString(_kProjectsAccess, projectsAccess);
  }

  /// Grupla paylaşılan veri. Özel askılıklar burada YOK.
  Map<String, dynamic> sharedJson() => {
        'cards': projects.cards.map((e) => e.toJson()).toList(),
        'members': members.map((e) => e.toJson()).toList(),
        'projectTypes': projects.template,
        'projectsName': projects.name,
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

  // =====================================================================
  // BULUT — kimlik, yönetici, Projeler yetkisi, onaylı paylaşım
  // =====================================================================
  //
  // Firestore yapısı (kurallar sunucuda uygulanır, bkz. firestore.rules):
  //   users/{uid}             profil (ad, emoji, renk) + projectsAccess (yönetici yazar)
  //   adminClaim/{gizliAnahtar}  {uid}: yöneticinin kim olduğu
  //   projects/main           yöneticinin Projeler askılığı + access {uid: view|edit}
  //   shares/{KOD}            paylaşılan özel askılık + members {uid: {ad, rol}}
  //   joinRequests/{KOD_uid}  katılma isteği (yönetici onaylar)
  //   racks/*                 eski sürüm verisi (sadece taşıma için okunur/silinir)

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Giriş yapılmış kimlik (anonim). Boşsa bulut kapalı.
  String uid = '';
  bool get signedIn => uid.isNotEmpty;

  /// Yönetici mi (adminClaim/{adminKey}.uid == uid).
  bool isAdmin = false;
  String? adminKey;

  /// Yönetici değilse: yöneticinin Projeler'ine erişim (none / view / edit).
  String projectsAccess = 'none';

  /// Eski sürümden kalan Projeler verisi yönetici girişini bekliyor.
  bool legacyProjectsPending = false;

  /// Projeler bulutla eşitleniyor mu (yönetici ya da yetki verilmiş kullanıcı).
  bool get projectsLinked => isAdmin || projectsAccess != 'none';

  /// Yönetim paneli verileri (sadece yöneticide dolar).
  List<AppUser> users = [];
  List<JoinRequest> pendingRequests = [];

  /// Benim katılma isteklerim (paylaşım kodu → istek).
  Map<String, JoinRequest> myJoins = {};

  StreamSubscription? _meSub, _usersSub, _pendingSub, _myJoinsSub;

  DocumentReference<Map<String, dynamic>> get _doc =>
      _db.collection('projects').doc('main');
  DocumentReference<Map<String, dynamic>> _shareDoc(String code) =>
      _db.collection('shares').doc(code.toUpperCase());
  DocumentReference<Map<String, dynamic>> _userDoc(String id) =>
      _db.collection('users').doc(id);

  /// Açılışta: anonim giriş → profil kaydı → yönetici/yetki dinleme → eşitleme.
  Future<void> _startCloud() async {
    if (!firebaseReady) return;
    try {
      final auth = FirebaseAuth.instance;
      final user = auth.currentUser ?? (await auth.signInAnonymously()).user;
      if (user == null) return;
      uid = user.uid;
    } catch (e) {
      syncStatus = 'Hata: giriş yapılamadı (Firebase → Anonymous açık mı?)';
      notifyListeners();
      return;
    }
    if (profile.id != uid) {
      profile = Member(id: uid, name: profile.name, color: profile.color, emoji: profile.emoji);
      await _saveLocal();
    }
    await _publishProfile();
    // yönetici mi?
    if (adminKey != null) {
      try {
        final s = await _db.collection('adminClaim').doc(adminKey).get();
        isAdmin = s.data()?['uid'] == uid;
      } catch (_) {
        isAdmin = false;
      }
    }
    await _migrateLegacy();
    if (isAdmin) {
      await _becomeAdmin();
    } else {
      _listenMe();
    }
    _listenMyJoins();
    for (final b in custom) {
      if (b.isShared) _listenShared(b);
    }
    notifyListeners();
  }

  Future<void> _publishProfile() async {
    if (!signedIn || !hasProfile) return;
    try {
      await _userDoc(uid).set({
        'name': profile.name,
        'emoji': profile.emoji,
        'color': profile.color.value,
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  // ---------- eski sürümden geçiş ----------

  /// Eski "racks" verisi: paylaşılan özel askılıklar yeni sisteme taşınır
  /// (sahipse aynı kodla yeniden paylaşılır, katılanlar yeniden onay ister),
  /// Projeler'in eski bağlantısı kapanır, veri yönetici girişini bekler.
  Future<void> _migrateLegacy() async {
    var changed = false;
    for (final b in custom.where((b) => b.isShared && !b.shareV2).toList()) {
      final code = b.shareCode!;
      if (b.role == ShareRole.owner) {
        try {
          await _db.collection('racks').doc('share_${code.toLowerCase()}').delete();
        } catch (_) {}
        b.people = {};
        try {
          await _createShare(b, code: code, canEdit: b.shareCanEdit, allowCopy: b.allowCopy);
        } catch (_) {
          b.shareCode = null;
          b.role = null;
        }
      } else {
        b.shareCode = null;
        b.role = null;
        b.shareEnded = true;
      }
      changed = true;
    }
    if (rackCode.isNotEmpty && !isAdmin && projectsAccess == 'none' && !legacyProjectsPending) {
      // eski ekip kodu: veri kalsın, yönetici girişi gelirse buluta taşınır
      legacyProjectsPending = projects.live.isNotEmpty;
      if (legacyProjectsPending) projectsHidden = true;
      changed = true;
    }
    if (changed) await _saveLocal();
  }

  /// Eski ekip kodu belgesini sil (yönetici, taşıdıktan sonra).
  Future<void> _dropLegacyRack() async {
    if (rackCode.isEmpty) return;
    try {
      await _db.collection('racks').doc(rackCode).delete();
    } catch (_) {}
    rackCode = '';
  }

  // ---------- yönetici ----------

  /// Yönetici anahtarını gir (bir kez). Doğruysa bu telefon yönetici olur.
  Future<bool> claimAdmin(String key) async {
    if (!signedIn) throw StateError('Önce internete bağlan.');
    final k = key.trim();
    if (k.isEmpty) return false;
    try {
      await _db.collection('adminClaim').doc(k).set({'uid': uid, 'name': profile.name});
    } catch (_) {
      return false; // kural reddetti: anahtar yanlış
    }
    adminKey = k;
    isAdmin = true;
    _meSub?.cancel();
    legacyProjectsPending = false;
    await _becomeAdmin();
    await _saveLocal();
    notifyListeners();
    return true;
  }

  Future<void> _becomeAdmin() async {
    projectsEverUsed = true;
    legacyProjectsPending = false;
    if (projectsHidden && projects.live.isNotEmpty) projectsHidden = false;
    // Projeler belgesi yoksa yereldekinden oluştur
    try {
      final s = await _doc.get();
      if (!s.exists) {
        await _doc.set({
          ...sharedJson(),
          'owner': uid,
          'ownerName': profile.name,
          'access': <String, String>{},
          'people': {uid: _meEntry(ShareRole.owner)},
          'log': projectsLog.map((e) => e.toJson()).toList(),
          'updatedBy': deviceId,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (_) {}
    await _dropLegacyRack();
    _syncProjectsShareState();
    _listen();
    _usersSub?.cancel();
    _usersSub = _db.collection('users').snapshots().listen((q) {
      users = q.docs.map((d) => AppUser.fromDoc(d.id, d.data())).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      notifyListeners();
    }, onError: (_) {});
    _pendingSub?.cancel();
    _pendingSub = _db
        .collection('joinRequests')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((q) {
      pendingRequests = q.docs.map((d) => JoinRequest.fromDoc(d.id, d.data())).toList()
        ..sort((a, b) => (a.createdAt ?? DateTime(2000)).compareTo(b.createdAt ?? DateTime(2000)));
      notifyListeners();
    }, onError: (_) {});
  }

  /// Yönetici: bir kullanıcıya Projeler yetkisi ver / değiştir / kaldır.
  Future<void> setProjectsAccess(AppUser u, String access) async {
    if (!isAdmin) return;
    final batch = _db.batch();
    if (access == 'none') {
      batch.update(_doc, {
        'access.${u.uid}': FieldValue.delete(),
        'people.${u.uid}': FieldValue.delete(),
      });
    } else {
      batch.update(_doc, {
        'access.${u.uid}': access,
        'people.${u.uid}': {
          'name': u.name,
          'color': u.color,
          'emoji': u.emoji,
          'role': access == 'edit' ? 'editor' : 'viewer',
        },
      });
    }
    batch.update(_userDoc(u.uid), {'projectsAccess': access});
    await batch.commit();
  }

  /// Yönetici: katılma isteğini onayla / reddet.
  Future<void> decideJoin(JoinRequest r, bool approve) async {
    if (!isAdmin) return;
    await _db.collection('joinRequests').doc(r.id).update({
      'status': approve ? 'approved' : 'rejected',
      'decidedAt': FieldValue.serverTimestamp(),
    });
  }

  // ---------- Projeler (yöneticinin askılığı) ----------

  /// Yönetici değilsem: kendi kullanıcı belgemden Projeler yetkimi dinle.
  void _listenMe() {
    _meSub?.cancel();
    _meSub = _userDoc(uid).snapshots().listen((s) async {
      final a = '${s.data()?['projectsAccess'] ?? 'none'}';
      if (a == projectsAccess) return;
      applyProjectsAccess(a);
      await _saveLocal();
    }, onError: (_) {});
  }

  /// Yöneticinin verdiği Projeler yetkisini uygula (none / view / edit).
  void applyProjectsAccess(String a) {
    final before = projectsLinked;
    projectsAccess = a;
    if (projectsLinked && !before) {
      // yetki verildi → Projeler belirir (eski yerel kopyanın yerini alır)
      legacyProjectsPending = false;
      rackCode = '';
      projectsHidden = false;
      projectsEverUsed = true;
      _syncProjectsShareState();
      _listen();
    } else if (!projectsLinked && before) {
      // yetki kaldırıldı → Projeler bu telefondan kalkar
      _sub?.cancel();
      _sub = null;
      projects.cards = [];
      projectsLog = [];
      projectsHidden = true;
      syncStatus = 'Yerel';
    }
    _syncProjectsShareState();
    notifyListeners();
  }

  /// Projeler'in paylaşım durumu (rol, kişiler).
  void _syncProjectsShareState() {
    if (!projectsLinked) {
      projects.shareCode = null;
      projects.role = null;
      projects.people = {};
      return;
    }
    projects.shareCode = 'PROJECTS';
    projects.shareV2 = true;
    projects.role = isAdmin
        ? ShareRole.owner
        : (projectsAccess == 'edit' ? ShareRole.editor : ShareRole.viewer);
    projects.shareCanEdit = projectsAccess == 'edit' || isAdmin;
  }

  bool get syncing => firebaseReady && signedIn && projectsLinked;

  Map<String, dynamic> _toCloud() => isAdmin
      ? {
          ...sharedJson(),
          'revision': _revision,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': deviceId,
        }
      : {
          // yetkili kullanıcı sadece kartları yazar (kurallar ayarları korur)
          'cards': projects.cards.map((e) => e.toJson()).toList(),
          'revision': _revision,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': deviceId,
        };

  /// Yazmaları 300 ms toplayıp tek seferde gönderir (hızlı tik atmalarda).
  void _pushCloud() {
    if (!syncing || !projects.canEdit) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      _revision++;
      try {
        await _doc.set(_toCloud(), SetOptions(merge: true));
        syncStatus = 'Eşitlendi';
      } catch (e) {
        syncStatus = 'Kaydedilemedi (yetki / bağlantı)';
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
      if (!snap.exists) return;
      applyProjectsSnapshot(snap.data()!, pending: _debounce?.isActive ?? false);
      if (isAdmin) _trimLog(_doc, projectsLog, isOwner: true);
      await _saveLocal();
      syncStatus = snap.metadata.isFromCache ? 'Çevrimdışı' : 'Eşitlendi';
      notifyListeners();
    }, onError: (_) {
      syncStatus = 'Erişim yok';
      notifyListeners();
    });
  }

  /// Projeler belgesinin son halini uygula (içerik, kişiler, geçmiş).
  void applyProjectsSnapshot(Map<String, dynamic> d, {bool pending = false}) {
    projectsOwner = d['owner'] as String?;
    projectsLog = _parseLog(d['log']);
    _absorbMembers(projects, d['people']);
    _syncProjectsShareState();
    if (d['updatedBy'] != deviceId && !pending) {
      _applyCloud(d);
      if (memberById(currentMemberId) == null) currentMemberId = members.first.id;
    }
    notifyListeners();
  }

  /// Board değişince çağrılır. Projeler kendi belgesine, paylaşılan özel
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

  /// Askılığı güncelle (sadece yöneten). renames: adı değişen maddeler.
  void updateBoard(Board b,
      {String? name, List<String>? template, Map<String, String> renames = const {}}) {
    if (!b.canManage) return;
    if (name != null && name.trim().isNotEmpty) b.name = name.trim();
    if (template != null && template.isNotEmpty) b.template = template;
    b.applyRenames(renames);
    boardChanged(b);
  }

  /// Askılığı sil. Paylaşan sahipse paylaşım da kapanır; katılansa ayrılır.
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

  // ---------- askılık paylaşma (her katılım yönetici onaylı) ----------

  static const _codeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final Map<String, StreamSubscription> _shareSubs = {};
  final Map<String, Timer> _shareTimers = {};

  static String newShareCode([Random? rnd]) {
    final r = rnd ?? Random.secure();
    return List.generate(8, (_) => _codeChars[r.nextInt(_codeChars.length)]).join();
  }

  /// "k7p2-qx9m " → "K7P2QX9M"
  static String normalizeCode(String s) =>
      s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  /// Yapıştırılan bağlantıdan kodu çıkar ("…/katil/?k=K7P2QX9M&n=…" → "K7P2QX9M").
  static String extractCode(String raw) {
    final m = RegExp(r'[?&]k=([A-Za-z0-9\-]+)').firstMatch(raw);
    return m != null ? m.group(1)! : raw;
  }

  /// Bağlantıdaki diğer bilgiler (askılık adı, paylaşan, paylaşanın kimliği).
  static Map<String, String> linkParams(String raw) {
    final i = raw.indexOf('?');
    if (i < 0) return const {};
    try {
      return Uri.splitQueryString(raw.substring(i + 1).split(RegExp(r'\s')).first);
    } catch (_) {
      return const {};
    }
  }

  /// Davet bağlantısı (dokununca uygulamada katılma ekranı açılır).
  static const inviteBase = 'https://emolibor.github.io/shake-rack/katil/';

  String inviteLink(Board b) {
    final code = b.shareCode;
    if (b.isProjects || code == null || code.length != 8) return '';
    final owner = hasProfile ? profile.name : '';
    return '$inviteBase?k=$code'
        '&n=${Uri.encodeQueryComponent(b.name)}'
        '${owner.isEmpty ? '' : '&o=${Uri.encodeQueryComponent(owner)}'}'
        '${uid.isEmpty ? '' : '&u=$uid'}';
  }

  /// Projeler'e davet bağlantısı (yönetici gönderir). Dokunan kişinin
  /// uygulamasından yöneticiye erişim isteği gelir.
  String projectsInviteLink() {
    final owner = hasProfile ? profile.name : '';
    return '$inviteBase?p=1'
        '&n=${Uri.encodeQueryComponent(projects.name)}'
        '${owner.isEmpty ? '' : '&o=${Uri.encodeQueryComponent(owner)}'}';
  }

  static const projectsRequestId = 'PROJECTS';

  /// Projeler'e erişim iste (davet bağlantısından). Yönetici onaylarken
  /// Görür / Düzenler seçer.
  Future<JoinRequest?> requestProjectsAccess({String boardName = '', String ownerName = ''}) async {
    if (!firebaseReady || !signedIn) throw StateError('İnternet bağlantısı yok.');
    if (!hasProfile) throw StateError('Önce adını gir.');
    if (isAdmin) throw StateError('Yöneticisin; Projeler zaten sende.');
    if (projectsLinked) throw StateError('Projeler\'e zaten erişimin var.');
    final id = '${projectsRequestId}_$uid';
    final ref = _db.collection('joinRequests').doc(id);
    final data = {
      'shareId': projectsRequestId,
      'uid': uid,
      'name': profile.name,
      'emoji': profile.emoji,
      'color': profile.color.value,
      'boardName': boardName.isEmpty ? 'Projeler' : boardName,
      'ownerName': ownerName,
      'ownerUid': '',
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    };
    try {
      await ref.delete();
    } catch (_) {}
    await ref.set(data);
    final r = JoinRequest.fromDoc(id, {...data, 'createdAt': null});
    myJoins[projectsRequestId] = r;
    notifyListeners();
    return r;
  }

  /// Yönetici: Projeler erişim isteğini yanıtla (none = reddet).
  Future<void> decideProjectsRequest(JoinRequest r, String access) async {
    if (!isAdmin) return;
    if (access != 'none') {
      final u = users.cast<AppUser?>().firstWhere((x) => x!.uid == r.uid, orElse: () => null) ??
          AppUser(uid: r.uid, name: r.name, emoji: r.emoji, color: r.color);
      await setProjectsAccess(u, access);
    }
    await decideJoin(r, access != 'none');
  }

  Future<void> _createShare(Board b,
      {required String code, required bool canEdit, required bool allowCopy}) async {
    b.shareCode = code;
    b.shareV2 = true;
    b.role = ShareRole.owner;
    b.shareCanEdit = canEdit;
    b.allowCopy = allowCopy;
    b.shareEnded = false;
    b.people = {uid: ShareRole.owner.name};
    await _shareDoc(code).set({
      ...b.sharePayload(),
      'owner': uid,
      'ownerName': profile.name,
      'permission': canEdit ? 'edit' : 'view',
      'allowCopy': allowCopy,
      'members': {uid: _meEntry(ShareRole.owner)},
      'log': <dynamic>[],
      'updatedBy': deviceId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _listenShared(b);
  }

  /// Askılığı paylaş (ya da izinlerini güncelle). Kodu döner.
  /// Katılmak isteyen herkes için yönetici onayı gerekir.
  Future<String> shareBoard(Board b,
      {required bool canEdit, required bool allowCopy}) async {
    if (!firebaseReady || !signedIn) {
      throw StateError('Paylaşım için internet gerekli.');
    }
    if (b.isProjects) {
      throw StateError('Projeler yönetim panelinden kişi kişi yetkilendirilir.');
    }
    if (b.shareCode == null) {
      await _createShare(b, code: newShareCode(), canEdit: canEdit, allowCopy: allowCopy);
    } else {
      // izin değişti: mevcut katılanların rolünü de güncelle
      b.shareCanEdit = canEdit;
      b.allowCopy = allowCopy;
      final upd = <String, dynamic>{
        'permission': canEdit ? 'edit' : 'view',
        'allowCopy': allowCopy,
      };
      b.people.forEach((id, role) {
        if (role == 'owner') return;
        upd['members.$id.role'] = canEdit ? 'editor' : 'viewer';
      });
      await _shareDoc(b.shareCode!).update(upd);
    }
    notifyListeners();
    await _saveLocal();
    return b.shareCode!;
  }

  /// Paylaşımı kapat (sahip). Katılanlarda askılık yerel kopyaya dönüşür.
  Future<void> stopSharing(Board b) async {
    final code = b.shareCode;
    if (code == null || b.isProjects) return;
    _unlistenShared(b);
    if (b.role == ShareRole.owner && firebaseReady) {
      try {
        await _shareDoc(code).delete();
      } catch (_) {}
    }
    b.shareCode = null;
    b.role = null;
    b.people = {};
    notifyListeners();
    await _saveLocal();
  }

  /// Bağlantı ya da kodla katılma isteği gönder. Yönetici onaylayınca
  /// askılık kendiliğinden eklenir.
  Future<JoinRequest> requestJoin(String raw) async {
    if (!firebaseReady || !signedIn) throw StateError('İnternet bağlantısı yok.');
    if (!hasProfile) throw StateError('Önce adını gir.');
    final params = linkParams(raw);
    if (params['p'] == '1') {
      final r = await requestProjectsAccess(
          boardName: params['n'] ?? '', ownerName: params['o'] ?? '');
      return r!;
    }
    final code = normalizeCode(extractCode(raw.trim()));
    if (code.length != 8) throw StateError('Bağlantı geçersiz.');
    if (custom.any((b) => b.shareCode == code)) {
      throw StateError('Bu askılık zaten sende.');
    }
    if (params['u'] == uid) throw StateError('Bu senin kendi paylaşımın.');
    final id = '${code}_$uid';
    final ref = _db.collection('joinRequests').doc(id);
    final data = {
      'shareId': code,
      'uid': uid,
      'name': profile.name,
      'emoji': profile.emoji,
      'color': profile.color.value,
      'boardName': params['n'] ?? '',
      'ownerName': params['o'] ?? '',
      'ownerUid': params['u'] ?? '',
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    };
    try {
      await ref.delete(); // önceki (reddedilmiş) istek varsa
    } catch (_) {}
    await ref.set(data);
    final r = JoinRequest.fromDoc(id, {...data, 'createdAt': null});
    myJoins[code] = r;
    notifyListeners();
    return r;
  }

  /// İsteği kaldır (beklemekten vazgeç / reddedileni kapat).
  Future<void> dismissJoin(String code) async {
    myJoins.remove(code);
    notifyListeners();
    try {
      await _db.collection('joinRequests').doc('${code}_$uid').delete();
    } catch (_) {}
  }

  /// Benim katılma isteklerimi dinle; onaylanınca askılığa katıl.
  void _listenMyJoins() {
    if (!signedIn) return;
    _myJoinsSub?.cancel();
    _myJoinsSub = _db
        .collection('joinRequests')
        .where('uid', isEqualTo: uid)
        .snapshots()
        .listen((q) async {
      final next = <String, JoinRequest>{};
      for (final d in q.docs) {
        final r = JoinRequest.fromDoc(d.id, d.data());
        next[r.shareId] = r;
      }
      myJoins = next;
      notifyListeners();
      for (final r in next.values.where((r) => r.status == 'approved')) {
        if (r.shareId == projectsRequestId || custom.any((b) => b.shareCode == r.shareId)) {
          // Projeler: yetki kullanıcı belgesinden gelir; diğerleri: zaten katıldık
          // katıldık; isteği temizle
          try {
            await _db.collection('joinRequests').doc(r.id).delete();
          } catch (_) {}
          continue;
        }
        await _completeJoin(r);
      }
    }, onError: (_) {});
  }

  /// Onaylanan isteği tamamla: üye listesine kendimi ekle, askılığı getir.
  Future<void> _completeJoin(JoinRequest r) async {
    final ref = _shareDoc(r.shareId);
    Map<String, dynamic>? data;
    // izne göre rolü kural belirler: önce düzenleyici dene, olmazsa izleyici
    for (final role in [ShareRole.editor, ShareRole.viewer]) {
      try {
        await ref.update({'members.$uid': _meEntry(role)});
        final s = await ref.get();
        data = s.data();
        break;
      } catch (_) {}
    }
    if (data == null) {
      // onaylandı ama paylaşım bu arada kapatılmış: isteği temizle
      try {
        await _db.collection('joinRequests').doc(r.id).delete();
      } catch (_) {}
      myJoins.remove(r.shareId);
      notifyListeners();
      return;
    }
    attachShared(data, r.shareId);
    try {
      await _db.collection('joinRequests').doc(r.id).delete();
    } catch (_) {}
    myJoins.remove(r.shareId);
    notifyListeners();
    await _saveLocal();
  }

  /// Üyesi olduğum paylaşım belgesinden askılığı ekle (onaydan sonra).
  Board attachShared(Map<String, dynamic> data, String code) {
    final existing = custom.cast<Board?>()
        .firstWhere((x) => x!.shareCode == code, orElse: () => null);
    if (existing != null) return existing;
    final b = Board.fromShare(data)..store = this;
    b.shareCode = code;
    b.shareV2 = true;
    final mine = (data['members'] is Map) ? (data['members'] as Map)[uid] : null;
    final role = mine is Map ? '${mine['role']}' : null;
    b.shareCanEdit = role == 'editor' || (role == null && data['permission'] != 'view');
    b.role = b.shareCanEdit ? ShareRole.editor : ShareRole.viewer;
    b.allowCopy = data['allowCopy'] ?? false;
    _absorbMembers(b, data['members']);
    b.people[uid] = b.role!.name;
    b.log = _parseLog(data['log']);
    custom.add(b);
    _listenShared(b);
    notifyListeners();
    _saveLocal();
    return b;
  }

  /// Paylaşılan askılığın bağımsız kopyasını kendi askılıklarına ekle.
  Board copyShared(Map<String, dynamic> data, {String? name}) {
    final b = Board.fromShare(data)..store = this;
    if (name != null) b.name = name;
    b.cards.removeWhere((c) => c.deleted);
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
      final owner = b.role == ShareRole.owner;
      try {
        await _shareDoc(code).set({
          if (owner) ...b.sharePayload() else 'cards': b.cards.map((e) => e.toJson()).toList(),
          'updatedBy': deviceId,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {/* çevrimdışı ya da yetki yok */}
    });
  }

  void _listenShared(Board b) {
    if (!firebaseReady || !signedIn || b.shareCode == null) return;
    _unlistenShared(b);
    void ended() async {
      if (b.role == ShareRole.owner) return;
      // paylaşım kapandı ya da çıkarıldım → bu telefonda bağımsız kopya
      _unlistenShared(b);
      b.shareCode = null;
      b.role = null;
      b.people = {};
      b.shareEnded = true;
      notifyListeners();
      await _saveLocal();
    }

    _shareSubs[b.id] = _shareDoc(b.shareCode!).snapshots().listen((snap) async {
      if (!snap.exists) {
        if (!snap.metadata.isFromCache) ended();
        return;
      }
      final pending = _shareTimers[b.id]?.isActive ?? false;
      applySharedSnapshot(b, snap.data()!, pending: pending);
      await _saveLocal();
    }, onError: (_) => ended());
  }

  /// Paylaşım belgesindeki son durumu askılığa uygula: içerik, izinler, üyeler.
  void applySharedSnapshot(Board b, Map<String, dynamic> d, {bool pending = false}) {
    if (d['updatedBy'] != deviceId && !pending) b.applyShared(d);
    if (b.role != ShareRole.owner) {
      final mine = (d['members'] is Map) ? (d['members'] as Map)[uid] : null;
      final role = mine is Map ? '${mine['role']}' : null;
      b.shareCanEdit = role == 'editor' || (role == null && d['permission'] != 'view');
      b.role = b.shareCanEdit ? ShareRole.editor : ShareRole.viewer;
      b.allowCopy = d['allowCopy'] ?? false;
    }
    _absorbMembers(b, d['members']);
    b.log = _parseLog(d['log']);
    if (b.role == ShareRole.owner && b.shareCode != null && firebaseReady) {
      _trimLog(_shareDoc(b.shareCode!), b.log, isOwner: true);
    }
    notifyListeners();
  }

  /// Belgedeki kişileri askılığa yaz; kendin dışındakileri arkadaş listesine ekle.
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

  /// Katılan askılıktan ayrılınca üye listesinden çık.
  Future<void> _leaveMembers(Board b) async {
    if (!firebaseReady || b.shareCode == null) return;
    try {
      await _shareDoc(b.shareCode!).update({'members.$uid': FieldValue.delete()});
    } catch (_) {}
  }

  // ---------- Projeler askılığı (isteğe bağlı) ----------

  /// Projeler'i bu telefondan kaldır. Bulutla eşitleniyorsa (yönetici ya da
  /// yetkili) bulut verisine dokunulmaz; değilse içerik de temizlenir.
  Future<void> hideProjects() async {
    projectsHidden = true;
    if (!projectsLinked) {
      projects.cards = [];
      projects.template = List.of(kProjectTypes);
      projects.name = 'Projeler';
    }
    boardOrder.remove(projects.id);
    notifyListeners();
    await _saveLocal();
  }

  /// Projeler'i geri ekle.
  Board showProjects() {
    projectsHidden = false;
    notifyListeners();
    _saveLocal();
    return projects;
  }

  // ---------- profil ve arkadaşlar ----------

  Future<void> updateProfile({String? name, Color? color, String? emoji}) async {
    profile = profile.copyWith(name: name?.trim(), color: color, emoji: emoji);
    notifyListeners();
    await _saveLocal();
    if (!firebaseReady || !signedIn || !hasProfile) return;
    await _publishProfile();
    try {
      for (final b in custom.where((b) => b.isShared)) {
        await _shareDoc(b.shareCode!)
            .update({'members.$uid': _meEntry(b.role ?? ShareRole.editor)});
      }
    } catch (_) {}
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

  /// Sıradaki numarayla "Kullanıcı N" ekler (sadece askılık sahibi).
  Member? addMember() {
    if (!canManageProjects) return null;
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
    if (!canManageProjects || members.length <= 1) return false;
    members.removeWhere((m) => m.id == id);
    for (final c in projects.cards) {
      if (c.assignedTo == id) c.assignedTo = null;
    }
    if (currentMemberId == id) currentMemberId = members.first.id;
    _membersChanged();
    return true;
  }

  void updateMember(String id, {String? name, Color? color}) {
    if (!canManageProjects) return;
    final i = members.indexWhere((m) => m.id == id);
    if (i < 0) return;
    members[i] = Member(
      id: id,
      name: (name == null || name.trim().isEmpty) ? members[i].name : name.trim(),
      color: color ?? members[i].color,
    );
    _membersChanged();
  }

  // ---------- işlem geçmişi ----------

  static List<Activity> _parseLog(dynamic raw) => raw is List
      ? raw
          .whereType<Map>()
          .map((e) => Activity.fromJson(Map<String, dynamic>.from(e)))
          .toList()
      : <Activity>[];

  /// Ortak askılıkta yapılan işlemi geçmişe yaz (yalnız/kodsuz askılıklarda yazılmaz).
  void logActivity(Board b, String action, CompanyCard card, String item) {
    final shared = b.isProjects ? projectsLinked : b.isShared;
    if (!shared) return;
    final a = Activity(
      id: _uuid.v4(),
      at: DateTime.now(),
      by: profile.id,
      byName: hasProfile ? profile.name : me.name,
      byColor: (hasProfile ? profile.color : me.color).value,
      byEmoji: hasProfile ? profile.emoji : '',
      boardId: b.id,
      boardName: b.name,
      action: action,
      cardId: card.id,
      card: card.name,
      item: item,
    );
    final list = b.isProjects ? projectsLog : b.log;
    list.add(a);
    if (list.length > 400) list.removeRange(0, list.length - 400);
    if (!firebaseReady || !signedIn) return;
    final doc = b.isProjects ? _doc : _shareDoc(b.shareCode!);
    // arrayUnion: aynı anda iki kişi işlem yapsa da kayıt kaybolmaz
    doc.update({
      'log': FieldValue.arrayUnion([a.toJson()])
    }).catchError((_) {});
  }

  /// Geçmiş çok uzarsa (sahip) eskileri buda.
  void _trimLog(DocumentReference<Map<String, dynamic>> doc, List<Activity> log,
      {required bool isOwner}) {
    if (!isOwner || log.length <= 400) return;
    final keep = ([...log]..sort((a, b) => a.at.compareTo(b.at)))
        .skip(log.length - 300)
        .map((e) => e.toJson())
        .toList();
    doc.update({'log': keep}).catchError((_) {});
  }

  /// Bu kayıttaki silinen kart hâlâ geri yüklenebilir mi?
  ({Board board, CompanyCard card})? restorable(Activity a) {
    if (a.action != 'delete') return null;
    final b = a.boardId == Board.projectsId ? projects : boardById(a.boardId);
    if (b == null || !b.canManage) return null;
    final c = b.cardById(a.cardId);
    if (c == null || !c.deleted) return null;
    return (board: b, card: c);
  }

  /// Sahibin adı (arkadaş listesinden ya da proje ekibinden).
  String get projectsOwnerName {
    final o = projectsOwner;
    if (o == null) return 'yönetici';
    if (o == profile.id) return hasProfile ? profile.name : 'Sen';
    return friends[o]?.name ?? 'yönetici';
  }

  @override
  void dispose() {
    for (final s in [_meSub, _usersSub, _pendingSub, _myJoinsSub]) {
      s?.cancel();
    }
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
