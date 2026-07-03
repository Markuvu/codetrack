import 'package:flutter/material.dart';

import 'screens/contests_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/flashcards_screen.dart';
import 'screens/leaderboard_screen.dart';
import 'screens/progress_screen.dart';
import 'screens/settings_screen.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  runApp(const CodeTrackApp());
}

class CodeTrackApp extends StatelessWidget {
  const CodeTrackApp({super.key});

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
      home: const HomeShell(),
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

  static const _screens = <Widget>[
    DashboardScreen(),
    ContestsScreen(),
    ProgressScreen(),
    FlashcardsScreen(),
    LeaderboardScreen(),
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
      body: _screens[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profiles'),
          NavigationDestination(icon: Icon(Icons.emoji_events_outlined), label: 'Contests'),
          NavigationDestination(icon: Icon(Icons.show_chart), label: 'Progress'),
          NavigationDestination(icon: Icon(Icons.style_outlined), label: 'Cards'),
          NavigationDestination(icon: Icon(Icons.group_outlined), label: 'Friends'),
        ],
      ),
    );
  }
}
