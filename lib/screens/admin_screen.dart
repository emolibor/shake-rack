import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../models/models.dart';
import '../services/store.dart';
import '../widgets/people.dart';

/// Yönetim paneli (sadece yönetici):
/// - Onaylar: paylaşılan askılıklara katılma istekleri (her kişi ayrı onay)
/// - Kullanıcılar: uygulamayı kullananlar ve Projeler yetkileri
class AdminScreen extends StatelessWidget {
  final RackStore store;
  const AdminScreen({super.key, required this.store});

  static Future<void> open(BuildContext context, RackStore store) => Navigator.push(
      context, MaterialPageRoute(builder: (_) => AdminScreen(store: store)));

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) => DefaultTabController(
        length: 2,
        initialIndex: store.pendingRequests.isNotEmpty ? 0 : 1,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Yönetim paneli'),
            actions: [
              IconButton(
                tooltip: 'Projeler\'e davet et',
                icon: const Icon(Icons.person_add_alt_1),
                onPressed: () => showProjectsInvite(context, store),
              ),
            ],
            bottom: TabBar(tabs: [
              Tab(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Onaylar'),
                  if (store.pendingRequests.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Badge(label: Text('${store.pendingRequests.length}')),
                  ],
                ]),
              ),
              Tab(text: 'Kullanıcılar (${store.users.where((u) => u.uid != store.uid).length})'),
            ]),
          ),
          body: TabBarView(children: [
            _Requests(store: store),
            _Users(store: store),
          ]),
        ),
      ),
    );
  }
}

class _Requests extends StatelessWidget {
  final RackStore store;
  const _Requests({required this.store});

