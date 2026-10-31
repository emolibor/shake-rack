import 'dart:math';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/store.dart';

/// İpe mandalla asılmış kağıt not kartı.
/// Kart rengi: atanmış kişinin rengi (soluk), yoksa krem kağıt.
class RopeCard extends StatelessWidget {
  final CompanyCard card;
  final RackStore store;
  final int index;
  final VoidCallback onOpen;
  final void Function(ProjectItem item) onToggle;

  const RopeCard({
    super.key,
    required this.card,
    required this.store,
    required this.index,
    required this.onOpen,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final assignee = store.memberById(card.assignedTo);
    final paper = assignee != null
        ? Color.lerp(Colors.white, assignee.color, 0.22)!
        : const Color(0xFFFFF8E7);
    // her kart hafif farklı açıda sallansın
    final tilt = ((index * 37) % 7 - 3) * 0.012;
    final remaining = card.remaining.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Transform.rotate(
        angle: tilt,
        alignment: Alignment.topCenter,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            // kağıt
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Material(
                color: paper,
                elevation: 4,
                shadowColor: Colors.black38,
                borderRadius: BorderRadius.circular(6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: onOpen,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                card.name,
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'monospace',
                                  color: Color(0xFF2B2B2B),
                                ),
                              ),
                            ),
                            if (assignee != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: assignee.color,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(assignee.name,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600)),
                              ),
                            const SizedBox(width: 6),
                            ReorderableDragStartListener(
                              index: index,
                              child: const Icon(Icons.drag_indicator,
                                  color: Colors.black38),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...card.items.map((it) => _ItemRow(
                              item: it,
                              who: store.memberById(it.doneBy),
                              onTap: () => onToggle(it),
                            )),
                        if (card.notes.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            card.notes,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                                color: Colors.brown.shade700),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          remaining == 0
                              ? 'Hepsi tamam!'
                              : '$remaining proje kaldı',
                          style: TextStyle(
                              fontSize: 11,
                              color: remaining == 0
                                  ? Colors.green.shade700
                                  : Colors.black45),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // mandal
            Positioned(top: 0, child: _Clothespin(color: assignee?.color)),
          ],
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final ProjectItem item;
  final Member? who;
  final VoidCallback onTap;
  const _ItemRow({required this.item, required this.who, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tickColor = who?.color ?? Colors.grey;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: item.done ? tickColor : Colors.transparent,
                border: Border.all(
                    color: item.done ? tickColor : Colors.black54, width: 1.6),
                borderRadius: BorderRadius.circular(5),
              ),
              child: item.done
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                kShortNames[item.type] ?? item.type,
                style: TextStyle(
                  fontSize: 14.5,
                  decoration: item.done ? TextDecoration.lineThrough : null,
                  color: item.done ? Colors.black45 : const Color(0xFF2B2B2B),
                ),
              ),
            ),
            if (item.done && who != null)
              Text(who!.name,
                  style: TextStyle(fontSize: 11, color: tickColor)),
          ],
        ),
      ),
    );
  }
}

/// Tahta mandal.
class _Clothespin extends StatelessWidget {
  final Color? color;
  const _Clothespin({this.color});
  @override
  Widget build(BuildContext context) {
    final wood = color ?? const Color(0xFFC89B5A);
    return Container(
      width: 16,
      height: 34,
      decoration: BoxDecoration(
        color: wood,
        borderRadius: BorderRadius.circular(3),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2, offset: Offset(0, 1))],
      ),
      child: Center(
        child: Container(width: 6, height: 6,
            decoration: const BoxDecoration(color: Colors.white70, shape: BoxShape.circle)),
      ),
    );
  }
}

/// Ekranın üstünden geçen ip. Hafif sarkık bir eğri çizer.
class RopePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFF6B4F2A)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path()..moveTo(0, 6);
    path.quadraticBezierTo(size.width / 2, 22, size.width, 6);
    canvas.drawPath(path, p);
    // ip dokusu
    final tex = Paint()..color = const Color(0xFF9C7A4A)..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 9) {
      final t = x / size.width;
      final y = 6 + 16 * 4 * t * (1 - t) / 2;
      canvas.drawLine(Offset(x, y - 1.5), Offset(x + 4, y + 1.5), tex);
    }
    // çiviler
    final nail = Paint()..color = Colors.grey.shade700;
    canvas.drawCircle(const Offset(6, 6), 4, nail);
    canvas.drawCircle(Offset(size.width - 6, 6), 4, nail);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Askılık logosu (mandal + ip): uygulama ikonu / splash için.
class HangerLogo extends StatelessWidget {
  final double size;
  final Color color;
  const HangerLogo({super.key, this.size = 48, this.color = Colors.white});
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size, size), painter: _HangerPainter(color));
}

class _HangerPainter extends CustomPainter {
  final Color c;
  _HangerPainter(this.c);
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.width * 0.08
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final w = s.width, h = s.height;
    // kanca
    final hook = Path()
      ..moveTo(w * 0.5, h * 0.42)
      ..lineTo(w * 0.5, h * 0.30)
      ..arcToPoint(Offset(w * 0.5, h * 0.10), radius: Radius.circular(w * 0.1), clockwise: true)
      ..arcToPoint(Offset(w * 0.62, h * 0.20), radius: Radius.circular(w * 0.1), clockwise: true);
    canvas.drawPath(hook, p);
    // üçgen gövde
    final body = Path()
      ..moveTo(w * 0.5, h * 0.42)
      ..lineTo(w * 0.1, h * 0.72)
      ..lineTo(w * 0.9, h * 0.72)
      ..close();
    canvas.drawPath(body, p);
    // asılı kağıt
    final paper = Paint()..color = c.withOpacity(0.85);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.36, h * 0.74, w * 0.28, h * 0.2), Radius.circular(w * 0.03)),
        paper);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Kartlar yan yana / sallanan hissi için küçük rastgele sapma.
double jitter(int seed, double amp) => (Random(seed).nextDouble() - 0.5) * amp;
