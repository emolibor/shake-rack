import 'package:flutter/material.dart';
import '../services/assistant.dart';
import '../services/store.dart';

class _Msg {
  final String text;
  final bool mine;
  _Msg(this.text, this.mine);
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
      _msgs.add(_Msg(_bot.answer(t), false));
    });
    _ctrl.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
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
