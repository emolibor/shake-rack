import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'screens/chat_screen.dart';
import 'screens/completed_screen.dart';
import 'screens/rack_screen.dart';
import 'screens/team_screen.dart';
import 'services/store.dart';
import 'widgets/rope_card.dart';

/// Firebase kurulduysa true. Kurulmadıysa uygulama yine çalışır, sadece yerel.
bool firebaseReady = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
    firebaseReady = true;
  } catch (e) {
    debugPrint('Firebase başlatılamadı, yerel modda: $e');
  }
  runApp(const ShakeRackApp());
}

class ShakeRackApp extends StatelessWidget {
  const ShakeRackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shake Rack',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF8B6A3E),
        scaffoldBackgroundColor: const Color(0xFFEFE6D6),
      ),
      home: const _Home(),
    );
  }
}

class _Home extends StatefulWidget {
  const _Home();
  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  final store = RackStore();
  bool _loaded = false;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    store.firebaseReady = firebaseReady;
    store.load().then((_) => setState(() => _loaded = true));
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(
        body: Center(child: HangerLogo(size: 96, color: Color(0xFF8B6A3E))),
      );
    }
    final pages = [
      RackScreen(store: store),
      CompletedScreen(store: store),
      ChatScreen(store: store),
      TeamScreen(store: store),
    ];
    const titles = ['Askılık', 'Tamamlananlar', 'Mesaj', 'Ekip'];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF8B6A3E),
        foregroundColor: Colors.white,
        title: Row(
          children: [
            const HangerLogo(size: 28),
            const SizedBox(width: 10),
            Flexible(
              child: Text(_tab == 0 ? 'Shake Rack' : titles[_tab],
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        actions: [
          AnimatedBuilder(
            animation: store,
            builder: (_, __) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: store.syncStatus,
                  child: Icon(
                    store.syncing
                        ? (store.syncStatus == 'Eşitlendi'
                            ? Icons.cloud_done_outlined
                            : Icons.cloud_sync_outlined)
                        : Icons.cloud_off_outlined,
                    size: 20,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(
                avatar: CircleAvatar(backgroundColor: store.me.color, radius: 8),
                label: Text(store.me.name, style: const TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
              ),
            ),
              ],
            ),
          ),
        ],
      ),
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.checkroom), label: 'Askılık'),
          NavigationDestination(
            icon: AnimatedBuilder(
              animation: store,
              builder: (_, __) => Badge(
                isLabelVisible: store.completed.isNotEmpty,
                label: Text('${store.completed.length}'),
                child: const Icon(Icons.emoji_events_outlined),
              ),
            ),
            label: 'Tamamlanan',
          ),
          const NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: 'Mesaj'),
          const NavigationDestination(icon: Icon(Icons.group_outlined), label: 'Ekip'),
        ],
      ),
    );
  }
}
