import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/store.dart';

/// Tamamlanan firmaların listesi.
class CompletedScreen extends StatelessWidget {
  final RackStore store;
  const CompletedScreen({super.key, required this.store});

  String _date(DateTime? d) =>
      d == null ? '' : '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final done = store.completed;
        if (done.isEmpty) {
          return const Center(
            child: Text('Henüz tamamlanan firma yok.',
                style: TextStyle(color: Colors.black54)),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: done.length,
          itemBuilder: (context, i) {
            final c = done[i];
            final who = store.memberById(c.assignedTo);
            return Card(
              color: who != null
                  ? Color.lerp(Colors.white, who.color, 0.15)
                  : null,
              child: ExpansionTile(
                leading: const Icon(Icons.check_circle, color: Colors.green),
                title: Text(c.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${c.items.length} proje · ${_date(c.completedAt)}'),
                children: [
                  ...c.items.map((it) {
                    final m = store.memberById(it.doneBy);
                    return ListTile(
                      dense: true,
                      leading: Icon(Icons.check, color: m?.color ?? Colors.grey),
                      title: Text(it.type),
                      trailing: m != null
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
                  OverflowBar(
                    children: [
                      TextButton.icon(
                        onPressed: () => store.reopen(c),
                        icon: const Icon(Icons.undo),
                        label: const Text('İpe geri as'),
                      ),
                      TextButton.icon(
                        onPressed: () => store.deleteCard(c),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Sil'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
