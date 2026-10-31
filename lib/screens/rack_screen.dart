import 'dart:math';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/board.dart';
import '../services/store.dart';
import '../widgets/people.dart';
import '../widgets/rope_card.dart';
import 'card_edit_screen.dart';

/// Bir askılığın ekranı: ip + asılı kartlar. Sürükle-bırak ile öncelik sırası.
class RackScreen extends StatefulWidget {
  final RackStore store;
  final Board board;
  const RackScreen({super.key, required this.store, required this.board});

  @override
  State<RackScreen> createState() => _RackScreenState();
}

class _RackScreenState extends State<RackScreen> {
  late final ConfettiController _confetti;

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(duration: const Duration(seconds: 2));
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  Future<void> _onToggle(CompanyCard card, ProjectItem item) async {
    final board = widget.board;
    final finished = board.toggleItem(card, item);
    if (!finished) return;
    _confetti.play();
    // Balon patlama animasyonu + tamamlandı diyaloğu
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BalloonPop(name: card.name),
    );
    if (!mounted) return;
    board.markCompleted(card);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${card.name} Tamamlananlara taşındı 🎉'),
      action: SnackBarAction(
        label: 'Geri al',
        onPressed: () => board.reopen(card),
      ),
    ));
  }

  /// Not askılığı: üstü çizili göster, kısa süre sonra Tamamlananlar'a at.
  final Set<String> _ticking = {};

  Future<void> _onNoteTick(CompanyCard card) async {
    final board = widget.board;
    if (_ticking.contains(card.id)) return;
    setState(() => _ticking.add(card.id));
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;
    _ticking.remove(card.id);
    board.toggleNote(card);
    _confetti.play();
    final short = card.name.length > 30 ? '${card.name.substring(0, 30)}…' : card.name;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('✓ $short'),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'Geri al',
          onPressed: () => board.reopen(card),
        ),
      ));
  }

  /// Not askılığı: alttan açılan hızlı not yazma.
  Future<void> _quickNote() async {
    final ctrl = TextEditingController();
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFFFF4B8),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: ctrl,
                autofocus: true,
                minLines: 1,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Notunu yaz…',
                  border: InputBorder.none,
                ),
              ),
            ),
            IconButton.filled(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              icon: const Icon(Icons.push_pin),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (text != null && text.trim().isNotEmpty) {
      widget.board.addCard(text, const []);
    }
  }

  void _add() => widget.board.isNotes ? _quickNote() : _openEdit();

  /// Sadece inceleme izninde değişiklik engellenir.
  void _guard(void Function() action) {
    if (widget.board.canEdit) {
      action();
    } else {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            content: Text('Bu askılığı sadece inceleyebilirsin 👁')));
    }
  }

  void _openEdit([CompanyCard? card]) {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => CardEditScreen(
              store: widget.store, board: widget.board, card: card)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final board = widget.board;
    return Stack(
      children: [
        // duvar dokusu
        Container(color: const Color(0xFFEFE6D6)),
        AnimatedBuilder(
          animation: store,
          builder: (context, _) {
            final cards = board.active;
            return Column(
              children: [
                if (!board.isProjects) _StatusBand(board: board, store: store),
                const SizedBox(height: 8),
                SizedBox(
                  height: 28,
                  width: double.infinity,
                  child: CustomPaint(painter: RopePainter()),
                ),
                Expanded(
                  child: cards.isEmpty
                      ? _Empty(board: board, onAdd: () => _guard(_add))
                      : ReorderableListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                          buildDefaultDragHandles: false,
                          onReorder: (o, n) {
                            if (board.canEdit) board.reorderActive(o, n);
                          },
                          proxyDecorator: (child, i, anim) => Transform.scale(
                              scale: 1.03, child: Material(color: Colors.transparent, child: child)),
                          itemCount: cards.length,
                          itemBuilder: (context, i) {
                            final c = cards[i];
                            if (board.isNotes) {
                              return NoteRopeCard(
                                key: ValueKey(c.id),
                                card: c,
                                index: i,
                                ticking: _ticking.contains(c.id),
                                onOpen: () => _guard(() => _openEdit(c)),
                                onToggle: () => _guard(() => _onNoteTick(c)),
                              );
                            }
                            return RopeCard(
                              key: ValueKey(c.id),
                              card: c,
                              store: store,
                              index: i,
                              onOpen: () => _guard(() => _openEdit(c)),
                              onToggle: (it) => _guard(() => _onToggle(c, it)),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
        if (board.canEdit)
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: _add,
            icon: Icon(board.isNotes ? Icons.edit_note : Icons.add),
            label: Text(board.isNotes ? 'Not yaz' : 'Kart as'),
          ),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _confetti,
            blastDirectionality: BlastDirectionality.explosive,
            numberOfParticles: 40,
            emissionFrequency: 0.05,
            gravity: 0.25,
            colors: const [
              Colors.red, Colors.orange, Colors.yellow, Colors.green,
              Colors.blue, Colors.purple, Colors.pink,
            ],
          ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  final Board board;
  final VoidCallback onAdd;
  const _Empty({required this.board, required this.onAdd});
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const HangerLogo(size: 72, color: Color(0xFF8B6A3E)),
            const SizedBox(height: 12),
            Text(board.isProjects
                ? 'İp boş. İlk firmayı as!'
                : board.isNotes
                    ? '${board.name} ipi boş. İlk notunu yaz!'
                    : '${board.name} ipi boş. İlk kartı as!',
                style: TextStyle(fontSize: 16, color: Colors.black54)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
                onPressed: onAdd,
                icon: Icon(board.isNotes ? Icons.edit_note : Icons.add),
                label: Text(board.isNotes ? 'Not yaz' : 'Kart as')),
          ],
        ),
      );
}

/// Şişip patlayan balon animasyonu.
class _BalloonPop extends StatefulWidget {
  final String name;
  const _BalloonPop({required this.name});
  @override
  State<_BalloonPop> createState() => _BalloonPopState();
}

class _BalloonPopState extends State<_BalloonPop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
      ..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = _c.value;
          // 0..0.7 şişer, 0.7..0.85 patlar (kaybolur), sonra yazı
          final inflate = Curves.easeOutBack.transform(min(t / 0.7, 1));
          final popped = t > 0.7;
          final shards = popped ? ((t - 0.7) / 0.15).clamp(0.0, 1.0) : 0.0;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 200,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (!popped)
                      Transform.scale(
                        scale: 0.3 + inflate * 0.9,
                        child: Container(
                          width: 130,
                          height: 160,
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(70),
                              bottom: Radius.circular(60),
                            ),
                            boxShadow: const [
                              BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, 6))
                            ],
                          ),
                          child: Align(
                            alignment: const Alignment(-0.4, -0.5),
                            child: Container(
                                width: 24, height: 40,
                                decoration: BoxDecoration(
                                    color: Colors.white38,
                                    borderRadius: BorderRadius.circular(20))),
                          ),
                        ),
                      ),
                    if (popped)
                      ...List.generate(10, (i) {
                        final a = i * pi * 2 / 10;
                        final d = 20 + shards * 110;
                        return Transform.translate(
                          offset: Offset(cos(a) * d, sin(a) * d),
                          child: Opacity(
                            opacity: 1 - shards,
                            child: Container(
                                width: 14, height: 14,
                                decoration: const BoxDecoration(
                                    color: Colors.redAccent, shape: BoxShape.circle)),
                          ),
                        );
                      }),
                    if (t > 0.8)
                      Opacity(
                        opacity: ((t - 0.8) / 0.2).clamp(0.0, 1.0),
                        child: const Text('🎉',
                            style: TextStyle(fontSize: 80)),
                      ),
                  ],
                ),
              ),
              if (t > 0.85)
                Opacity(
                  opacity: ((t - 0.85) / 0.15).clamp(0.0, 1.0),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${widget.name} tamamlandı!',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          const Text('Tüm projeler çizildi. Helal olsun 👏'),
                          const SizedBox(height: 14),
                          FilledButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Tamamlananlara at')),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// İpin üstündeki ince bilgi bandı: özel / paylaşılıyor / sadece inceleme.
class _StatusBand extends StatelessWidget {
  final Board board;
  final RackStore store;
  const _StatusBand({required this.board, required this.store});

  @override
  Widget build(BuildContext context) {
    final c = Colors.brown.shade400;
    late final IconData icon;
    late final String text;
    if (board.shareEnded && !board.isShared) {
      icon = Icons.link_off;
      text = 'Paylaşım sonlandırıldı · bu artık senin kopyan';
    } else if (!board.isShared) {
      icon = Icons.lock_outline;
      text = 'Özel askılık · sadece bu telefonda';
    } else if (board.role == ShareRole.owner) {
      icon = Icons.people_alt_outlined;
      text = 'Paylaşılıyor · kod ${board.shareCodePretty} · '
          '${board.shareCanEdit ? 'düzenleyebilirler' : 'sadece inceleyebilirler'}';
    } else if (board.canEdit) {
      icon = Icons.people_alt_outlined;
      text = 'Paylaşılan askılık · düzenleyebilirsin';
    } else {
      icon = Icons.visibility_outlined;
      text = 'Paylaşılan askılık · sadece inceleme';
    }
    final others = board.isShared ? boardPeople(store, board) : const <Member>[];
    return InkWell(
      onTap: board.isShared ? () => showPeopleSheet(context, store, board) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 13, color: c),
            const SizedBox(width: 4),
            Flexible(
              child: Text(text,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: c)),
            ),
            if (others.isNotEmpty) ...[
              const SizedBox(width: 8),
              AvatarStack(people: others, size: 20),
            ],
          ],
        ),
      ),
    );
  }
}
