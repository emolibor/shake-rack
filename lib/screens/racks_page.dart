import 'package:flutter/material.dart';
import '../services/board.dart';
import '../services/store.dart';
import '../widgets/rope_card.dart';
import 'board_edit_screen.dart';
import 'rack_screen.dart';
import 'share_sheets.dart';

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
        final all = store.boards;
        final Board? board = store.boardById(_selected) ??
            (all.isEmpty ? null : all.first);
        return Column(
          children: [
            _HangerTabs(
              boards: store.boards,
              selectedId: board?.id ?? '',
              onSelect: (b) => setState(() => _selected = b.id),
              onEdit: (b) => (b.role == ShareRole.editor || b.role == ShareRole.viewer)
                  ? showSharedInfoSheet(context, store, b)
                  : BoardEditScreen.edit(context, store, b),
              onReorder: store.reorderBoards,
              onAdd: _create,
            ),
            Expanded(
              child: board == null
                  ? _Welcome(onCreate: _create)
                  : RackScreen(
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
  final void Function(int oldIndex, int newIndex) onReorder;
  final VoidCallback onAdd;

  const _HangerTabs({
    required this.boards,
    required this.selectedId,
    required this.onSelect,
    required this.onEdit,
    required this.onReorder,
    required this.onAdd,
  });

  static const _brown = Color(0xFF8B6A3E);

  /// Sürüklemenin başladığı sekme (bırakınca yer değişti mi anlamak için).
  static int? _dragStart;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 74,
      decoration: const BoxDecoration(
        color: Color(0xFFE6D9C2),
        border: Border(bottom: BorderSide(color: Color(0xFFD2C1A3))),
      ),
      child: Row(
        children: [
          // Uzun bas + sürükle → yer değiştir. Uzun bas + kaydırmadan bırak → düzenle.
          Expanded(
            child: ReorderableListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(10, 8, 2, 8),
              buildDefaultDragHandles: false,
              proxyDecorator: (child, i, anim) => AnimatedBuilder(
                animation: anim,
                builder: (_, c) => Transform.rotate(
                  angle: -0.06 * anim.value,
                  child: Transform.scale(
                    scale: 1 + 0.08 * anim.value,
                    child: Material(color: Colors.transparent, child: c),
                  ),
                ),
                child: child,
              ),
              onReorderStart: (i) => _dragStart = i,
              onReorderEnd: (i) {
                final s = _dragStart;
                _dragStart = null;
                // yerinden oynamadan bırakıldıysa: düzenleme aç
                if (s != null && (i == s || i == s + 1)) {
                  final b = boards[s];
                  WidgetsBinding.instance
                      .addPostFrameCallback((_) => onEdit(b));
                }
              },
              onReorder: (o, n) {
                if (n == o || n == o + 1) return; // yer değişmedi
                onReorder(o, n);
              },
              children: [
                for (var i = 0; i < boards.length; i++)
                  ReorderableDelayedDragStartListener(
                    key: ValueKey(boards[i].id),
                    index: i,
                    child: _tab(
                      label: boards[i].name,
                      selected: boards[i].id == selectedId,
                      locked: boards[i].isPrivate,
                      shared: boards[i].isShared,
                      count: boards[i].active.length,
                      notes: boards[i].isNotes,
                      onTap: () => onSelect(boards[i]),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 10, 8),
            child: _tab(label: 'Yeni', selected: false, add: true, onTap: onAdd),
          ),
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
    bool shared = false,
    bool add = false,
    bool notes = false,
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
                      : notes
                          ? Icon(Icons.sticky_note_2_outlined, size: 22, color: fg)
                          : HangerLogo(size: 24, color: fg),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (locked || shared) ...[
                        Icon(shared ? Icons.people_alt : Icons.lock,
                            size: 10, color: fg.withOpacity(0.8)),
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

/// Hiç askılık yokken: karşılama.
class _Welcome extends StatelessWidget {
  final VoidCallback onCreate;
  const _Welcome({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEFE6D6),
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const HangerLogo(size: 84, color: Color(0xFF8B6A3E)),
            const SizedBox(height: 16),
            const Text('Askılığın boş',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text(
              'Alışveriş, yapılacaklar, içerik fikirleri, projeler…\n'
              'Bir askılık aç, notlarını ipe as, bitince tikle.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, height: 1.4),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Askılık aç'),
            ),
          ],
        ),
      ),
    );
  }
}
