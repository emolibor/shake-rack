import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../services/board.dart';
import '../services/store.dart';
import '../widgets/people.dart';

const _apkUrl =
    'https://github.com/emolibor/shake-rack/releases/download/latest/shake-rack.apk';

String _inviteText(Board b) {
  final perm = b.shareCanEdit ? 'birlikte düzenleyebiliriz' : 'sadece inceleyebilirsin';
  return '📌 Shake Rack\'te "${b.name}" askılığını seninle paylaştım ($perm).\n\n'
      'Kod: ${b.shareCodePretty}\n\n'
      'Uygulamada: Askılık → + Yeni → Kodla katıl\n'
      'Uygulama yoksa indir: $_apkUrl';
}

Widget _sheetFrame(BuildContext ctx, List<Widget> children) => SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 8, 20, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );

// =====================================================================
// Sahip: askılığı paylaş / izinleri değiştir / durdur
// =====================================================================
Future<void> showShareSheet(BuildContext context, RackStore store, Board b) {
  var canEdit = b.isShared ? b.shareCanEdit : true;
  var allowCopy = b.isShared ? b.allowCopy : true;
  var busy = false;
  String? error;

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      Future<void> run(Future<void> Function() job) async {
        setS(() {
          busy = true;
          error = null;
        });
        try {
          await job();
        } catch (e) {
          error = '$e'.replaceFirst('Bad state: ', '');
        }
        if (ctx.mounted) setS(() => busy = false);
      }

      final shared = b.isShared;
      return _sheetFrame(ctx, [
        Text('"${b.name}" askılığını paylaş',
            style: Theme.of(ctx).textTheme.titleLarge),
        const SizedBox(height: 4),
        const Text('Kodu alan kişi kendi telefonunda bu askılığı görür.',
            style: TextStyle(color: Colors.black54)),
        const SizedBox(height: 16),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
                value: true, icon: Icon(Icons.edit), label: Text('Düzenleyebilir')),
            ButtonSegment(
                value: false,
                icon: Icon(Icons.visibility_outlined),
                label: Text('Sadece inceler')),
          ],
          selected: {canEdit},
          onSelectionChanged: (s) => setS(() => canEdit = s.first),
        ),
        const SizedBox(height: 6),
        Text(
          canEdit
              ? 'Tik atabilir, kart/not ekleyip düzenleyebilir. Değişiklikler iki tarafta canlı görünür.'
              : 'Canlı görür ama hiçbir şeyi değiştiremez.',
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: allowCopy,
          onChanged: (v) => setS(() => allowCopy = v),
          title: const Text('Kendi askılığına kopyalayabilsin'),
          subtitle: const Text('Bağımsız bir kopya alır; senin askılığını etkilemez.'),
        ),
        if (shared) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE8DCC6)),
            ),
            child: Column(
              children: [
                const Text('PAYLAŞIM KODU',
                    style: TextStyle(fontSize: 11, letterSpacing: 2, color: Colors.black45)),
                const SizedBox(height: 4),
                SelectableText(b.shareCodePretty,
                    style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 3,
                        fontFamily: 'monospace')),
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: b.shareCodePretty));
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Kod kopyalandı')));
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Kopyala'),
                ),
              ],
            ),
          ),
        ],
        if (store.friends.values.any((f) => !b.people.containsKey(f.id))) ...[
          const SizedBox(height: 12),
          const Text('Arkadaşına doğrudan gönder',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const Text('Kod gerekmez; askılık onun telefonunda kendiliğinden belirir.',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final f in store.friends.values.where((f) => !b.people.containsKey(f.id)))
                ActionChip(
                  avatar: PersonAvatar(person: f, size: 22),
                  label: Text(f.name.isEmpty ? 'İsimsiz' : f.name),
                  onPressed: busy
                      ? null
                      : () => run(() async {
                            if (!await ensureProfile(context, store)) return;
                            if (!b.isShared) {
                              await store.shareBoard(b, canEdit: canEdit, allowCopy: allowCopy);
                            }
                            await store.inviteFriend(b, f);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text('${f.name} davet edildi 🤝')));
                            }
                          }),
                ),
            ],
          ),
        ],
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(error!, style: const TextStyle(color: Colors.red)),
          ),
        const SizedBox(height: 14),
        if (!shared)
          FilledButton.icon(
            onPressed: busy
                ? null
                : () => run(() async {
                      if (!await ensureProfile(context, store)) return;
                      await store.shareBoard(b, canEdit: canEdit, allowCopy: allowCopy);
                      await Share.share(_inviteText(b), subject: b.name);
                    }),
            icon: busy
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.ios_share),
            label: const Text('Kod oluştur ve gönder'),
          )
        else ...[
          FilledButton.icon(
            onPressed: busy ? null : () => Share.share(_inviteText(b), subject: b.name),
            icon: const Icon(Icons.ios_share),
            label: const Text('Davet gönder (WhatsApp vb.)'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: (busy ||
                    (canEdit == b.shareCanEdit && allowCopy == b.allowCopy))
                ? null
                : () => run(() =>
                    store.shareBoard(b, canEdit: canEdit, allowCopy: allowCopy)),
            icon: const Icon(Icons.save_outlined),
            label: const Text('İzinleri güncelle'),
          ),
          const SizedBox(height: 4),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: busy
                ? null
                : () => run(() async {
                      await store.stopSharing(b);
                      if (ctx.mounted) Navigator.pop(ctx);
                    }),
            icon: const Icon(Icons.link_off),
            label: const Text('Paylaşımı durdur'),
          ),
        ],
      ]);
    }),
  );
}

