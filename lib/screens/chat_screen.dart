import 'package:flutter/material.dart';
import '../services/assistant.dart';
import '../services/report.dart';
import '../services/store.dart';
import '../widgets/report_card.dart';

class _Msg {
  final String text;
  final bool mine;
  final Report? report;
  final GlobalKey shotKey = GlobalKey(); // rapor görüntüsü için
  _Msg(this.text, this.mine, [this.report]);
}

/// Mesaj ekranı: "Hangi projeler kaldı?" gibi sorulara liste cevabı verir.
class ChatScreen extends StatefulWidget {
  final RackStore store;
  const ChatScreen({super.key, required this.store});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  late final RackAssistant _bot;
  final List<_Msg> _msgs = [];

  static const _quick = [
    'Hangi projeler kaldı?',
    'Neler tamamlandı?',
    'Durum ne?',
    'Kimde ne var?',
    'Sıradaki ne?',
  ];

  @override
  void initState() {
    super.initState();
    _bot = RackAssistant(widget.store);
    _msgs.add(_Msg(
        'Selam! "Hangi projeler kaldı?" diye sorabilirsin, öncelik sırana göre listeleyeyim.',
        false));
  }

  void _send(String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    setState(() {
      _msgs.add(_Msg(t, true));
      final r = _bot.reply(t);
      _msgs.add(_Msg(r.text, false, r.report));
    });
    _ctrl.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  bool _busy = false;

  Future<void> _export(Future<void> Function() job) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Paylaşılamadı: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Tasarlanmış liste + altında Resim / PDF / Metin paylaşım butonları.
  Widget _reportBubble(_Msg m) {
    final r = m.report!;
    Widget btn(IconData icon, String label, Future<void> Function() job) =>
        Expanded(
          child: TextButton.icon(
            onPressed: _busy ? null : () => _export(job),
            icon: Icon(icon, size: 18),
            label: Text(label),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF6B4F2A),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            elevation: 2,
            shadowColor: Colors.black26,
            borderRadius: BorderRadius.circular(18),
            color: Colors.transparent,
            child: RepaintBoundary(
              key: m.shotKey,
              child: ReportCard(report: r),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                btn(Icons.image_outlined, 'Resim',
                    () => ReportExport.sharePng(r, m.shotKey)),
                btn(Icons.picture_as_pdf_outlined, 'PDF',
                    () => ReportExport.sharePdf(r, m.shotKey)),
                btn(Icons.notes, 'Metin', () => ReportExport.shareText(r)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.store.me;
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.all(12),
            itemCount: _msgs.length,
            itemBuilder: (context, i) {
              final m = _msgs[i];
              if (m.report != null) return _reportBubble(m);
              return Align(
                alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.8),
                  decoration: BoxDecoration(
                    color: m.mine ? me.color : const Color(0xFFFFF8E7),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(m.mine ? 16 : 4),
                      bottomRight: Radius.circular(m.mine ? 4 : 16),
                    ),
                  ),
                  child: SelectableText(
                    m.text,
                    style: TextStyle(
                        color: m.mine ? Colors.white : Colors.black87,
                        height: 1.35),
                  ),
                ),
              );
            },
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: _quick
                .map((q) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(label: Text(q), onPressed: () => _send(q)),
                    ))
                .toList(),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _send,
                    decoration: InputDecoration(
                      hintText: 'Bir şey sor...',
                      filled: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                    onPressed: () => _send(_ctrl.text),
                    icon: const Icon(Icons.send)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
