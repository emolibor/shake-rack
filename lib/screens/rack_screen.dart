import 'dart:math';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/board.dart';
import '../services/store.dart';
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
                if (board.isPrivate)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_outline, size: 13, color: Colors.brown.shade400),
                        const SizedBox(width: 4),
                        Text('Özel askılık · sadece bu telefonda',
                            style: TextStyle(fontSize: 11.5, color: Colors.brown.shade400)),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 28,
                  width: double.infinity,
                  child: CustomPaint(painter: RopePainter()),
                ),
                Expanded(
                  child: cards.isEmpty
                      ? _Empty(board: board, onAdd: () => _openEdit())
                      : ReorderableListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                          buildDefaultDragHandles: false,
                          onReorder: board.reorderActive,
                          proxyDecorator: (child, i, anim) => Transform.scale(
                              scale: 1.03, child: Material(color: Colors.transparent, child: child)),
                          itemCount: cards.length,
                          itemBuilder: (context, i) {
                            final c = cards[i];
                            return RopeCard(
                              key: ValueKey(c.id),
                              card: c,
                              store: store,
                              index: i,
                              onOpen: () => _openEdit(c),
                              onToggle: (it) => _onToggle(c, it),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: () => _openEdit(),
            icon: const Icon(Icons.add),
            label: const Text('Kart as'),
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
            Text(board.isProjects ? 'İp boş. İlk firmayı as!' : '${board.name} ipi boş. İlk kartı as!',
                style: TextStyle(fontSize: 16, color: Colors.black54)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
                onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Kart as')),
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
