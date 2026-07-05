import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'screens/auth_screen.dart';
import 'screens/contests_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/flashcards_screen.dart';
import 'screens/leaderboard_screen.dart';
import 'screens/progress_screen.dart';
import 'screens/settings_screen.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Local notifications are not supported in the browser.
  if (!kIsWeb) {
    await NotificationService.instance.init();
  }
  final loggedIn = await AuthService.instance.isLoggedIn();
  runApp(CodeTrackApp(loggedIn: loggedIn));
}

class CodeTrackApp extends StatelessWidget {
  const CodeTrackApp({super.key, required this.loggedIn});

  final bool loggedIn;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CodeTrack',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6C5CE7),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: loggedIn ? const HomeShell() : const AuthScreen(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  // Built lazily so the dashboard can jump to other tabs (e.g. "View all"
  // on the contests preview switches to the Contests tab).
  late final List<Widget> _screens = <Widget>[
    DashboardScreen(onOpenContests: () => setState(() => _index = 1)),
    const ContestsScreen(),
    const ProgressScreen(),
    const FlashcardsScreen(),
    const LeaderboardScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CodeTrack'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      // IndexedStack keeps every tab's state alive across switches: the
      // dashboard doesn't refetch (so its card order never flickers), and
      // scroll positions / filters on other tabs are preserved too.
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.emoji_events_outlined), label: 'Contests'),
          NavigationDestination(icon: Icon(Icons.show_chart), label: 'Progress'),
          NavigationDestination(icon: Icon(Icons.style_outlined), label: 'Cards'),
          NavigationDestination(icon: Icon(Icons.group_outlined), label: 'Friends'),
        ],
      ),
    );
  }
}
