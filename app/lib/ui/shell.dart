import 'package:flutter/material.dart';

import '../data/repo.dart';
import '../reader/reader_service.dart';
import '../theme.dart';
import 'home_screen.dart';
import 'settings_screen.dart';

/// Bottom navigation: Home, Reports, Deposits, Settings.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.repo});
  final Repo repo;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkInbox();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back in the app: refresh, and let this phone's Reader check the inbox.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    widget.repo.load();
    _checkInbox();
  }

  void _checkInbox() {
    if (ReaderService.supported) ReaderService.runNow().catchError((Object _) => false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(
      index: _tab,
      children: [
        HomeScreen(repo: widget.repo),
        const _ComingSoon(
          icon: Icons.bar_chart,
          title: 'Reports',
          text:
              'Collection and deposit reports are the next milestones. Payments are already being recorded, so the reports will cover them.',
        ),
        const _ComingSoon(
          icon: Icons.account_balance,
          title: 'Deposits',
          text: 'Recording bank deposits comes in a later milestone.',
        ),
        SettingsScreen(repo: widget.repo),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: (i) => setState(() => _tab = i),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
        NavigationDestination(
          icon: Icon(Icons.bar_chart_outlined),
          selectedIcon: Icon(Icons.bar_chart),
          label: 'Reports',
        ),
        NavigationDestination(
          icon: Icon(Icons.account_balance_outlined),
          selectedIcon: Icon(Icons.account_balance),
          label: 'Deposits',
        ),
        NavigationDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune), label: 'Settings'),
      ],
    ),
  );
}

class _ComingSoon extends StatelessWidget {
  const _ComingSoon({required this.icon, required this.title, required this.text});
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      children: [
        Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        const SizedBox(height: 40),
        Icon(icon, size: 44, color: Palette.ink3),
        const SizedBox(height: 12),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Palette.ink2, height: 1.45),
        ),
      ],
    ),
  );
}
