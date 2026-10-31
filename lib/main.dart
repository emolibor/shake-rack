import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'screens/chat_screen.dart';
import 'screens/completed_screen.dart';
import 'screens/history_screen.dart';
import 'screens/racks_page.dart';
import 'screens/team_screen.dart';
import 'services/store.dart';
import 'services/updater.dart';
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
        // 5 sekmede etiketler tek satıra sığsın
        navigationBarTheme: const NavigationBarThemeData(
          labelTextStyle: WidgetStatePropertyAll(
              TextStyle(fontSize: 12, fontWeight: FontWeight.w500, overflow: TextOverflow.ellipsis)),
        ),
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

  @override
  void initState() {
    super.initState();
    store.firebaseReady = firebaseReady;
    store.load().then((_) {
      setState(() => _loaded = true);
      _checkUpdate();
    });
  }

  /// Açılışta sessizce yeni sürüm var mı bak; varsa sor.
  Future<void> _checkUpdate() async {
    final info = await Updater.check();
    if (info == null || !mounted) return;
    await showUpdateDialog(context, info);
  }

  /// Seçili sekme (anahtar ile: Mesaj sekmesi gizlenince kayma olmasın).
  String _tabKey = 'rack';

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(
        body: Center(child: HangerLogo(size: 96, color: Color(0xFF8B6A3E))),
      );
    }
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) => _scaffold(context),
    );
  }

  Widget _scaffold(BuildContext context) {
    final doneCount = store.boards.fold<int>(0, (s, b) => s + b.completed.length);
    // (anahtar, başlık, sayfa, alt menü öğesi)
    final tabs = <(String, String, Widget, NavigationDestination)>[
      ('rack', 'Shake Rack', RacksPage(key: const ValueKey('rack'), store: store),
          const NavigationDestination(icon: Icon(Icons.checkroom), label: 'Askılık')),
      ('done', 'Tamamlananlar',
          CompletedScreen(key: const ValueKey('done'), store: store),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: doneCount > 0,
              label: Text('$doneCount'),
              child: const Icon(Icons.emoji_events_outlined),
            ),
            label: 'Bitenler',
          )),
      ('history', 'Geçmiş', HistoryScreen(key: const ValueKey('history'), store: store),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _tabKey != 'history' && store.unseenActivities > 0,
              label: Text('${store.unseenActivities}'),
              child: const Icon(Icons.history),
            ),
            label: 'Geçmiş',
          )),
      // proje sohbeti sadece Projeler askılığı varken
      if (!store.projectsHidden)
        ('chat', 'Mesaj', ChatScreen(key: const ValueKey('chat'), store: store),
            const NavigationDestination(
                icon: Icon(Icons.chat_bubble_outline), label: 'Mesaj')),
      ('profile', 'Profil', TeamScreen(key: const ValueKey('profile'), store: store),
          const NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profil')),
    ];
    var index = tabs.indexWhere((e) => e.$1 == _tabKey);
    if (index < 0) index = 0;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF8B6A3E),
        foregroundColor: Colors.white,
        title: Row(
          children: [
            const HangerLogo(size: 28),
            const SizedBox(width: 10),
            Flexible(
              child: Text(tabs[index].$2, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        actions: [
          if (store.syncing)
            Tooltip(
              message: '${store.projects.name}: ${store.syncStatus}',
              child: Icon(
                store.syncStatus == 'Eşitlendi'
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_sync_outlined,
                size: 20,
                color: Colors.white70,
              ),
            ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Chip(
              avatar: CircleAvatar(
                  backgroundColor:
                      store.hasProfile ? store.profile.color : store.me.color,
                  radius: 8),
              label: Text(store.hasProfile ? store.profile.name : store.me.name,
                  style: const TextStyle(fontSize: 12)),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
      body: IndexedStack(index: index, children: [for (final e in tabs) e.$3]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) {
          final key = tabs[i].$1;
          if (_tabKey == 'history' || key == 'history') store.markHistorySeen();
          setState(() => _tabKey = key);
        },
        destinations: [for (final e in tabs) e.$4],
      ),
    );
  }
}
