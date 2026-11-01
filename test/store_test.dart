import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shake_rack/services/assistant.dart';
import 'package:shake_rack/services/board.dart';
import 'package:shake_rack/models/models.dart';
import 'package:shake_rack/services/store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Özel askılıklar', () {
    test('buluta giden veride özel askılık yok', () {
      final store = RackStore();
      store.addCard('Atilla Tekstil', ['Mimari Proje']);
      final reels = store.addBoard('Reels', ['Instagram', 'YouTube']);
      reels.addCard('GİZLİ kat planı videosu', reels.template);

      final shared = jsonEncode(store.sharedJson());
      expect(shared, contains('Atilla Tekstil'));
      expect(shared, isNot(contains('GİZLİ')));
      expect(shared, isNot(contains('Reels')));
      expect(shared, isNot(contains('Instagram')));
    });

    test('şablon maddeleriyle kart, hepsi tiklenince tamamlanır', () {
      final store = RackStore();
      final reels = store.addBoard('Reels', ['Instagram', 'YouTube']);
      final c = reels.addCard('Cephe çizimi', reels.template);
      expect(c.items.map((e) => e.type), ['Instagram', 'YouTube']);
      expect(reels.toggleItem(c, c.items[0]), isFalse);
      expect(reels.toggleItem(c, c.items[1]), isTrue);
      reels.markCompleted(c);
      expect(reels.active, isEmpty);
      expect(reels.completed.single.name, 'Cephe çizimi');
      // Projeler askılığı etkilenmez
      expect(store.projects.cards, isEmpty);
    });

    test('kayıttan geri yüklenir', () async {
      final a = RackStore();
      final reels = a.addBoard('Reels', ['Instagram']);
      reels.addCard('Video 1', reels.template);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final b = RackStore();
      await b.load();
      expect(b.custom.single.name, 'Reels');
      expect(b.custom.single.cards.single.name, 'Video 1');
      // geri yüklenen askılık da kaydedebilmeli
      b.custom.single.addCard('Video 2', ['Instagram']);
      expect(b.custom.single.cards.length, 2);
    });

    test('askılık silinir; Projeler de silinip geri eklenebilir', () async {
      final store = RackStore();
      store.addCard('Atilla', ['Mimari Proje']);
      final r = store.addBoard('Reels', ['Instagram']);
      await store.deleteBoard(r);
      expect(store.boards.map((b) => b.id), ['projects']);
      await store.deleteBoard(store.projects);
      expect(store.boards, isEmpty);
      expect(store.projects.cards, isEmpty); // ekip koduna bağlı değil → temizlendi
      store.showProjects();
      expect(store.boards.map((b) => b.id), ['projects']);
    });
  });

  group('Kullanıcılar', () {
    test('varsayılan adlar Kullanıcı 1 ve 2', () {
      final store = RackStore();
      expect(store.members.map((m) => m.name), ['Kullanıcı 1', 'Kullanıcı 2']);
    });

    test('eski adlar (Ben / Arkadaşım) yeni adlara çevrilir', () async {
      SharedPreferences.setMockInitialValues({
        'members_v1': jsonEncode([
          {'id': 'me', 'name': 'Ben', 'color': 0xFF2E7DE0},
          {'id': 'friend', 'name': 'Arkadaşım', 'color': 0xFF2EA35A},
        ]),
      });
      final store = RackStore();
      await store.load();
      expect(store.members.map((m) => m.name), ['Kullanıcı 1', 'Kullanıcı 2']);
    });

    test('kullanıcı ekle → Kullanıcı 3, farklı renk', () {
      final store = RackStore();
      final m = store.addMember()!;
      expect(m.name, 'Kullanıcı 3');
      expect(store.members.where((x) => x.color.value == m.color.value).length, 1);
    });

    test('kullanıcı silinince atamaları boşalır, son kullanıcı silinmez', () {
      final store = RackStore();
      final c = store.projects.addCard('Cupplast', ['Elektrik Projesi'],
          assignedTo: 'friend');
      expect(store.removeMember('friend'), isTrue);
      expect(c.assignedTo, isNull);
      expect(store.removeMember('me'), isFalse);
      expect(store.members.length, 1);
    });

    test('asistan "Kullanıcı 1" ile "Kullanıcı 12"yi karıştırmaz', () {
      final store = RackStore();
      while (store.members.length < 12) {
        store.addMember();
      }
      final u12 = store.members.firstWhere((m) => m.name == 'Kullanıcı 12');
      store.projects
          .addCard('Demir Lojistik', ['Mimari Proje'], assignedTo: u12.id);
      store.projects.addCard('Atilla', ['Mimari Proje'], assignedTo: 'me');
      final bot = RackAssistant(store);
      final a = bot.answer('Kullanıcı 12 kalan işler');
      expect(a, contains('Demir'));
      expect(a, isNot(contains('Atilla')));
      final b = bot.answer('kullanıcı 1 kalan');
      expect(b, contains('Atilla'));
      expect(b, isNot(contains('Demir')));
    });
  });

  group('Not askılığı', () {
    test('madde yok, nota tik → tamamlanır, geri alınır', () {
      final store = RackStore();
      final notes = store.addBoard('Notlar', ['yok sayılır'], kind: BoardKind.notes);
      expect(notes.isNotes, isTrue);
      expect(notes.template, isEmpty);
      final n = notes.addCard('Tabela ölçüsünü sor', const []);
      expect(n.items, isEmpty);
      expect(notes.toggleNote(n), isTrue);
      expect(notes.active, isEmpty);
      expect(notes.completed.single.name, 'Tabela ölçüsünü sor');
      notes.reopen(n);
      expect(notes.active.single, n);
    });

    test('özel kalır ve türüyle geri yüklenir', () async {
      final a = RackStore();
      final notes = a.addBoard('Notlar', const [], kind: BoardKind.notes);
      notes.addCard('ÖZEL NOT', const []);
      expect(jsonEncode(a.sharedJson()), isNot(contains('ÖZEL NOT')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final b = RackStore();
      await b.load();
      expect(b.custom.single.isNotes, isTrue);
      expect(b.custom.single.cards.single.name, 'ÖZEL NOT');
    });
  });

  group('Projeler maddelerini düzenleme', () {
    test('ekle + yeniden adlandır: kartlar güncellenir, tik korunur, grupla paylaşılır', () {
      final store = RackStore();
      final c = store.addCard('Atilla Tekstil', ['Mimari Proje', 'Elektrik Projesi']);
      store.toggleItem(c, c.items[1]); // elektrik tiklendi
      final tpl = store.projects.template
          .map((e) => e == 'Elektrik Projesi' ? 'Elektrik Tesisat Projesi' : e)
          .toList()
        ..add('Doğalgaz Projesi');
      store.updateBoard(store.projects,
          template: tpl, renames: {'Elektrik Projesi': 'Elektrik Tesisat Projesi'});

      expect(store.projects.name, 'Projeler');
      expect(c.items[1].type, 'Elektrik Tesisat Projesi');
      expect(c.items[1].done, isTrue);
      final shared = store.sharedJson();
      expect(shared['projectTypes'], contains('Doğalgaz Projesi'));
      expect(shared['projectTypes'], isNot(contains('Elektrik Projesi')));
    });

    test('asistan eklenen ve yeniden adlandırılan türleri anlar', () {
      final store = RackStore();
      store.updateBoard(store.projects,
          template: [...store.projects.template, 'Doğalgaz Projesi']);
      store.addCard('Demir Lojistik', ['Doğalgaz Projesi']);
      store.addCard('Cupplast', ['Elektrik Projesi']);
      final bot = RackAssistant(store);
      final a = bot.answer('doğalgazı kalan firmalar');
      expect(a, contains('Demir'));
      expect(a, isNot(contains('Cupplast')));

      final tpl = store.projects.template
          .map((e) => e == 'Elektrik Projesi' ? 'Elektrik Tesisat Projesi' : e)
          .toList();
      store.updateBoard(store.projects,
          template: tpl, renames: {'Elektrik Projesi': 'Elektrik Tesisat Projesi'});
      final b = bot.answer('hangi firmaların elektriği kaldı');
      expect(b, contains('Cupplast'));
      expect(b, isNot(contains('Demir')));
    });

    test('düzenlenen türler kayıttan geri gelir', () async {
      final a = RackStore();
      a.updateBoard(a.projects, template: ['Mimari Proje', 'Statik Proje']);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final b = RackStore();
      await b.load();
      expect(b.projects.template, ['Mimari Proje', 'Statik Proje']);
    });
  });

  group('Sekme sırası', () {
    test('sürükle-bırak sırası uygulanır ve kayıttan geri gelir', () async {
      final a = RackStore();
      final reels = a.addBoard('Reels', ['Instagram']);
      final notes = a.addBoard('Notlar', const [], kind: BoardKind.notes);
      expect(a.boards.map((b) => b.name), ['Projeler', 'Reels', 'Notlar']);

      a.reorderBoards(2, 0); // Notlar en başa
      expect(a.boards.map((b) => b.name), ['Notlar', 'Projeler', 'Reels']);
      a.reorderBoards(1, 3); // Projeler en sona
      expect(a.boards.map((b) => b.name), ['Notlar', 'Reels', 'Projeler']);

      // sonradan eklenen sona gelir
      a.addBoard('Fikirler', ['A']);
      expect(a.boards.last.name, 'Fikirler');

      await Future<void>.delayed(const Duration(milliseconds: 50));
      final b = RackStore();
      await b.load();
      expect(b.boards.map((x) => x.name), ['Notlar', 'Reels', 'Projeler', 'Fikirler']);
      expect(reels.id, isNotEmpty);
      expect(notes.id, isNotEmpty);
    });
  });

  group('Askılık paylaşma', () {
    Map<String, dynamic> sharedDoc(RackStore owner, Board b,
        {String permission = 'edit', bool allowCopy = true}) => {
          ...b.sharePayload(),
          'permission': permission,
          'allowCopy': allowCopy,
          'ownerName': owner.me.name,
          'code': 'K7P2QX9M',
        };

    test('kod üretimi ve normalize', () {
      final c = RackStore.newShareCode();
      expect(c.length, 8);
      expect(RegExp(r'^[A-HJ-NP-Z2-9]{8}$').hasMatch(c), isTrue);
      expect(RackStore.normalizeCode(' k7p2-qx9m '), 'K7P2QX9M');
    });

    test('izle (sadece inceleme): değiştirilemez, kaydedilmez', () {
      final owner = RackStore();
      final reels = owner.addBoard('Reels', ['Instagram']);
      reels.addCard('Video 1', reels.template);

      final guest = RackStore();
      final b = guest.joinShared(sharedDoc(owner, reels, permission: 'view'));
      expect(b.isShared, isTrue);
      expect(b.role, ShareRole.viewer);
      expect(b.canEdit, isFalse);
      expect(b.isPrivate, isFalse);
      expect(b.cards.single.name, 'Video 1');
      // aynı koda tekrar katılınca yeni askılık açılmaz
      expect(guest.joinShared(sharedDoc(owner, reels, permission: 'view')), same(b));
      expect(guest.custom.length, 1);
    });

    test('birlikte düzenle rolü', () {
      final owner = RackStore();
      final notes = owner.addBoard('Notlar', const [], kind: BoardKind.notes);
      notes.addCard('Tabela', const []);
      final guest = RackStore();
      final b = guest.joinShared(sharedDoc(owner, notes));
      expect(b.role, ShareRole.editor);
      expect(b.canEdit, isTrue);
      expect(b.isNotes, isTrue);
    });

    test('kopya bağımsızdır', () {
      final owner = RackStore();
      final reels = owner.addBoard('Reels', ['Instagram', 'YouTube']);
      final c = reels.addCard('Video 1', reels.template);
      reels.toggleItem(c, c.items[0]);

      final guest = RackStore();
      final copy = guest.copyShared(sharedDoc(owner, reels));
      expect(copy.isShared, isFalse);
      expect(copy.isPrivate, isTrue);
      expect(copy.id, isNot(reels.id));
      expect(copy.cards.single.items[0].done, isTrue); // durum kopyalanır
      copy.addCard('Video 2', copy.template);
      expect(reels.cards.length, 1); // asıl etkilenmez
    });

    test('paylaşım bilgisi kayıttan geri gelir, grup verisine karışmaz', () async {
      // Paylaşan taraf başka telefonda: aynı sahte hafızaya yazmasın diye
      // store'a bağlı olmayan bir askılıkla temsil ediliyor.
      final owner = RackStore();
      final reels = Board.custom('GİZLİ Reels', ['Instagram']);
      final guest = RackStore();
      guest.joinShared(sharedDoc(owner, reels, permission: 'view', allowCopy: false));
      expect(jsonEncode(guest.sharedJson()), isNot(contains('GİZLİ')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final again = RackStore();
      await again.load();
      final b = again.custom.single;
      expect(b.shareCode, 'K7P2QX9M');
      expect(b.shareCodePretty, 'K7P2-QX9M');
      expect(b.role, ShareRole.viewer);
      expect(b.allowCopy, isFalse);
    });
  });

  group('Projeler isteğe bağlı', () {
    test('ad değişir, grupla paylaşılır ve kayıttan geri gelir', () async {
      final a = RackStore();
      a.updateBoard(a.projects, name: 'İşler');
      expect(a.sharedJson()['projectsName'], 'İşler');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final b = RackStore();
      await b.load();
      expect(b.projects.name, 'İşler');
    });

    test('gizliyken kalıcıdır, sohbet bilgi verir', () async {
      final a = RackStore();
      await a.hideProjects();
      a.addBoard('Alışveriş', const [], kind: BoardKind.notes);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final b = RackStore();
      await b.load();
      expect(b.projectsHidden, isTrue);
      expect(b.boards.map((x) => x.name), ['Alışveriş']);
      expect(RackAssistant(b).answer('hangi projeler kaldı'), contains('Ekip projeleri'));
    });
  });

  group('Profil ve arkadaşlar', () {
    test('profil oluşturulur ve kayıttan geri gelir', () async {
      final a = RackStore();
      await a.load();
      expect(a.profile.id, isNotEmpty);
      expect(a.hasProfile, isFalse);
      await a.updateProfile(name: ' Emirhan ', emoji: '🦊');
      final b = RackStore();
      await b.load();
      expect(b.profile.id, a.profile.id);
      expect(b.profile.name, 'Emirhan');
      expect(b.profile.badge, '🦊');
    });

    test('paylaşılan askılıktaki kişiler arkadaş olur, ortak askılık görünür', () {
      final guest = RackStore()
        ..profile = const Member(id: 'p-guest', name: 'Ben', color: Color(0xFF2E7DE0));
      final reels = Board.custom('Reels', ['Instagram']);
      final b = guest.joinShared({
        ...reels.sharePayload(),
        'permission': 'edit',
        'allowCopy': true,
        'code': 'K7P2QX9M',
        'members': {
          'p-ayse': {'name': 'Ayşe', 'color': 0xFFE02E7D, 'emoji': '🌻', 'role': 'owner'},
        },
      });
      expect(guest.friends['p-ayse']!.name, 'Ayşe');
      expect(guest.boardsWith('p-ayse'), [b]);
      expect(b.people, {'p-ayse': 'owner', 'p-guest': 'editor'});

      // sonradan biri daha katıldı → snapshot ile gelir
      guest.applySharedSnapshot(b, {
        ...b.sharePayload(),
        'permission': 'edit',
        'members': {
          'p-ayse': {'name': 'Ayşe', 'color': 0xFFE02E7D, 'emoji': '🌻', 'role': 'owner'},
          'p-guest': {'name': 'Ben', 'color': 0xFF2E7DE0, 'role': 'editor'},
          'p-mert': {'name': 'Mert', 'color': 0xFF14A3A3, 'role': 'viewer'},
        },
        'updatedBy': 'baska-cihaz',
      });
      expect(guest.friends.keys.toSet(), {'p-ayse', 'p-mert'}); // kendim yokum
      expect(b.people['p-mert'], 'viewer');
      expect(guest.memberById('p-mert')!.name, 'Mert');
    });

    test('paylaşılan askılıkta tik profil kimliğiyle atılır', () {
      final guest = RackStore()
        ..profile = const Member(id: 'p-guest', name: 'Ben', color: Color(0xFF9B4DE0));
      final reels = Board.custom('Reels', ['Instagram']);
      reels.cards.add(CompanyCard(
          id: 'c1', name: 'Video', items: [ProjectItem(type: 'Instagram')]));
      final b = guest.joinShared({
        ...reels.sharePayload(),
        'permission': 'edit',
        'code': 'ABCD2345',
      });
      final c = b.cards.single;
      b.toggleItem(c, c.items.single);
      expect(c.items.single.doneBy, 'p-guest');
      expect(guest.memberById('p-guest')!.color, const Color(0xFF9B4DE0));
    });
  });

  group('Sahiplik, geri alınabilir silme, geçmiş', () {
    Board ownedShared(RackStore s) {
      final b = s.addBoard('Reels', ['Instagram']);
      b.shareCode = 'K7P2QX9M';
      b.role = ShareRole.owner;
      return b;
    }

    test('paylaşılmayan askılıkta silme kalıcıdır, geçmiş yazılmaz', () {
      final s = RackStore();
      final c = s.addCard('Atilla', ['Mimari Proje']);
      s.projects.deleteCard(c);
      expect(s.projects.cards, isEmpty);
      expect(s.activities, isEmpty);
    });

    test('ortak askılıkta silinen kart gizlenir ve sahip geri yükler', () {
      final s = RackStore()
        ..profile = const Member(id: 'p-me', name: 'Emirhan', color: Color(0xFF2E7DE0));
      final b = ownedShared(s);
      final c = b.addCard('Video 1', b.template);
      b.deleteCard(c);
      expect(b.cards, contains(c)); // veride duruyor
      expect(b.active, isEmpty); // ama ipte yok
      final del = s.activities.firstWhere((a) => a.action == 'delete');
      expect(del.text, 'Video 1 silindi');
      expect(del.byName, 'Emirhan');
      final r = s.restorable(del)!;
      expect(r.card, same(c));
      expect(r.board.restoreCard(r.card), isTrue);
      expect(b.active.single.name, 'Video 1');
      expect(s.activities.any((a) => a.action == 'restore'), isTrue);
      expect(s.restorable(del), isNull); // artık geri yüklenecek bir şey yok
    });

    test('düzenleyici askılık ayarlarını değiştiremez, silineni geri yükleyemez', () {
      final guest = RackStore()
        ..profile = const Member(id: 'p-guest', name: 'Mert', color: Color(0xFF14A3A3));
      final src = Board.custom('Reels', ['Instagram']);
      final b = guest.joinShared({
        ...src.sharePayload(),
        'permission': 'edit',
        'code': 'ABCD2345',
        'members': {'p-owner': {'name': 'Emirhan', 'role': 'owner', 'color': 0xFF2E7DE0}},
      });
      expect(b.canEdit, isTrue);
      expect(b.canManage, isFalse);
      guest.updateBoard(b, name: 'Benim artık', template: ['TikTok']);
      expect(b.name, 'Reels');
      expect(b.template, ['Instagram']);

      final c = b.addCard('Video', b.template);
      b.deleteCard(c);
      expect(b.active, isEmpty);
      final del = guest.activities.firstWhere((a) => a.action == 'delete');
      expect(guest.restorable(del), isNull);
      expect(b.restoreCard(c), isFalse);
      expect(b.purgeCard(c), isFalse);
    });

    test('işlem metinleri ve diğer kullanıcı rozeti', () {
      final s = RackStore()
        ..profile = const Member(id: 'p-me', name: 'Emirhan', color: Color(0xFF2E7DE0));
      final b = ownedShared(s);
      final c = b.addCard('Atilla Tekstil', ['Elektrik Projesi']);
      b.toggleItem(c, c.items.single);
      expect(s.activities.firstWhere((a) => a.action == 'tick').text,
          'Atilla Tekstil · Elektrik tiklendi');
      expect(s.unseenActivities, 0); // kendi işlemlerim sayılmaz

      // diğer telefondan gelen geçmiş
      s.applySharedSnapshot(b, {
        ...b.sharePayload(),
        'updatedBy': 'baska',
        'members': {'p-ayse': {'name': 'Ayşe', 'role': 'editor', 'color': 0xFFE02E7D}},
        'log': [
          ...b.log.map((e) => e.toJson()),
          Activity(
            id: 'x1', at: DateTime.now(), by: 'p-ayse', byName: 'Ayşe',
            byColor: 0xFFE02E7D, boardId: b.id, boardName: 'Reels',
            action: 'complete', cardId: c.id, card: 'Atilla Tekstil',
          ).toJson(),
        ],
      });
      expect(s.activities.firstWhere((a) => a.by == 'p-ayse').text,
          'Atilla Tekstil tamamlandı 🎉');
      expect(s.unseenActivities, 1);
      s.markHistorySeen();
      expect(s.unseenActivities, 0);
    });
  });

  group('Yeni kurulum ve Projeler paylaşımı', () {
    Map<String, dynamic> projectsDoc({String perm = 'edit', String owner = 'p-owner'}) => {
          'kind': 'projects',
          'code': 'K7P2QX9M',
          '_doc': 'share_k7p2qx9m',
          'owner': owner,
          'ownerName': 'Emirhan',
          'permission': perm,
          'allowCopy': true,
          'projectsName': 'Fourmis Projeler',
          'projectTypes': ['Mimari Proje', 'Elektrik Projesi'],
          'members': [
            {'id': 'me', 'name': 'Kullanıcı 1', 'color': 0xFF2E7DE0},
            {'id': 'friend', 'name': 'Kullanıcı 2', 'color': 0xFF2EA35A},
          ],
          'cards': [
            {
              'id': 'c1', 'name': 'Atilla Tekstil', 'createdAt': '2026-10-31T10:00:00.000',
              'items': [
                {'type': 'Mimari Proje', 'done': true, 'doneBy': 'me'},
                {'type': 'Elektrik Projesi', 'done': false},
              ],
            },
          ],
          'people': {
            'p-owner': {'name': 'Emirhan', 'color': 0xFF8B6A3E, 'role': 'owner'},
          },
        };

    test('yeni kurulumda Projeler yok, Mesaj/ekip seçeneği yok', () async {
      final s = RackStore();
      await s.load();
      expect(s.projectsHidden, isTrue);
      expect(s.projectsEverUsed, isFalse);
      expect(s.boards, isEmpty);
    });

    test('eski kullanıcıda Projeler olduğu gibi kalır', () async {
      SharedPreferences.setMockInitialValues({'cards_v1': '[]', 'rack_code_v1': 'fourmis-proje'});
      final s = RackStore();
      await s.load();
      expect(s.projectsHidden, isFalse);
      expect(s.projectsEverUsed, isTrue);
      // eski kod: kod olarak görünür, sahipsizken herkes yönetebilir
      expect(s.projects.isShared, isTrue);
      expect(s.projects.shareCodePretty, 'fourmis-proje');
      expect(s.projects.role, isNull);
    });

    test('paylaşım belgesi Projeler olarak tanınır (eski kod dahil)', () {
      expect(RackStore.isProjectsData(projectsDoc()), isTrue);
      expect(RackStore.isProjectsData({'projectTypes': [], 'cards': []}), isTrue);
      expect(RackStore.isProjectsData({'kind': 'notes'}), isFalse);
    });

    test('kodla Projeler\'e katılma: düzenleyici', () async {
      final s = RackStore()
        ..profile = const Member(id: 'p-guest', name: 'Mert', color: Color(0xFF14A3A3));
      await s.hideProjects(); // yeni kullanıcı gibi
      final b = s.joinShared(projectsDoc()); // dispatch → joinProjects
      expect(b, same(s.projects));
      expect(s.projectsHidden, isFalse);
      expect(s.rackCode, 'share_k7p2qx9m');
      expect(s.projects.name, 'Fourmis Projeler');
      expect(s.projects.live.single.name, 'Atilla Tekstil');
      expect(s.projects.role, ShareRole.editor);
      expect(s.projects.canEdit, isTrue);
      expect(s.projects.canManage, isFalse); // sahip değil
      expect(s.friends['p-owner']!.name, 'Emirhan');
      expect(s.projects.people['p-guest'], 'editor');
      // sahip olmayan proje türlerini / ekibi değiştiremez
      s.updateBoard(s.projects, name: 'Benim', template: ['X']);
      expect(s.projects.name, 'Fourmis Projeler');
      expect(s.addMember(), isNull);
    });

    test('sadece inceleme izniyle Projeler kilitli', () async {
      final s = RackStore()
        ..profile = const Member(id: 'p-guest', name: 'Mert', color: Color(0xFF14A3A3));
      s.joinProjects(projectsDoc(perm: 'view'));
      expect(s.projects.role, ShareRole.viewer);
      expect(s.projects.canEdit, isFalse);
    });

    test('ayrılınca bu telefondan temizlenir', () async {
      final s = RackStore()
        ..profile = const Member(id: 'p-guest', name: 'Mert', color: Color(0xFF14A3A3));
      s.joinProjects(projectsDoc());
      await s.deleteBoard(s.projects); // alıcı → ayrıl
      expect(s.rackCode, isEmpty);
      expect(s.projectsHidden, isTrue);
      expect(s.projects.cards, isEmpty);
      expect(s.projects.isShared, isFalse);
    });

    test('Projeler kopyası bağımsız maddeli askılık olur', () {
      final s = RackStore();
      final c = s.copyShared(projectsDoc());
      expect(c.isProjects, isFalse);
      expect(c.isNotes, isFalse);
      expect(c.name, 'Fourmis Projeler');
      expect(c.template, ['Mimari Proje', 'Elektrik Projesi']);
      expect(c.cards.single.items.first.done, isTrue);
      expect(s.projects.cards, isEmpty); // kendi Projeler'ine dokunulmaz
    });
  });

  test('Bitenler rozeti bakınca sıfırlanır', () async {
    final s = RackStore();
    await s.load();
    final b = s.addBoard('Yapılacaklar', const [], kind: BoardKind.notes);
    final n = b.addCard('Gözlük çizimi', const []);
    expect(s.unseenCompleted, 0);
    b.toggleNote(n);
    expect(s.unseenCompleted, 1);
    s.markDoneSeen();
    expect(s.unseenCompleted, 0);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final again = RackStore();
    await again.load();
    expect(again.unseenCompleted, 0); // bakıldığı kayıtlı
  });
}
