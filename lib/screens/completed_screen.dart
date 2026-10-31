import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/board.dart';
import '../services/store.dart';

/// Tamamlanan kartlar; üstten askılık seçilir (Projeler / özel askılıklar).
class CompletedScreen extends StatefulWidget {
  final RackStore store;
  const CompletedScreen({super.key, required this.store});

  @override
  State<CompletedScreen> createState() => _CompletedScreenState();
}

class _CompletedScreenState extends State<CompletedScreen> {
  String _selected = Board.projectsId;

  String _date(DateTime? d) => d == null
      ? ''
      : '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final all = store.boards;
        if (all.isEmpty) {
          return const Center(
              child: Text('Henüz askılık yok.', style: TextStyle(color: Colors.black54)));
        }
        final board = store.boardById(_selected) ?? all.first;
        final done = board.completed;
        return Column(
          children: [
            if (all.length > 1)
              SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                  children: [
                    for (final b in store.boards)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          avatar: b.isShared
                              ? const Icon(Icons.people_alt, size: 14)
                              : b.isPrivate
                                  ? const Icon(Icons.lock, size: 14)
                                  : null,
                          label: Text('${b.name} (${b.completed.length})'),
                          selected: b.id == board.id,
                          onSelected: (_) => setState(() => _selected = b.id),
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: done.isEmpty
                  ? Center(
                      child: Text(
                          board.isProjects
                              ? 'Henüz tamamlanan firma yok.'
                              : '${board.name} askılığında tamamlanan yok.',
                          style: const TextStyle(color: Colors.black54)),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: done.length,
                      itemBuilder: (context, i) => _tile(board, done[i]),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _noteTile(Board board, CompanyCard c) => Card(
        color: const Color(0xFFFFFBE6),
        child: ListTile(
          leading: Icon(Icons.check_circle, color: Colors.green.shade600),
          title: Text(c.name,
              style: const TextStyle(
                  decoration: TextDecoration.lineThrough,
                  color: Colors.black54)),
          subtitle: Text(_date(c.completedAt)),
          trailing: !board.canEdit ? null : PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'reopen') {
                board.reopen(c);
              } else {
                board.deleteCard(c);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'reopen', child: Text('İpe geri as')),
              PopupMenuItem(value: 'delete', child: Text('Sil')),
            ],
          ),
        ),
      );

  Widget _tile(Board board, CompanyCard c) {
    if (board.isNotes) return _noteTile(board, c);
    final store = widget.store;
    final who = store.memberById(c.assignedTo);
    final unit = board.isProjects ? 'proje' : 'madde';
    return Card(
      color: who != null ? Color.lerp(Colors.white, who.color, 0.15) : null,
      child: ExpansionTile(
        leading: const Icon(Icons.check_circle, color: Colors.green),
        title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${c.items.length} $unit · ${_date(c.completedAt)}'),
        children: [
          for (final it in c.items)
            Builder(builder: (_) {
              final m = store.memberById(it.doneBy);
              return ListTile(
                dense: true,
                leading: Icon(Icons.check, color: m?.color ?? Colors.grey),
                title: Text(it.type),
                trailing: (m != null && board.isProjects)
                    ? Text(m.name, style: TextStyle(color: m.color))
                    : null,
              );
            }),
          if (c.notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(c.notes,
                  style: const TextStyle(fontStyle: FontStyle.italic)),
            ),
          if (board.canEdit)
          OverflowBar(
            children: [
              TextButton.icon(
                onPressed: () => board.reopen(c),
                icon: const Icon(Icons.undo),
                label: const Text('İpe geri as'),
              ),
              TextButton.icon(
                onPressed: () => board.deleteCard(c),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Sil'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
