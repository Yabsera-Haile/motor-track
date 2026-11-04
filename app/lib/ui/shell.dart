import 'dart:async';

import 'package:flutter/material.dart';

import '../data/repo.dart';
import '../push/push_service.dart';
import '../reader/reader_service.dart';
import 'alerts_screen.dart';
import 'deposits_screen.dart';
import 'home_screen.dart';
import 'message_driver_sheet.dart';
import 'reports_screen.dart';
import 'vehicle_detail_screen.dart';
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
    widget.repo.registerPush();
    PushService.onOpened(_handleNotificationTap);
    // Opened by tapping a notification.
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleNotificationTap());
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
    widget.repo.registerPush();
  }

  bool _opening = false;

  Future<void> _handleNotificationTap() async {
    if (_opening) return;
    _opening = true;
    try {
      final action = await PushService.takeOpenAction();
      if (action == null || !mounted) return;
      final nav = Navigator.of(context);
      // Start from Home, so Back from the alert leads somewhere sensible.
      nav.popUntil((r) => r.isFirst);
      setState(() => _tab = 0);
      if (action.open == 'home') return;
      final repo = widget.repo;
      if (action.open == 'vehicle') {
        if (repo.vehicleById(action.vehicleId) != null) {
          unawaited(
            nav.push(
              MaterialPageRoute<void>(
                builder: (_) => VehicleDetailScreen(repo: repo, vehicleId: action.vehicleId!),
              ),
            ),
          );
        }
        return;
      }
      unawaited(nav.push(MaterialPageRoute<void>(builder: (_) => AlertsScreen(repo: repo))));
      if (action.open == 'message' && action.alertId != null) {
        final alert = await repo.alert(action.alertId!);
        if (alert != null && mounted) await showMessageDriverForAlert(nav.context, repo, alert);
      }
    } catch (e) {
      debugPrint('notification tap failed: $e');
    } finally {
      _opening = false;
    }
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
        ReportsScreen(repo: widget.repo, visible: _tab == 1),
        DepositsScreen(repo: widget.repo),
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
