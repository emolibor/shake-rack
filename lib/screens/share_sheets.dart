import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../models/models.dart';
import '../services/board.dart';
import '../services/store.dart';
import '../widgets/people.dart';

String _inviteText(RackStore store, Board b) {
  final perm = b.shareCanEdit ? 'birlikte düzenleyebiliriz' : 'sadece inceleyebilirsin';
  return '📌 Shake Rack\'te "${b.name}" askılığına seni davet ettim ($perm).\n\n'
      'Katılmak için dokun:\n${store.inviteLink(b)}';
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

String _err(Object e) => '$e'.replaceFirst('Bad state: ', '');

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
          error = _err(e);
        }
        if (ctx.mounted) setS(() => busy = false);
      }

      final shared = b.isShared;
      final others = b.people.keys.where((id) => id != store.profile.id).length;
      return _sheetFrame(ctx, [
        Text('"${b.name}" askılığını paylaş',
            style: Theme.of(ctx).textTheme.titleLarge),
        const SizedBox(height: 4),
        const Text(
            'Bağlantıyı alan kişi katılma isteği gönderir; yönetici onaylayınca '
            'askılık onun telefonunda belirir.',
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
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE8DCC6)),
            ),
            child: Row(
              children: [
                const Icon(Icons.link, color: Color(0xFF6B4F2A)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('DAVET BAĞLANTISI',
                          style: TextStyle(fontSize: 11, letterSpacing: 2, color: Colors.black45)),
                      const SizedBox(height: 2),
                      Text(store.inviteLink(b),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5, color: Color(0xFF2E6BB8))),
                      const SizedBox(height: 2),
                      Text(
                          others == 0
                              ? 'Henüz katılan yok. Her katılım yönetici onayından geçer.'
                              : '$others kişi katıldı. Yeni katılımlar yönetici onayından geçer.',
                          style: const TextStyle(fontSize: 11.5, color: Colors.black45)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Kopyala',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: store.inviteLink(b)));
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Bağlantı kopyalandı')));
                  },
                  icon: const Icon(Icons.copy),
                ),
              ],
            ),
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
                      await Share.share(_inviteText(store, b), subject: b.name);
                    }),
            icon: busy
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.ios_share),
            label: const Text('Bağlantı oluştur ve gönder'),
          )
        else ...[
          FilledButton.icon(
            onPressed: busy ? null : () => Share.share(_inviteText(store, b), subject: b.name),
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
// Katılmak isteyen: bağlantıyla katılma isteği (yönetici onaylar)
// =====================================================================
Future<Board?> showJoinSheet(BuildContext context, RackStore store,
    {String? initialCode}) {
  final ctrl = TextEditingController(text: initialCode ?? '');
  var busy = false;
  var autoStarted = false;
  JoinRequest? sent;
  String? error;

  return showModalBottomSheet<Board>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      Future<void> send() async {
        setS(() {
          busy = true;
          error = null;
        });
        try {
          if (!await ensureProfile(context, store)) {
            setS(() => busy = false);
            return;
          }
          sent = await store.requestJoin(ctrl.text);
        } catch (e) {
          error = _err(e);
        }
        if (ctx.mounted) setS(() => busy = false);
      }

      // davet bağlantısından geldiyse isteği hemen gönder
      if (initialCode != null && !autoStarted) {
        autoStarted = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => send());
      }

      final params = RackStore.linkParams(ctrl.text);
      final r = sent;
      return _sheetFrame(ctx, [
        Text('Paylaşılan askılığa katıl', style: Theme.of(ctx).textTheme.titleLarge),
        const SizedBox(height: 4),
        const Text('Sana gönderilen bağlantıyı yapıştır. Yönetici onaylayınca askılık '
            'kendiliğinden eklenir.',
            style: TextStyle(color: Colors.black54)),
        const SizedBox(height: 14),
        if (r == null) ...[
          TextField(
            controller: ctrl,
            autofocus: initialCode == null,
            onChanged: (_) => setS(() {}),
            onSubmitted: (_) => send(),
            style: const TextStyle(fontSize: 15),
            decoration: const InputDecoration(
              hintText: 'Davet bağlantısı',
              border: OutlineInputBorder(),
            ),
          ),
          if ((params['n'] ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                  '"${params['n']}"${(params['o'] ?? '').isNotEmpty ? ' · ${params['o']} paylaştı' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(error!, style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: busy || ctrl.text.trim().isEmpty ? null : send,
            icon: busy
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.how_to_reg_outlined),
            label: const Text('Katılma isteği gönder'),
          ),
        ] else ...[
          Card(
            margin: EdgeInsets.zero,
            color: const Color(0xFFFFF8E7),
            child: ListTile(
              leading: const Icon(Icons.hourglass_top, color: Color(0xFFE09A2E)),
              title: Text(r.boardName.isEmpty ? 'Katılma isteği gönderildi' : '"${r.boardName}"',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Yönetici onayı bekleniyor. Onaylanınca askılık '
                  'Askılık sekmesinde kendiliğinden belirir; bu pencereyi kapatabilirsin.'),
              isThreeLine: true,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tamam'),
          ),
        ],
      ]);
    }),
  );
}

// =====================================================================
// Katılan: paylaşılan askılığın bilgisi / kopyala / ayrıl
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
