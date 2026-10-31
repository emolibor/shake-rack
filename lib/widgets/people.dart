import 'package:flutter/material.dart';
import '../models/models.dart';
import '../screens/board_edit_screen.dart';
import '../services/board.dart';
import '../services/store.dart';

const kProfileEmojis = [
  '🙂', '😎', '🦊', '🐻', '🐼', '🦁', '🐯', '🐸',
  '🌻', '🌵', '🍀', '🔥', '⭐', '🎯', '🎨', '📐',
  '🏗️', '🧱', '☕', '🎧', '📚', '🚲', '⚽', '🎸',
];

/// Renkli daire içinde emoji ya da baş harf.
class PersonAvatar extends StatelessWidget {
  final Member person;
  final double size;
  final bool ring;
  const PersonAvatar({super.key, required this.person, this.size = 32, this.ring = false});

  @override
  Widget build(BuildContext context) {
    final hasEmoji = person.emoji.isNotEmpty;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: hasEmoji ? Color.lerp(Colors.white, person.color, 0.25) : person.color,
        shape: BoxShape.circle,
        border: Border.all(
            color: ring ? Colors.white : person.color, width: ring ? 2 : 1.5),
      ),
      child: Text(
        person.badge,
        style: TextStyle(
          fontSize: size * (hasEmoji ? 0.52 : 0.45),
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1.1,
        ),
      ),
    );
  }
}

/// Üst üste binen küçük avatarlar (paylaşılan askılıktaki kişiler).
class AvatarStack extends StatelessWidget {
  final List<Member> people;
  final double size;
  final int max;
  const AvatarStack({super.key, required this.people, this.size = 22, this.max = 4});

  @override
  Widget build(BuildContext context) {
    final shown = people.take(max).toList();
    final extra = people.length - shown.length;
    final step = size * 0.68;
    final width = shown.isEmpty ? 0.0 : size + step * (shown.length - 1) + (extra > 0 ? step : 0);
    return SizedBox(
      width: width,
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * step,
              child: PersonAvatar(person: shown[i], size: size, ring: true),
            ),
          if (extra > 0)
            Positioned(
              left: shown.length * step,
              child: Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.brown.shade300,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Text('+$extra',
                    style: TextStyle(
                        fontSize: size * 0.4, color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Profil düzenleyici (isim, emoji, renk).
Future<void> showProfileEditor(BuildContext context, RackStore store,
    {String? reason}) async {
  final ctrl = TextEditingController(text: store.profile.name);
  var emoji = store.profile.emoji;
  var color = store.profile.color;
  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('Profilin'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (reason != null) ...[
                Text(reason, style: const TextStyle(color: Colors.black54, fontSize: 13)),
                const SizedBox(height: 12),
              ],
              Center(
                child: PersonAvatar(
                  person: Member(id: '', name: ctrl.text, color: color, emoji: emoji),
                  size: 64,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: store.profile.name.isEmpty,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setS(() {}),
                decoration: const InputDecoration(
                  labelText: 'Adın (arkadaşların bunu görür)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final e in kProfileEmojis)
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setS(() => emoji = e),
                      child: Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: e == emoji ? const Color(0xFFFFF0D0) : null,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: e == emoji ? const Color(0xFF8B6A3E) : Colors.transparent),
                        ),
                        child: Text(e, style: const TextStyle(fontSize: 20)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in kMemberPalette)
                    GestureDetector(
                      onTap: () => setS(() => color = c),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: c == color ? Colors.black : Colors.transparent, width: 3),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: ctrl.text.trim().isEmpty
                ? null
                : () async {
                    Navigator.pop(ctx);
                    await store.updateProfile(name: ctrl.text, emoji: emoji, color: color);
                  },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    ),
  );
  ctrl.dispose();
}

/// Paylaşma / katılma öncesi: profil yoksa oluşturmasını iste.
Future<bool> ensureProfile(BuildContext context, RackStore store) async {
  if (store.hasProfile) return true;
  await showProfileEditor(context, store,
      reason: 'Paylaştığın ya da katıldığın askılıklarda arkadaşların seni bu adla görecek.');
  return store.hasProfile;
}

/// Arkadaş kartı: profil, ortak askılıklar, yeni ortak askılık.
Future<void> showFriendSheet(BuildContext context, RackStore store, Member friend) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => AnimatedBuilder(
      animation: store,
      builder: (ctx, _) {
        final f = store.friends[friend.id] ?? friend;
        final shared = store.boardsWith(f.id);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: PersonAvatar(person: f, size: 72)),
                const SizedBox(height: 10),
                Text(f.name.isEmpty ? 'İsimsiz' : f.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  shared.isEmpty ? 'Ortak askılığınız yok' : '${shared.length} ortak askılık',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 14),
                for (final b in shared)
                  Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    color: const Color(0xFFFFF8E7),
                    child: ListTile(
                      dense: true,
                      leading: Icon(b.isNotes ? Icons.sticky_note_2_outlined : Icons.checkroom),
                      title: Text(b.name),
                      subtitle: Text(_roleText(b, f.id)),
                      trailing: Text('${b.active.length} açık',
                          style: const TextStyle(fontSize: 12, color: Colors.black54)),
                    ),
                  ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    if (!await ensureProfile(context, store)) return;
                    if (!context.mounted) return;
                    final b = await BoardEditScreen.create(context, store);
                    if (b == null || b.isProjects) return;
                    try {
                      await store.inviteFriend(b, f);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('"${b.name}" ${f.name} ile paylaşıldı 🤝')));
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('Gönderilemedi: $e')));
                      }
                    }
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Yeni ortak askılık'),
                ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: Colors.black54),
                  onPressed: () {
                    store.removeFriend(f.id);
                    Navigator.pop(ctx);
                  },
                  child: const Text('Arkadaş listemden çıkar'),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

String _roleText(Board b, String friendId) {
  final r = b.people[friendId];
  final mine = b.role == ShareRole.owner ? 'Sen paylaştın' : 'O paylaştı';
  if (r == 'owner') return 'O paylaştı';
  if (r == 'viewer') return '$mine · o sadece inceliyor';
  return '$mine · birlikte düzenliyorsunuz';
}

/// Paylaşılan askılıktaki herkes (kendin dahil).
List<Member> boardPeople(RackStore store, Board b, {bool includeMe = false}) {
  final out = <Member>[];
  b.people.forEach((id, _) {
    if (id == store.profile.id) {
      if (includeMe) out.add(store.profile);
      return;
    }
    out.add(store.friends[id] ?? Member(id: id, name: '', color: Colors.grey));
  });
  return out;
}

/// Askılıktaki kişiler listesi.
Future<void> showPeopleSheet(BuildContext context, RackStore store, Board b) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final people = boardPeople(store, b, includeMe: true);
      String role(String id) => switch (b.people[id]) {
            'owner' => 'Paylaşan',
            'viewer' => 'Sadece inceliyor',
            _ => 'Düzenleyebilir',
          };
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Text('${b.name} · ${people.length} kişi',
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            for (final p in people)
              ListTile(
                leading: PersonAvatar(person: p, size: 38),
                title: Text(p.id == store.profile.id
                    ? '${p.name.isEmpty ? 'Sen' : p.name} (sen)'
                    : (p.name.isEmpty ? 'İsimsiz' : p.name)),
                subtitle: Text(role(p.id)),
                onTap: p.id == store.profile.id
                    ? null
                    : () {
                        Navigator.pop(ctx);
                        showFriendSheet(context, store, p);
                      },
              ),
          ],
        ),
      );
    },
  );
}
