import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';

/// Tüm uygulama durumu.
///
/// - Her değişiklik önce yerelde (shared_preferences) saklanır → çevrimdışı çalışır.
/// - Bir "askılık kodu" girildiyse aynı veri Firestore'da `racks/{kod}` belgesine
///   yazılır ve oradan canlı dinlenir → iki telefon aynı ipi görür.
class RackStore extends ChangeNotifier {
  static const _kCards = 'cards_v1';
  static const _kMembers = 'members_v1';
  static const _kCurrent = 'current_member_v1';
  static const _kRackCode = 'rack_code_v1';
  static const _kDeviceId = 'device_id_v1';

  /// Bu cihaza özel kimlik — kendi yazdığımız güncellemeyi tanımak için.
  String deviceId = '';

  final _uuid = const Uuid();
  List<CompanyCard> cards = [];
  List<Member> members = List.of(kDefaultMembers);
  String currentMemberId = 'me';

  /// Paylaşılan askılık kodu (ör. "fourmis-2026"). Boşsa sadece yerel.
  String rackCode = '';
  bool firebaseReady = false; // Firebase.initializeApp başarılı mı
  bool get syncing => firebaseReady && rackCode.isNotEmpty;
  String syncStatus = 'Yerel';

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  int _revision = 0; // kendi yazdığımızı geri okumamak için
  Timer? _debounce;

  Member get me => members.firstWhere((m) => m.id == currentMemberId,
      orElse: () => members.first);
  Member? memberById(String? id) => id == null
      ? null
      : members.cast<Member?>().firstWhere((m) => m!.id == id, orElse: () => null);

  List<CompanyCard> get active => cards.where((c) => !c.completed).toList();
  List<CompanyCard> get completed => cards.where((c) => c.completed).toList()
    ..sort((a, b) =>
        (b.completedAt ?? b.createdAt).compareTo(a.completedAt ?? a.createdAt));

  // ---------- yükleme / kayıt ----------

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final c = p.getString(_kCards);
    if (c != null) {
      cards = (jsonDecode(c) as List).map((e) => CompanyCard.fromJson(e)).toList();
    }
    final m = p.getString(_kMembers);
    if (m != null) {
      members = (jsonDecode(m) as List).map((e) => Member.fromJson(e)).toList();
    }
    currentMemberId = p.getString(_kCurrent) ?? 'me';
    rackCode = p.getString(_kRackCode) ?? '';
    deviceId = p.getString(_kDeviceId) ?? '';
    if (deviceId.isEmpty) {
      deviceId = _uuid.v4();
      await p.setString(_kDeviceId, deviceId);
    }
    notifyListeners();
    if (rackCode.isNotEmpty) _listen();
  }

  Future<void> _saveLocal() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kCards, jsonEncode(cards.map((e) => e.toJson()).toList()));
    await p.setString(_kMembers, jsonEncode(members.map((e) => e.toJson()).toList()));
    await p.setString(_kCurrent, currentMemberId);
    await p.setString(_kRackCode, rackCode);
  }

  Map<String, dynamic> _toCloud() => {
        'cards': cards.map((e) => e.toJson()).toList(),
        'members': members.map((e) => e.toJson()).toList(),
        'revision': _revision,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': deviceId,
      };

  void _applyCloud(Map<String, dynamic> d) {
    cards = (d['cards'] as List? ?? [])
        .map((e) => CompanyCard.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final ms = d['members'] as List?;
    if (ms != null && ms.isNotEmpty) {
      members = ms.map((e) => Member.fromJson(Map<String, dynamic>.from(e))).toList();
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
    rackCode = code.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9\-_]'), '-');
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

  void _commit() {
    notifyListeners();
    _saveLocal();
    _pushCloud();
  }

  // ---------- kartlar ----------
  CompanyCard addCard(String name, List<String> types, {String? assignedTo}) {
    final card = CompanyCard(
      id: _uuid.v4(),
      name: name.trim(),
      items: types.map((t) => ProjectItem(type: t)).toList(),
      assignedTo: assignedTo,
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
      final old = {for (final i in card.items) i.type: i};
      card.items = types.map((t) => old[t] ?? ProjectItem(type: t)).toList();
    }
    _commit();
  }

  void deleteCard(CompanyCard card) {
    cards.remove(card);
    _commit();
  }

  void reorderActive(int oldIndex, int newIndex) {
    final act = active;
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = act.removeAt(oldIndex);
    act.insert(newIndex, moved);
    final done = cards.where((c) => c.completed).toList();
    cards = [...act, ...done];
    _commit();
  }

  bool toggleItem(CompanyCard card, ProjectItem item) {
    item.done = !item.done;
    if (item.done) {
      item.doneBy = currentMemberId;
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

  // ---------- ekip ----------
  void setCurrentMember(String id) {
    currentMemberId = id;
    notifyListeners();
    _saveLocal(); // kişi seçimi cihaza özel, buluta gitmez
  }

  void updateMember(String id, {String? name, Color? color}) {
    final i = members.indexWhere((m) => m.id == id);
    if (i < 0) return;
    members[i] = Member(
      id: id,
      name: name ?? members[i].name,
      color: color ?? members[i].color,
    );
    _commit();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _debounce?.cancel();
    super.dispose();
  }
}
