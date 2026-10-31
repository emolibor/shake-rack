import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/store.dart';
import '../services/updater.dart';
import '../widgets/people.dart';

/// Ekip ayarları: kim kullanıyor (aktif kişi), isimler ve renkler.
class TeamScreen extends StatelessWidget {
  final RackStore store;
  const TeamScreen({super.key, required this.store});

  static const _palette = kMemberPalette;

  Future<void> _edit(BuildContext context, String id) async {
    final m = store.memberById(id)!;
    final ctrl = TextEditingController(text: m.name);
    Color picked = m.color;
    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setS) => AlertDialog(
          title: const Text('Kullanıcıyı düzenle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: ctrl,
                  decoration: const InputDecoration(labelText: 'İsim')),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _palette
                    .map((c) => GestureDetector(
                          onTap: () => setS(() => picked = c),
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: picked == c ? Colors.black : Colors.transparent,
                                  width: 3),
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ],
          ),
          actions: [
            if (store.members.length > 1)
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: Text('${m.name} silinsin mi?'),
                      content: const Text(
                          'Atandığı kartlar "atama yok" olur. Attığı tikler kalır ama gri görünür.'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Vazgeç')),
                        FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Sil')),
                      ],
                    ),
                  );
                  if (ok == true && context.mounted) {
                    store.removeMember(id);
                    Navigator.pop(context);
                  }
                },
                child: const Text('Sil'),
              ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
            FilledButton(
                onPressed: () {
                  store.updateMember(id, name: ctrl.text.trim(), color: picked);
                  Navigator.pop(context);
                },
                child: const Text('Kaydet')),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _ProfileCard(store: store),
          const SizedBox(height: 18),
          _section('Arkadaşlarım', Icons.people_alt_outlined),
          _FriendsList(store: store),
          if (!store.projectsHidden) ...[
          const SizedBox(height: 22),
          _section('Proje ekibi (${store.projects.name})', Icons.groups_outlined),
          _OwnerRow(store: store),
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Text(
                'Bu telefonu kim kullanıyor? Proje kartlarında tik attığında seçili kullanıcının rengi basılır. '
                'İsim ve rengi değiştirmek için renkli daireye dokun.',
                style: TextStyle(color: Colors.black54, fontSize: 13)),
          ),
          ...store.members.map((m) => Card(
                child: RadioListTile<String>(
                  value: m.id,
                  groupValue: store.currentMemberId,
                  onChanged: (v) => store.setCurrentMember(v!),
                  title: Text(m.name),
                  secondary: IconButton(
                    icon: CircleAvatar(backgroundColor: m.color, radius: 14,
                        child: Icon(
                            store.canManageProjects ? Icons.edit : Icons.lock_outline,
                            size: 14, color: Colors.white)),
                    onPressed: store.canManageProjects ? () => _edit(context, m.id) : null,
                  ),
                ),
              )),
          const SizedBox(height: 4),
          if (store.canManageProjects)
          OutlinedButton.icon(
            onPressed: () {
              final m = store.addMember();
              if (m == null) return;
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${m.name} eklendi')));
            },
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Kullanıcı ekle'),
          ),
          ],
          const SizedBox(height: 22),
          const Divider(),
          const _VersionCard(),
        ],
      ),
    );
  }
}

/// Yüklü sürüm + elle güncelleme kontrolü.
class _VersionCard extends StatefulWidget {
  const _VersionCard();
  @override
  State<_VersionCard> createState() => _VersionCardState();
}

class _VersionCardState extends State<_VersionCard> {
  String _version = '…';
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    Updater.currentVersion().then((v) {
      if (mounted) setState(() => _version = v);
    });
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    final info = await Updater.check();
    if (!mounted) return;
    setState(() => _checking = false);
    if (info == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('En güncel sürümü kullanıyorsun ✓')));
    } else {
      await showUpdateDialog(context, info);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.system_update_alt),
        title: const Text('Güncellemeleri denetle'),
        subtitle: Text('Yüklü sürüm: $_version'),
        trailing: _checking
            ? const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.chevron_right),
        onTap: _checking ? null : _check,
      ),
    );
  }
}