  @override
  Widget build(BuildContext context) {
    final list = store.pendingRequests;
    if (list.isEmpty) {
      return const _Empty(
        icon: Icons.verified_outlined,
        text: 'Bekleyen istek yok.\nBiri paylaşılan bir askılığa katılmak istediğinde '
            'burada onayına düşer. Askılıkların içeriğini görmezsin; sadece kimin, '
            'kimin askılığına katılmak istediğini görürsün.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final r in list)
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      PersonAvatar(person: r.requester, size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text.rich(TextSpan(children: [
                          TextSpan(
                              text: r.name.isEmpty ? 'İsimsiz' : r.name,
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          const TextSpan(text: ', '),
                          if (r.shareId == RackStore.projectsRequestId)
                            TextSpan(text: ' "${store.projects.name}" askılığına erişim istiyor.')
                          else ...[
                          TextSpan(
                              text: r.ownerName.isEmpty ? 'bir kullanıcının' : '${r.ownerName} adlı kişinin',
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          TextSpan(
                              text: r.boardName.isEmpty
                                  ? ' paylaştığı askılığa katılmak istiyor.'
                                  : ' "${r.boardName}" askılığına katılmak istiyor.'),
                          ],
                        ])),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (r.shareId == RackStore.projectsRequestId)
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 6,
                      children: [
                        TextButton(
                          style: TextButton.styleFrom(foregroundColor: Colors.red),
                          onPressed: () => store.decideProjectsRequest(r, 'none'),
                          child: const Text('Reddet'),
                        ),
                        OutlinedButton(
                          onPressed: () => store.decideProjectsRequest(r, 'view'),
                          child: const Text('Görür'),
                        ),
                        FilledButton(
                          onPressed: () => store.decideProjectsRequest(r, 'edit'),
                          child: const Text('Düzenler'),
                        ),
                      ],
                    )
                  else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                        onPressed: () => store.decideJoin(r, false),
                        child: const Text('Reddet'),
                      ),
                      const SizedBox(width: 6),
                      FilledButton.icon(
                        onPressed: () => store.decideJoin(r, true),
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Onayla'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Users extends StatelessWidget {
  final RackStore store;
  const _Users({required this.store});

  static const _labels = {'none': 'Yok', 'view': 'Görür', 'edit': 'Düzenler'};

  String _seen(DateTime? d) {
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 5) return 'şimdi aktif';
    if (diff.inHours < 1) return '${diff.inMinutes} dk önce';
    if (diff.inDays < 1) return '${diff.inHours} saat önce';
    return '${diff.inDays} gün önce';
  }

  @override
  Widget build(BuildContext context) {
    final list = store.users.where((u) => u.uid != store.uid).toList();
    if (list.isEmpty) {
      return const _Empty(
        icon: Icons.group_outlined,
        text: 'Henüz başka kullanıcı yok.\nUygulamayı indirip adını giren herkes burada görünür.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: FilledButton.icon(
            onPressed: () => showProjectsInvite(context, store),
            icon: const Icon(Icons.person_add_alt_1),
            label: Text('"${store.projects.name}" askılığına davet et'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text(
            '"${store.projects.name}" askılığına kimin erişeceğini seç. Yetkisi olmayan '
            'Projeler\'i hiç görmez. Kullanıcıların kendi askılıklarına erişimin yok.',
            style: const TextStyle(color: Colors.black54, fontSize: 13, height: 1.35),
          ),
        ),
        for (final u in list)
          Card(
            child: ListTile(
              leading: PersonAvatar(person: u.asMember, size: 40),
              title: Text(u.name.isEmpty ? 'İsimsiz' : u.name),
              subtitle: Text(_seen(u.lastSeen)),
              trailing: DropdownButton<String>(
                value: _labels.containsKey(u.projectsAccess) ? u.projectsAccess : 'none',
                underline: const SizedBox.shrink(),
                items: [
                  for (final e in _labels.entries)
                    DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: e.key == 'none'
                                  ? Colors.black45
                                  : e.key == 'edit'
                                      ? const Color(0xFF2E7D32)
                                      : const Color(0xFF2E6BB8))),
                    ),
                ],
                onChanged: (v) async {
                  if (v == null || v == u.projectsAccess) return;
                  try {
                    await store.setProjectsAccess(u, v);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(v == 'none'
                              ? '${u.name}: Projeler erişimi kaldırıldı'
                              : '${u.name}: Projeler\'i ${v == 'edit' ? 'düzenleyebilir' : 'görebilir'}')));
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
                    }
                  }
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Empty({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: const Color(0xFFB59B74)),
            const SizedBox(height: 10),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54, height: 1.4)),
          ]),
        ),
      );
}

/// Projeler'e davet: uygulama indirme + erişim isteği bağlantısı.
Future<void> showProjectsInvite(BuildContext context, RackStore store) {
  final link = store.projectsInviteLink();
  final text = '📌 Seni Shake Rack\'teki "${store.projects.name}" askılığına davet ediyorum.\n\n'
      '1) Uygulama yoksa indir (Android):\n'
      'https://github.com/emolibor/shake-rack/releases/download/latest/shake-rack.apk\n\n'
      '2) Kurup adını girdikten sonra bu bağlantıya dokun:\n$link';
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('"${store.projects.name}" askılığına davet',
                style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 6),
            const Text(
              'Bağlantıya dokunan kişinin uygulamasından sana erişim isteği gelir. '
              'Onaylar sekmesinde Görür ya da Düzenler seçersin; onaylamadan hiçbir şey göremez.',
              style: TextStyle(color: Colors.black54, height: 1.35),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Share.share(text, subject: store.projects.name),
              icon: const Icon(Icons.ios_share),
              label: const Text('Davet gönder (WhatsApp vb.)'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: link));
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Bağlantı kopyalandı')));
              },
              icon: const Icon(Icons.copy),
              label: const Text('Bağlantıyı kopyala'),
            ),
            const SizedBox(height: 10),
            const Text(
              'Uygulamayı zaten kurmuş biriyse Kullanıcılar listesinde de görünür; '
              'oradan doğrudan yetki verebilirsin.',
              style: TextStyle(fontSize: 12, color: Colors.black45),
            ),
          ],
        ),
      ),
    ),
  );
}