// =====================================================================
// Alıcı: kodla katıl
// =====================================================================
Future<Board?> showJoinSheet(BuildContext context, RackStore store) {
  final ctrl = TextEditingController();
  Map<String, dynamic>? found;
  var busy = false;
  String? error;

  return showModalBottomSheet<Board>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      Future<void> find() async {
        setS(() {
          busy = true;
          error = null;
          found = null;
        });
        try {
          if (!store.firebaseReady) throw 'İnternet / Firebase bağlantısı yok.';
          final d = await store.fetchShared(ctrl.text);
          if (d == null) {
            error = 'Bu koda ait askılık bulunamadı. Kodu kontrol et.';
          } else {
            found = d;
          }
        } catch (e) {
          error = '$e';
        }
        if (ctx.mounted) setS(() => busy = false);
      }

      final d = found;
      final canEdit = d?['permission'] != 'view';
      final allowCopy = d?['allowCopy'] == true;
      final isNotes = d?['kind'] == 'notes';
      final isProj = d?['kind'] == 'projects';
      final count = ((d?['cards'] as List?) ?? const [])
          .where((c) => c is Map && c['deleted'] != true)
          .length;
      final replaces = isProj &&
          store.rackCode != d?['_doc'] &&
          store.projects.live.isNotEmpty;

      return _sheetFrame(ctx, [
        Text('Kodla katıl', style: Theme.of(ctx).textTheme.titleLarge),
        const SizedBox(height: 4),
        const Text('Sana gönderilen paylaşım kodunu yaz.',
            style: TextStyle(color: Colors.black54)),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                onSubmitted: (_) => find(),
                style: const TextStyle(
                    fontSize: 20, letterSpacing: 2, fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  hintText: 'K7P2-QX9M',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: busy ? null : find,
              child: busy
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Bul'),
            ),
          ],
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(error!, style: const TextStyle(color: Colors.red)),
          ),
        if (d != null) ...[
          const SizedBox(height: 16),
          Card(
            margin: EdgeInsets.zero,
            color: const Color(0xFFFFF8E7),
            child: ListTile(
              leading: Icon(isProj
                  ? Icons.groups_outlined
                  : isNotes
                      ? Icons.sticky_note_2_outlined
                      : Icons.checkroom),
              title: Text('${d['name']}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                  '${d['ownerName'] ?? 'Biri'} paylaştı · $count ${isProj ? 'firma' : isNotes ? 'not' : 'kart'}\n'
                  '${canEdit ? 'Düzenleyebilirsin' : 'Sadece inceleyebilirsin'}'),
              isThreeLine: true,
            ),
          ),
          if (replaces)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Dikkat: Bu telefondaki "${store.projects.name}" askılığının yerini alır '
                '(${store.projects.live.length} firma). Onları korumak istersen önce '
                '"Kopyasını al" seç ya da paylaşanla birleştirin.',
                style: const TextStyle(color: Colors.deepOrange, fontSize: 12.5),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () async {
              if (!await ensureProfile(context, store)) return;
              if (ctx.mounted) Navigator.pop(ctx, store.joinShared(d));
            },
            icon: Icon(canEdit ? Icons.group_add : Icons.visibility_outlined),
            label: Text(canEdit ? 'Askılığa katıl (birlikte düzenle)' : 'Askılığa katıl (izle)'),
          ),
          if (allowCopy) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(ctx, store.copyShared(d)),
              icon: const Icon(Icons.copy_all),
              label: const Text('Kopyasını kendi askılığıma ekle'),
            ),
          ],
        ],
      ]);
    }),
  );
}

// =====================================================================
// Alıcı: paylaşılan askılığın bilgisi / kopyala / ayrıl
// =====================================================================
Future<void> showSharedInfoSheet(BuildContext context, RackStore store, Board b) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (ctx) => _sheetFrame(ctx, [
      Text(b.name, style: Theme.of(ctx).textTheme.titleLarge),
      const SizedBox(height: 4),
      Text(
        b.canEdit
            ? 'Paylaşılan askılık · düzenleyebilirsin. Değişiklikler herkeste görünür.'
            : 'Paylaşılan askılık · sadece inceleyebilirsin.',
        style: const TextStyle(color: Colors.black54),
      ),
      const SizedBox(height: 16),
      if (b.allowCopy)
        OutlinedButton.icon(
          onPressed: () {
            final copy = store.copyShared(
                {...b.sharePayload(), 'name': '${b.name} (kopya)'});
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('"${copy.name}" askılıklarına eklendi')));
          },
          icon: const Icon(Icons.copy_all),
          label: const Text('Kopyasını kendi askılığıma ekle'),
        ),
      const SizedBox(height: 8),
      TextButton.icon(
        style: TextButton.styleFrom(foregroundColor: Colors.red),
        onPressed: () async {
          await store.deleteBoard(b);
          if (ctx.mounted) Navigator.pop(ctx);
        },
        icon: const Icon(Icons.logout),
        label: const Text('Askılıktan ayrıl'),
      ),
    ]),
  );
}
