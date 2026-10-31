import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../services/report.dart';
import 'rope_card.dart';

const _brown = Color(0xFF8B6A3E);
const _brownDark = Color(0xFF6B4F2A);
const _paper = Color(0xFFFFFCF5);
const _ink = Color(0xFF2B2B2B);

/// Sohbetteki tasarlanmış liste. RepaintBoundary ile sarılıdır; aynı görüntü
/// PNG ve PDF olarak dışa aktarılır.
class ReportCard extends StatelessWidget {
  final Report report;
  const ReportCard({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final r = report;
    return Container(
      decoration: BoxDecoration(
        color: _paper,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8DCC6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---- başlık ----
          Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_brown, _brownDark],
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: HangerLogo(size: 34),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('SHAKE RACK',
                          style: TextStyle(
                              color: Colors.white60,
                              fontSize: 10,
                              letterSpacing: 2,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(r.title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              height: 1.15,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(r.subtitle,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12.5)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(r.dateText,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          // ---- özet ----
          Container(
            color: const Color(0xFFF4ECDD),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            child: Row(
              children: [
                Icon(
                    r.style == ReportStyle.done
                        ? Icons.task_alt
                        : Icons.pending_actions,
                    size: 16,
                    color: _brownDark),
                const SizedBox(width: 6),
                Text(r.summary,
                    style: const TextStyle(
                        color: _brownDark,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          // ---- satırlar ----
          for (var i = 0; i < r.rows.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, indent: 18, endIndent: 18, color: Color(0xFFEDE3D1)),
            _Row(index: i, row: r.rows[i], style: r.style),
          ],
          // ---- alt bilgi ----
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
            child: Text('Shake Rack ile hazırlandı · ${r.dateText}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10, color: Colors.black38)),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final int index;
  final ReportRow row;
  final ReportStyle style;
  const _Row({required this.index, required this.row, required this.style});

  @override
  Widget build(BuildContext context) {
    final done = style == ReportStyle.done;
    final chipBg = done ? const Color(0xFFE2F3E5) : const Color(0xFFFFEBDB);
    final chipFg = done ? const Color(0xFF2E7D32) : const Color(0xFFA0521D);
    final progress = row.total == 0 ? 0.0 : row.done / row.total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 18, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: index == 0 && !done ? _brown : Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(color: _brown, width: 1.6),
            ),
            child: Text('${index + 1}',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: index == 0 && !done ? Colors.white : _brown)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(row.title,
                          style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                              color: _ink)),
                    ),
                    if (row.owner != null)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: (row.ownerColor ?? Colors.grey).withOpacity(0.14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                                radius: 3.5,
                                backgroundColor: row.ownerColor ?? Colors.grey),
                            const SizedBox(width: 4),
                            Text(row.owner!,
                                style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: row.ownerColor ?? Colors.grey)),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    for (final it in row.items)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: chipBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(done ? Icons.check : Icons.radio_button_unchecked,
                                size: 11, color: chipFg),
                            const SizedBox(width: 4),
                            Text(it,
                                style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: chipFg)),
                          ],
                        ),
                      ),
                  ],
                ),
                if (row.total > 0) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 5,
                            backgroundColor: const Color(0xFFEDE3D1),
                            valueColor: const AlwaysStoppedAnimation(Color(0xFF4CAF50)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${row.done}/${row.total} bitti',
                          style: const TextStyle(fontSize: 10.5, color: Colors.black45)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Rapor kartını PNG / PDF / metin olarak paylaşır.
class ReportExport {
  /// Kartın ekran görüntüsü (yüksek çözünürlük).
  static Future<(Uint8List, int, int)> _capture(GlobalKey key) async {
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3.5);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return (data!.buffer.asUint8List(), image.width, image.height);
  }

  static Future<File> _write(String name, List<int> bytes) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$name');
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  static Future<void> sharePng(Report r, GlobalKey key) async {
    final (png, _, __) = await _capture(key);
    final f = await _write('${r.fileBase}.png', png);
    await Share.shareXFiles([XFile(f.path, mimeType: 'image/png')],
        subject: r.title);
  }

  static Future<void> sharePdf(Report r, GlobalKey key) async {
    final (png, w, h) = await _capture(key);
    // A4 genişliğinde, rapor boyunda tek sayfa (kenar boşluklu)
    const pageW = 595.0, margin = 28.0;
    final imgW = pageW - margin * 2;
    final imgH = imgW * h / w;
    final doc = pw.Document(title: r.title, author: 'Shake Rack');
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat(pageW, imgH + margin * 2, marginAll: margin),
      build: (_) => pw.Image(pw.MemoryImage(png), width: imgW, height: imgH),
    ));
    final f = await _write('${r.fileBase}.pdf', await doc.save());
    await Share.shareXFiles([XFile(f.path, mimeType: 'application/pdf')],
        subject: r.title);
  }

  static Future<void> shareText(Report r) =>
      Share.share(r.toText(), subject: r.title);
}