Widget _section(String title, IconData icon) => Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF6B4F2A)),
          const SizedBox(width: 6),
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF6B4F2A))),
        ],
      ),
    );

/// Kendi profilim.
class _ProfileCard extends StatelessWidget {
  final RackStore store;
  const _ProfileCard({required this.store});

  @override
  Widget build(BuildContext context) {
    final p = store.profile;
    return Card(
      color: const Color(0xFFFFF8E7),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showProfileEditor(context, store),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              PersonAvatar(person: p, size: 58),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(store.hasProfile ? p.name : 'Profilini oluştur',
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      store.hasProfile
                          ? '${store.friends.length} arkadaş · ${store.custom.where((b) => b.isShared).length} paylaşılan askılık'
                          : 'Askılık paylaştığında arkadaşların seni bu adla görür.',
                      style: const TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.edit_outlined, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }
}

/// Arkadaş listesi (askılık paylaşınca / katılınca oluşur).
class _FriendsList extends StatelessWidget {
  final RackStore store;
  const _FriendsList({required this.store});

  @override
  Widget build(BuildContext context) {
    final list = store.friends.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (list.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Henüz arkadaşın yok. Bir askılığını paylaştığında ya da birinin '
            'askılığına katıldığında burada görünür; sonra onunla doğrudan ortak askılık açabilirsin.',
            style: TextStyle(color: Colors.black54, height: 1.35),
          ),
        ),
      );
    }
    return Card(
      child: Column(
        children: [
          for (final f in list)
            ListTile(
              leading: PersonAvatar(person: f, size: 40),
              title: Text(f.name.isEmpty ? 'İsimsiz' : f.name),
              subtitle: Text(() {
                final n = store.boardsWith(f.id).length;
                return n == 0 ? 'Ortak askılık yok' : '$n ortak askılık';
              }()),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showFriendSheet(context, store, f),
            ),
        ],
      ),
    );
  }
}

/// Proje kodunun sahibi: göster ya da (sahipsizse) sahiplen.
class _OwnerRow extends StatelessWidget {
  final RackStore store;
  const _OwnerRow({required this.store});

  @override
  Widget build(BuildContext context) {
    if (store.rackCode.isEmpty) return const SizedBox.shrink();
    final owner = store.projectsOwner;
    final mine = owner == store.profile.id;
    return Card(
      color: mine ? const Color(0xFFE2F3E5) : const Color(0xFFFFF8E7),
      child: ListTile(
        leading: Icon(owner == null
            ? Icons.shield_outlined
            : mine
                ? Icons.verified_user
                : Icons.lock_outline),
        title: Text(owner == null
            ? 'Bu askılığın sahibi yok'
            : mine
                ? 'Askılığın sahibi sensin'
                : 'Sahibi: ${store.projectsOwnerName}'),
        subtitle: Text(owner == null
            ? 'Şu an koda bağlı herkes her şeyi değiştirebilir. Sahiplenince adı, proje türlerini '
                've kullanıcıları sadece sen değiştirirsin; silinen firmaları geri yüklersin.'
            : mine
                ? 'Diğerleri tik atar, firma ekler; askılığın ayarlarını sadece sen değiştirirsin.'
                : 'Tik atabilir, firma ekleyip düzenleyebilirsin; ayarları sadece sahip değiştirir.'),
        isThreeLine: true,
        trailing: owner == null
            ? FilledButton(
                onPressed: () async {
                  if (!await ensureProfile(context, store)) return;
                  final ok = await store.claimProjects();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(ok
                            ? 'Artık askılığın sahibi sensin 🔒'
                            : 'Başka biri az önce sahiplendi.')));
                  }
                },
                child: const Text('Sahibi benim'),
              )
            : null,
      ),
    );
  }
}
