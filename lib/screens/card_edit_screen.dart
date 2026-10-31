import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/store.dart';

/// Yeni kart ekleme / mevcut kartı düzenleme sayfası.
class CardEditScreen extends StatefulWidget {
  final RackStore store;
  final CompanyCard? card; // null ise yeni kart
  const CardEditScreen({super.key, required this.store, this.card});

  @override
  State<CardEditScreen> createState() => _CardEditScreenState();
}

class _CardEditScreenState extends State<CardEditScreen> {
  late final TextEditingController _name;
  late final TextEditingController _notes;
  late final Set<String> _types;
  String? _assignee;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.card?.name ?? '');
    _notes = TextEditingController(text: widget.card?.notes ?? '');
    _types = {...?widget.card?.items.map((e) => e.type)};
    _assignee = widget.card?.assignedTo;
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    if (_name.text.trim().isEmpty || _types.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Firma adı ve en az bir proje seç.')));
      return;
    }
    final ordered = kProjectTypes.where(_types.contains).toList();
    if (widget.card == null) {
      final c = widget.store.addCard(_name.text, ordered, assignedTo: _assignee);
      widget.store.updateCard(c, notes: _notes.text);
    } else {
      widget.store.updateCard(widget.card!,
          name: _name.text,
          types: ordered,
          notes: _notes.text,
          assignedTo: _assignee,
          clearAssignee: _assignee == null);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.card == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'Yeni Kart' : 'Kartı Düzenle'),
        actions: [
          if (!isNew)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Kartı sil?'),
                    content: Text('${widget.card!.name} ipten alınacak.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
                      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sil')),
                    ],
                  ),
                );
                if (ok == true && mounted) {
                  widget.store.deleteCard(widget.card!);
                  Navigator.pop(context);
                }
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Firma adı',
              hintText: 'Atilla Tekstil',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 18),
          const Text('Çizilecek projeler', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: kProjectTypes.map((t) {
              final sel = _types.contains(t);
              return FilterChip(
                label: Text(kShortNames[t]!),
                selected: sel,
                onSelected: (v) => setState(() => v ? _types.add(t) : _types.remove(t)),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          const Text('Kim çizecek? (kart rengi)', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
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
          const SizedBox(height: 18),
          TextField(
            controller: _notes,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Notlar',
              hintText: 'Ölçüler alındı, kat planı bekleniyor...',
              border: OutlineInputBorder(),
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
