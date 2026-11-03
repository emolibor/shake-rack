import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/store.dart';
import '../widgets/people.dart';
import '../widgets/rope_card.dart';

/// İlk açılış: kullanıcı adı zorunlu. Ad girilmeden uygulamaya geçilmez.
class OnboardingScreen extends StatefulWidget {
  final RackStore store;
  const OnboardingScreen({super.key, required this.store});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final TextEditingController _name =
      TextEditingController(text: widget.store.profile.name);
  late String _emoji = widget.store.profile.emoji.isEmpty ? '🙂' : widget.store.profile.emoji;
  late Color _color = widget.store.profile.color;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final n = _name.text.trim();
    if (n.length < 2) return;
    setState(() => _busy = true);
    await widget.store.updateProfile(name: n, emoji: _emoji, color: _color);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final ok = _name.text.trim().length >= 2;
    return Scaffold(
      backgroundColor: const Color(0xFFEFE6D6),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: HangerLogo(size: 76, color: Color(0xFF8B6A3E))),
                  const SizedBox(height: 10),
                  const Text('Shake Rack\'e hoş geldin',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  const Text(
                    'Başlamak için adını gir. Paylaştığın askılıklarda diğerleri seni bu adla görür.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54, height: 1.4),
                  ),
                  const SizedBox(height: 22),
                  Center(
                    child: PersonAvatar(
                      person: Member(id: '', name: _name.text, color: _color, emoji: _emoji),
                      size: 72,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _name,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _go(),
                    decoration: const InputDecoration(
                      labelText: 'Kullanıcı adın',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final e in kProfileEmojis.take(16))
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => setState(() => _emoji = e),
                          child: Container(
                            width: 38,
                            height: 38,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: e == _emoji ? const Color(0xFFFFF0D0) : null,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: e == _emoji ? const Color(0xFF8B6A3E) : Colors.transparent),
                            ),
                            child: Text(e, style: const TextStyle(fontSize: 20)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    children: [
                      for (final c in kMemberPalette)
                        GestureDetector(
                          onTap: () => setState(() => _color = c),
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: c == _color ? Colors.black : Colors.transparent, width: 3),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: ok && !_busy ? _go : null,
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: _busy
                        ? const SizedBox(
                            width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Başla', style: TextStyle(fontSize: 16)),
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
