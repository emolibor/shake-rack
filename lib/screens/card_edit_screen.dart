import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/board.dart';
import '../services/store.dart';

/// Yeni kart ekleme / mevcut kartı düzenleme sayfası.
/// Projeler askılığında: proje türleri + kişi ataması.
/// Özel askılıkta: şablon maddeleri + karta özel ek maddeler.
class CardEditScreen extends StatefulWidget {
  final RackStore store;
  final Board board;
  final CompanyCard? card; // null ise yeni kart
  const CardEditScreen(
      {super.key, required this.store, required this.board, this.card});

  @override
  State<CardEditScreen> createState() => _CardEditScreenState();
}

class _CardEditScreenState extends State<CardEditScreen> {
  late final TextEditingController _name;
  late final TextEditingController _notes;
  final _newItem = TextEditingController();
  late final Set<String> _selected;

  /// Gösterilecek tüm madde seçenekleri (şablon + karta özel olanlar).
  late final List<String> _options;
  String? _assignee;

  Board get board => widget.board;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.card?.name ?? '');
    _notes = TextEditingController(text: widget.card?.notes ?? '');
    final existing = widget.card?.items.map((e) => e.type).toList() ?? [];
    _options = [
      ...board.template,
      ...existing.where((t) => !board.template.contains(t)),
    ];
    // Yeni özel kartta şablonun hepsi seçili gelir; projelerde hiçbiri.
    _selected = widget.card != null
        ? existing.toSet()
        : (board.isProjects ? <String>{} : board.template.toSet());
    _assignee = widget.card?.assignedTo;
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    _newItem.dispose();
    super.dispose();
  }

  void _addItem() {
    final t = _newItem.text.trim();
    if (t.isEmpty) return;
    setState(() {
      if (!_options.contains(t)) _options.add(t);
      _selected.add(t);
      _newItem.clear();
    });
  }

  void _save() {
    if (board.isNotes) {
      if (_name.text.trim().isEmpty) return;
      if (widget.card == null) {
        board.addCard(_name.text, const []);
      } else {
        board.updateCard(widget.card!, name: _name.text);
      }
      Navigator.pop(context);
      return;
    }
    if (_name.text.trim().isEmpty || _selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${board.cardTitleLabel} ve en az bir ${board.isProjects ? 'proje' : 'madde'} gerekli.')));
      return;
    }
    final ordered = _options.where(_selected.contains).toList();
    if (widget.card == null) {
      board.addCard(_name.text, ordered,
          assignedTo: board.isProjects ? _assignee : null, notes: _notes.text);
    } else {
      board.updateCard(widget.card!,
          name: _name.text,
          types: ordered,
          notes: _notes.text,
          assignedTo: _assignee,
          clearAssignee: _assignee == null);
    }
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(board.isNotes ? 'Notu sil?' : 'Kartı sil?'),
        content: Text((board.isNotes
                ? 'Bu not ipten alınacak.'
                : '${widget.card!.name} ipten alınacak.') +
            ((board.isShared || (board.isProjects && widget.store.syncing))
                ? '\n\nAskılık sahibi Geçmiş sekmesinden geri yükleyebilir.'
                : '')),
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
    if (ok == true && mounted) {
      board.deleteCard(widget.card!);
      Navigator.pop(context);
    }
  }

  /// Not askılığı: sadece yazı.
  Widget _noteBody(bool isNew) => Scaffold(
        backgroundColor: const Color(0xFFFFF8E7),
        appBar: AppBar(
          backgroundColor: const Color(0xFFFFF4B8),
          title: Text(isNew ? 'Yeni Not' : 'Notu Düzenle'),
          actions: [
            if (!isNew)
              IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
            IconButton(icon: const Icon(Icons.check), onPressed: _save),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _name,
            autofocus: isNew,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 17, height: 1.4),
            decoration: const InputDecoration(
              hintText: 'Notunu yaz…',
              border: InputBorder.none,
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final isNew = widget.card == null;
    if (board.isNotes) return _noteBody(isNew);
    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'Yeni Kart · ${board.name}' : 'Kartı Düzenle'),
        actions: [
          if (!isNew)
            IconButton(
                icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: board.cardTitleLabel,
              hintText: board.isProjects ? 'Atilla Tekstil' : 'Örn. Kat planı reels',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 18),
          Text(board.itemsLabel,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _options.map((t) {
              final sel = _selected.contains(t);
              return FilterChip(
                label: Text(kShortNames[t] ?? t),
                selected: sel,
                onSelected: (v) =>
                    setState(() => v ? _selected.add(t) : _selected.remove(t)),
              );
            }).toList(),
          ),
          if (!board.isProjects) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newItem,
                    onSubmitted: (_) => _addItem(),
                    decoration: const InputDecoration(
                      hintText: 'Bu karta madde ekle (ör. TikTok)',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                    onPressed: _addItem, icon: const Icon(Icons.add)),
              ],
            ),
          ],
          if (board.isProjects) ...[
            const SizedBox(height: 18),
            const Text('Kim çizecek? (kart rengi)',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ChoiceChip(
                  label: const Text('Atama yok'),
                  selected: _assignee == null,
                  onSelected: (_) => setState(() => _assignee = null),
                ),
                ...widget.store.members.map((m) => ChoiceChip(
                      avatar: CircleAvatar(backgroundColor: m.color, radius: 8),
                      label: Text(m.name),
                      selected: _assignee == m.id,
                      selectedColor: m.color.withOpacity(0.3),
                      onSelected: (_) => setState(() => _assignee = m.id),
                    )),
              ],
            ),
          ],
          const SizedBox(height: 18),
          TextField(
            controller: _notes,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'Notlar',
              hintText: board.isProjects
                  ? 'Ölçüler alındı, kat planı bekleniyor...'
                  : 'Fikir, link, açıklama...',
              border: const OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.push_pin),
            label: Text(isNew ? 'İpe As' : 'Kaydet'),
          ),
        ],
      ),
    );
  }
}
