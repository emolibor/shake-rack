import 'package:flutter/material.dart';
import '../services/store.dart';

/// Ekip ayarları: kim kullanıyor (aktif kişi), isimler ve renkler.
class TeamScreen extends StatelessWidget {
  final RackStore store;
  const TeamScreen({super.key, required this.store});

  static const _palette = [
    Color(0xFF2E7DE0), Color(0xFF2EA35A), Color(0xFFE0652E), Color(0xFF9B4DE0),
    Color(0xFFE02E7D), Color(0xFF14A3A3), Color(0xFFC9A200), Color(0xFF555555),
  ];

  Future<void> _edit(BuildContext context, String id) async {
    final m = store.memberById(id)!;
    final ctrl = TextEditingController(text: m.name);
    Color picked = m.color;
    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setS) => AlertDialog(
          title: const Text('Kişiyi düzenle'),
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
            child: Text('Bu telefonu kim kullanıyor? Tik attığında senin rengin basılır.',
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
          const SizedBox(height: 24),
          const Divider(),
          _SyncCard(store: store),
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
