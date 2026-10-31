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
      final m = store.addMember();
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
}
