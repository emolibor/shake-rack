import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/board.dart';
import '../services/store.dart';

/// Şablondaki bir madde; `orig` düzenlemeden önceki adı (yeni eklenense null).
class _Entry {
  final String? orig;
  String name;
  final Key key = UniqueKey();
  _Entry(this.orig, this.name);
}

/// Askılık oluştur / düzenle.
/// - Yeni: tür (maddeli / sadece not) + ad + maddeler.
/// - Özel askılık: ad + maddeler, silme.
/// - Projeler: sadece maddeler (proje türleri); grupla eşitlenir.
class BoardEditScreen extends StatefulWidget {
  final RackStore store;
  final Board? board; // null = yeni
  const BoardEditScreen({super.key, required this.store, this.board});

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
  late final List<_Entry> _entries = [
    for (final t in widget.board?.template ?? const <String>[]) _Entry(t, t)
  ];
  late BoardKind _kind = widget.board?.kind ?? BoardKind.items;

  bool get _isNew => widget.board == null;
  bool get _isProjects => widget.board?.isProjects ?? false;
  bool get _isNotes => _kind == BoardKind.notes;

  List<String> get _ideas => _isProjects
      ? kProjectTypes
      : const ['Instagram', 'YouTube', 'TikTok', 'Çekildi', 'Kurgulandı', 'Paylaşıldı'];

  @override
  void dispose() {
    _name.dispose();
    _item.dispose();
    super.dispose();
  }

  bool _exists(String t) => _entries.any((e) => e.name == t);

  void _add([String? text]) {
    final t = (text ?? _item.text).trim();
    if (t.isEmpty || _exists(t)) return;
    setState(() => _entries.add(_Entry(null, t)));
    _item.clear();
  }

  Future<void> _rename(_Entry e) async {
    final ctrl = TextEditingController(text: e.name);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Maddeyi yeniden adlandır'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (s) => Navigator.pop(ctx, s),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Tamam')),
        ],
      ),
    );
    ctrl.dispose();
    final n = v?.trim() ?? '';
    if (n.isEmpty || n == e.name) return;
    if (_exists(n)) {
      _snack('"$n" zaten var.');
      return;
    }
    setState(() => e.name = n);
  }

  void _snack(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  void _save() {
    if (!_isProjects && _name.text.trim().isEmpty) {
      _snack('Askılığa bir ad ver.');
      return;
    }
    if (!_isNotes && _entries.isEmpty) {
      _snack(_isProjects ? 'En az bir proje türü kalmalı.' : 'En az bir madde ekle (ör. Instagram).');
      return;
    }
    final template = _entries.map((e) => e.name).toList();
    if (_isNew) {
      final b = widget.store.addBoard(_name.text, template, kind: _kind);
      Navigator.pop(context, b);
      return;
    }
    final renames = <String, String>{
      for (final e in _entries)
        if (e.orig != null && e.orig != e.name) e.orig!: e.name
    };
    widget.store.updateBoard(widget.board!,
        name: _name.text, template: _isNotes ? null : template, renames: renames);
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final b = widget.board!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('"${b.name}" askılığını sil?'),
        content: Text('İçindeki ${b.cards.length} ${b.isNotes ? 'not' : 'kart'} da silinecek. Geri alınamaz.'),
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

  Widget _info(IconData icon, String text) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final title = _isNew
        ? 'Yeni Askılık'
        : _isProjects
            ? 'Proje Türlerini Düzenle'
            : 'Askılığı Düzenle';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (!_isNew && !_isProjects)
            IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _isProjects
              ? _info(Icons.groups_outlined,
                  'Projeler askılığı grupla paylaşılır; buradaki değişiklik herkeste görünür. '
                  'Bir maddenin adını değiştirirsen mevcut kartlardaki adı da değişir, tikler korunur.')
              : _info(Icons.lock_outline,
                  'Özel askılık sadece bu telefonda tutulur, grupla paylaşılmaz.'),
          const SizedBox(height: 16),
          if (_isNew) ...[
            const Text('Askılık türü', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SegmentedButton<BoardKind>(
              segments: const [
                ButtonSegment(
                    value: BoardKind.items,
                    icon: Icon(Icons.checklist),
                    label: Text('Maddeli kartlar')),
                ButtonSegment(
                    value: BoardKind.notes,
                    icon: Icon(Icons.sticky_note_2_outlined),
                    label: Text('Sadece notlar')),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 6),
            Text(
              _isNotes
                  ? 'Başlık ya da madde yok: yazını yaz, ipe as, üzerine tik at.'
                  : 'Her kartın altında tiklenecek maddeler olur (ör. Instagram, YouTube).',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 16),
          ],
          if (!_isProjects)
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Askılık adı',
                hintText: _isNotes ? 'Notlar' : 'Reels',
                border: const OutlineInputBorder(),
              ),
            ),
          if (!_isNotes) ...[
            const SizedBox(height: 20),
            Text(_isProjects ? 'Proje türleri' : 'Her karta gelecek maddeler',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const Text('Sürükleyerek sırala, adını değiştirmek için dokun.',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 8),
            if (_entries.isNotEmpty)
              Card(
                margin: EdgeInsets.zero,
                child: ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  onReorder: (o, n) => setState(() {
                    if (n > o) n -= 1;
                    _entries.insert(n, _entries.removeAt(o));
                  }),
                  children: [
                    for (var i = 0; i < _entries.length; i++)
                      ListTile(
                        key: _entries[i].key,
                        dense: true,
                        leading: ReorderableDragStartListener(
                            index: i, child: const Icon(Icons.drag_indicator)),
                        title: Text(_entries[i].name),
                        subtitle: (_entries[i].orig != null &&
                                _entries[i].orig != _entries[i].name)
                            ? Text('eski: ${_entries[i].orig}',
                                style: const TextStyle(fontSize: 11))
                            : null,
                        onTap: () => _rename(_entries[i]),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() => _entries.removeAt(i)),
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
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: _isProjects
                          ? 'Proje türü ekle (ör. Doğalgaz Projesi)'
                          : 'Madde ekle (ör. Instagram)',
                      isDense: true,
                      border: const OutlineInputBorder(),
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
                  .where((e) => !_exists(e))
                  .map((e) => ActionChip(
                        avatar: const Icon(Icons.add, size: 16),
                        label: Text(kShortNames[e] ?? e),
                        onPressed: () => _add(e),
                      ))
                  .toList(),
            ),
            if (!_isNew)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Eklenen / silinen maddeler yeni kartlarda kullanılır; '
                  'mevcut kartlara kart düzenleme ekranından eklenebilir.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.checkroom),
            label: Text(_isNew ? 'Askılığı oluştur' : 'Kaydet'),
          ),
        ],
      ),
    );
  }
}
