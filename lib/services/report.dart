import 'package:flutter/material.dart';

/// Rapor türü: kalanlar (turuncu etiketler) ya da bitenler (yeşil etiketler).
enum ReportStyle { remaining, done }

/// Rapordaki bir satır = bir firma.
class ReportRow {
  final String title;
  final String? owner;
  final Color? ownerColor;
  final List<String> items; // gösterilecek proje etiketleri
  final int done; // firmanın biten proje sayısı
  final int total; // firmanın toplam proje sayısı

  const ReportRow({
    required this.title,
    required this.items,
    this.owner,
    this.ownerColor,
    this.done = 0,
    this.total = 0,
  });
}

/// Sohbetteki "tasarlanmış liste". Kart olarak çizilir, PNG/PDF/metin
/// olarak paylaşılabilir.
class Report {
  final String title;
  final String subtitle;
  final String summary;
  final ReportStyle style;
  final List<ReportRow> rows;
  final DateTime date;

  Report({
    required this.title,
    required this.subtitle,
    required this.summary,
    required this.rows,
    this.style = ReportStyle.remaining,
    DateTime? date,
  }) : date = date ?? DateTime.now();

  String get dateText =>
      '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';

  /// Dosya adı için güvenli kısa ad: "kalan-projeler-31-10-2026"
  String get fileBase {
    const tr = {'ı': 'i', 'ş': 's', 'ğ': 'g', 'ü': 'u', 'ö': 'o', 'ç': 'c'};
    var s = title.toLowerCase();
    tr.forEach((k, v) => s = s.replaceAll(k, v));
    s = s.replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
    return '$s-${dateText.replaceAll('.', '-')}';
  }

  /// WhatsApp'a yapıştırılabilir düz metin.
  String toText() {
    final b = StringBuffer('*$title*\n$subtitle · $dateText\n\n');
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final owner = r.owner != null ? ' (${r.owner})' : '';
      b.writeln('${i + 1}. *${r.title}*$owner');
      if (r.items.isNotEmpty) b.writeln('   ${r.items.join(' · ')}');
    }
    b.write('\n$summary');
    return b.toString();
  }
}

/// Asistanın cevabı: her zaman metin, uygun sorularda ayrıca rapor.
class AssistantReply {
  final String text;
  final Report? report;
  const AssistantReply(this.text, [this.report]);
}
