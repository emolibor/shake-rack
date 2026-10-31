import 'package:flutter/material.dart';
import '../services/board.dart';
import '../services/store.dart';
import '../widgets/rope_card.dart';
import 'board_edit_screen.dart';
import 'rack_screen.dart';

/// Askılık sekmeleri: üstte askı etiketleri (Projeler + özel askılıklar + "+"),
/// altında seçili askılığın ipi.
class RacksPage extends StatefulWidget {
  final RackStore store;
  const RacksPage({super.key, required this.store});

  @override
  State<RacksPage> createState() => _RacksPageState();
}

class _RacksPageState extends State<RacksPage> {
  String _selected = Board.projectsId;

  Future<void> _create() async {
    final b = await BoardEditScreen.create(context, widget.store);
    if (b != null && mounted) setState(() => _selected = b.id);
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final board = store.boardById(_selected) ?? store.projects;
        return Column(
          children: [
            _HangerTabs(
              boards: store.boards,
              selectedId: board.id,
              onSelect: (b) => setState(() => _selected = b.id),
              onEdit: (b) => BoardEditScreen.edit(context, store, b),
              onAdd: _create,
            ),
            Expanded(
              child: RackScreen(
                key: ValueKey(board.id),
                store: store,
                board: board,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _HangerTabs extends StatelessWidget {
  final List<Board> boards;
  final String selectedId;
  final void Function(Board) onSelect;
  final void Function(Board) onEdit;
  final VoidCallback onAdd;

  const _HangerTabs({
    required this.boards,
    required this.selectedId,
    required this.onSelect,
    required this.onEdit,
    required this.onAdd,
  });

  static const _brown = Color(0xFF8B6A3E);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 74,
      decoration: const BoxDecoration(
        color: Color(0xFFE6D9C2),
        border: Border(bottom: BorderSide(color: Color(0xFFD2C1A3))),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        children: [
          for (final b in boards)
            _tab(
              label: b.name,
              selected: b.id == selectedId,
              locked: b.isPrivate,
              count: b.active.length,
              onTap: () => onSelect(b),
              onLongPress: b.isPrivate ? () => onEdit(b) : null,
            ),
          _tab(label: 'Yeni', selected: false, add: true, onTap: onAdd),
        ],
      ),
    );
  }

  Widget _tab({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    bool locked = false,
    bool add = false,
    int count = 0,
  }) {
    final fg = selected ? Colors.white : _brown;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? _brown : (add ? Colors.transparent : const Color(0xFFFFF8E7)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: add
              ? const BorderSide(color: _brown, width: 1.2, style: BorderStyle.solid)
              : BorderSide.none,
        ),
        elevation: selected ? 3 : 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          onLongPress: onLongPress,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  add
                      ? Icon(Icons.add, size: 22, color: fg)
                      : HangerLogo(size: 24, color: fg),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (locked) ...[
                        Icon(Icons.lock, size: 10, color: fg.withOpacity(0.8)),
                        const SizedBox(width: 3),
                      ],
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 110),
                        child: Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: fg,
                              fontSize: 12,
                              fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
                        ),
                      ),
                      if (count > 0) ...[
                        const SizedBox(width: 4),
                        Text('$count',
                            style: TextStyle(
                                color: fg.withOpacity(0.75), fontSize: 10.5)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
