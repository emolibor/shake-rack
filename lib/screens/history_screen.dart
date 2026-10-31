import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/store.dart';
import '../widgets/people.dart';

/// Geçmiş: ortak askılıklarda kim ne yaptı. Varsayılan: diğer kullanıcılar.
class HistoryScreen extends StatefulWidget {
  final RackStore store;
  const HistoryScreen({super.key, required this.store});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  bool _othersOnly = true;
  String? _board; // null = tümü

  static const _months = [
    'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
    'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'
  ];

  String _day(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Bugün';
    if (diff == 1) return 'Dün';
    return '${d.day} ${_months[d.month - 1]}${d.year != now.year ? ' ${d.year}' : ''}';
  }

  String _time(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  static const _icons = {
    'tick': (Icons.check_circle, Color(0xFF2E7D32)),
    'untick': (Icons.remove_circle_outline, Color(0xFF9E9E9E)),
    'complete': (Icons.celebration, Color(0xFFE09A2E)),
    'reopen': (Icons.undo, Color(0xFF6B4F2A)),
    'add': (Icons.add_circle_outline, Color(0xFF2E7DE0)),
    'edit': (Icons.edit_outlined, Color(0xFF6B4F2A)),
    'delete': (Icons.delete_outline, Color(0xFFD32F2F)),
    'restore': (Icons.restore, Color(0xFF14A3A3)),
  };

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final all = store.activities;
        final boardNames = <String, String>{
          for (final a in all) a.boardId: a.boardName,
        };
        final list = all
            .where((a) => !_othersOnly || a.by != store.profile.id)
            .where((a) => _board == null || a.boardId == _board)
            .toList();

        return Column(
          children: [
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                children: [
                  ChoiceChip(
                    label: const Text('Diğer kullanıcılar'),
                    selected: _othersOnly,
                    onSelected: (_) => setState(() => _othersOnly = true),
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: const Text('Herkes'),
                    selected: !_othersOnly,
                    onSelected: (_) => setState(() => _othersOnly = false),
                  ),
                  if (boardNames.length > 1) ...[
                    const SizedBox(width: 14),
                    for (final e in boardNames.entries)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(e.value),
                          selected: _board == e.key,
                          onSelected: (v) => setState(() => _board = v ? e.key : null),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: list.isEmpty
                  ? _empty(all.isEmpty)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final a = list[i];
                        final header = i == 0 || _day(list[i - 1].at) != _day(a.at);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (header)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(6, 14, 6, 6),
                                child: Text(_day(a.at),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF6B4F2A))),
                              ),
                            _tile(a),
                          ],
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _empty(bool nothing) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.history, size: 56, color: Color(0xFFB59B74)),
              const SizedBox(height: 10),
              Text(
                nothing
                    ? 'Henüz geçmiş yok.\nOrtak askılıklarda (proje kodu ya da paylaştığın askılıklar) '
                        'yapılan tikler, tamamlananlar ve silinenler burada görünür.'
                    : 'Diğer kullanıcılardan henüz bir işlem yok.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54, height: 1.4),
              ),
            ],
          ),
        ),
      );

  Widget _tile(Activity a) {
    final store = widget.store;
    final person = Member(
        id: a.by,
        name: a.byName,
        color: Color(a.byColor),
        emoji: store.friends[a.by]?.emoji ?? a.byEmoji);
    final (icon, color) = _icons[a.action] ?? (Icons.circle_outlined, Colors.grey);
    final restore = store.restorable(a);
    final me = a.by == store.profile.id;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: a.action == 'delete' ? const Color(0xFFFFF1F0) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                PersonAvatar(person: person, size: 36),
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: Container(
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: Icon(icon, size: 16, color: color),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(TextSpan(children: [
                    TextSpan(
                        text: me ? 'Sen' : (a.byName.isEmpty ? 'Biri' : a.byName),
                        style: TextStyle(fontWeight: FontWeight.w700, color: Color(a.byColor))),
                    const TextSpan(text: '  '),
                    TextSpan(text: a.text),
                  ])),
                  const SizedBox(height: 3),
                  Text('${a.boardName} · ${_time(a.at)}',
                      style: const TextStyle(fontSize: 11.5, color: Colors.black45)),
                  if (restore != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: () {
                              restore.board.restoreCard(restore.card);
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text('${restore.card.name} geri yüklendi')));
                            },
                            icon: const Icon(Icons.restore, size: 18),
                            label: const Text('Geri yükle'),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(foregroundColor: Colors.black54),
                            onPressed: () => restore.board.purgeCard(restore.card),
                            child: const Text('Kalıcı sil'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
