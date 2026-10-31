import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/store.dart';
import '../services/updater.dart';

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
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
                'Bu telefonu kim kullanıyor? Tik attığında seçili kullanıcının rengi basılır. '
                'İsim ve rengi değiştirmek için renkli daireye dokun.',
                style: TextStyle(color: Colors.black54)),
          ),
          ...store.members.map((m) => Card(
                child: RadioListTile<String>(
                  value: m.id,
                  groupValue: store.currentMemberId,
                  onChanged: (v) => store.setCurrentMember(v!),
                  title: Text(m.name),
                  secondary: IconButton(
                    icon: CircleAvatar(backgroundColor: m.color, radius: 14,
                        child: const Icon(Icons.edit, size: 14, color: Colors.white)),
                    onPressed: () => _edit(context, m.id),
                  ),
                ),
              )),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: () {
              final m = store.addMember();
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${m.name} eklendi')));
            },
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Kullanıcı ekle'),
          ),
          const SizedBox(height: 24),
          const Divider(),
          _SyncCard(store: store),
          const SizedBox(height: 8),
          const _VersionCard(),
        ],
      ),
    );
  }
}

/// Askılık kodu: iki telefon aynı kodu girince aynı ipi görür.
class _SyncCard extends StatefulWidget {
  final RackStore store;
  const _SyncCard({required this.store});
  @override
  State<_SyncCard> createState() => _SyncCardState();
}

class _SyncCardState extends State<_SyncCard> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.store.rackCode);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(s.syncing ? Icons.cloud_done_outlined : Icons.cloud_off_outlined),
                const SizedBox(width: 8),
                const Text('Ortak askılık',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                const Spacer(),
                Text(s.syncStatus,
                    style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'İkiniz de aynı kodu girin; kartlar, tikler ve sıra iki telefonda canlı eşitlenir.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            if (!s.firebaseReady)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Firebase kurulu değil — README\'deki "flutterfire configure" adımını yap.',
                  style: TextStyle(fontSize: 12, color: Colors.redAccent),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              enabled: s.firebaseReady,
              decoration: const InputDecoration(
                labelText: 'Askılık kodu',
                hintText: 'fourmis-proje',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: s.firebaseReady
                      ? () async {
                          await s.setRackCode(_ctrl.text);
                          _ctrl.text = s.rackCode;
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(s.rackCode.isEmpty
                                    ? 'Yerel moda geçildi'
                                    : '"${s.rackCode}" askılığına bağlanıldı')));
                          }
                        }
                      : null,
                  icon: const Icon(Icons.link),
                  label: const Text('Bağlan'),
                ),
                const SizedBox(width: 8),
                if (s.rackCode.isNotEmpty)
                  TextButton(
                    onPressed: () async {
                      await s.setRackCode('');
                      _ctrl.clear();
                    },
                    child: const Text('Ayrıl'),
                  ),
              ],
            ),
          ],
        ),
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
