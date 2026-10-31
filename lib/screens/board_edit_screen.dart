import 'package:flutter/material.dart';
import '../services/board.dart';
import '../services/store.dart';

/// Özel askılık oluştur / düzenle: ad + her karta gelecek maddeler (şablon).
class BoardEditScreen extends StatefulWidget {
  final RackStore store;
  final Board? board; // null = yeni
  const BoardEditScreen({super.key, required this.store, this.board});

  /// Yeni askılık açar; oluşturulursa Board döner.
  static Future<Board?> create(BuildContext context, RackStore store) =>
      Navigator.push<Board>(context,
          MaterialPageRoute(builder: (_) => BoardEditScreen(store: store)));

  static Future<void> edit(BuildContext context, RackStore store, Board b) =>
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => BoardEditScreen(store: store, board: b)));

  @override
  State<BoardEditScreen> createState() => _BoardEditScreenState();
}

class _BoardEditScreenState extends State<BoardEditScreen> {
  late final TextEditingController _name =
      TextEditingController(text: widget.board?.name ?? '');
  final _item = TextEditingController();
  late final List<String> _template = List.of(widget.board?.template ?? []);

  static const _ideas = ['Instagram', 'YouTube', 'TikTok', 'Çekildi', 'Kurgulandı', 'Paylaşıldı'];

  @override
  void dispose() {
    _name.dispose();
    _item.dispose();
    super.dispose();
  }

  void _add([String? text]) {
    final t = (text ?? _item.text).trim();
    if (t.isEmpty || _template.contains(t)) return;
    setState(() => _template.add(t));
    _item.clear();
  }

  void _save() {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Askılığa bir ad ver.')));
      return;
    }
    if (_template.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('En az bir madde ekle (ör. Instagram).')));
      return;
    }
    if (widget.board == null) {
      final b = widget.store.addBoard(_name.text, _template);
      Navigator.pop(context, b);
    } else {
      widget.store.updateBoard(widget.board!, name: _name.text, template: _template);
      Navigator.pop(context);
    }
  }

  Future<void> _delete() async {
    final b = widget.board!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('"${b.name}" askılığını sil?'),
        content: Text('İçindeki ${b.cards.length} kart da silinecek. Geri alınamaz.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sil')),
        ],
      ),
    );
    if (ok == true && mounted) {
      widget.store.deleteBoard(b);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.board == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'Yeni Askılık' : 'Askılığı Düzenle'),
        actions: [
          if (!isNew)
            IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.lock_outline, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Özel askılık sadece bu telefonda tutulur, grupla paylaşılmaz.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Askılık adı',
              hintText: 'Reels',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Her karta gelecek maddeler',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const Text('Sürükleyerek sırala. Kart açarken karta özel madde de ekleyebilirsin.',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 8),
          if (_template.isNotEmpty)
            Card(
              margin: EdgeInsets.zero,
              child: ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                onReorder: (o, n) => setState(() {
                  if (n > o) n -= 1;
                  _template.insert(n, _template.removeAt(o));
                }),
                children: [
                  for (var i = 0; i < _template.length; i++)
                    ListTile(
                      key: ValueKey(_template[i]),
                      dense: true,
                      leading: ReorderableDragStartListener(
                          index: i, child: const Icon(Icons.drag_indicator)),
                      title: Text(_template[i]),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => _template.removeAt(i)),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _item,
                  onSubmitted: (_) => _add(),
                  decoration: const InputDecoration(
                    hintText: 'Madde ekle (ör. Instagram)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(onPressed: _add, icon: const Icon(Icons.add)),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: _ideas
                .where((e) => !_template.contains(e))
                .map((e) => ActionChip(
                      avatar: const Icon(Icons.add, size: 16),
                      label: Text(e),
                      onPressed: () => _add(e),
                    ))
                .toList(),
          ),
          if (!isNew)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Not: Madde değişiklikleri yeni kartlarda kullanılır; mevcut kartlar aynı kalır.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.checkroom),
            label: Text(isNew ? 'Askılığı oluştur' : 'Kaydet'),
          ),
        ],
      ),
    );
  }
}
