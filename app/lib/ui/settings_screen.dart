import 'package:flutter/material.dart';

import '../data/repo.dart';
import '../reader/reader_service.dart';
import '../theme.dart';
import 'reader_card.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.repo});
  final Repo repo;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: repo,
    builder: (context, _) => SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
        children: [
          const Text('Settings', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Palette.muteBg,
                child: Text(
                  (repo.me?.name ?? '?').characters.first.toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w700, color: Palette.ink),
                ),
              ),
              title: Text(repo.me?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('This phone'),
            ),
          ),
          const _Heading('Reader'),
          ReaderCard(repo: repo),
          const _Heading('Alerts'),
          Card(
            child: Column(
              children: [
                if (ReaderService.supported) ...[const _NotificationsRow(), const Divider()],
                ListTile(title: const Text('Payment deadline'), trailing: Text(repo.settings.deadline)),
                const Divider(),
                ListTile(
                  title: const Text('Day missed alert'),
                  trailing: Text(_missedLabel(repo.settings.missedAlertOffset)),
                ),
              ],
            ),
          ),
          const _Heading('Team'),
          Card(
            child: Column(
              children: [
                for (final (i, m) in repo.members.indexed) ...[
                  if (i > 0) const Divider(),
                  ListTile(
                    title: Text(m.name),
                    trailing: Text(
                      m.momoNumber == null ? 'no MoMo wallet set' : 'MoMo ${m.momoNumber}',
                      style: const TextStyle(color: Palette.ink2),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Motor Track 0.3.1 · MVP',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Palette.ink2),
          ),
        ],
      ),
    ),
  );

  static String _missedLabel(String offset) => switch (offset) {
    '-01:00:00' => '23:00 same day',
    '00:00:00' => 'Midnight',
    '07:00:00' => '07:00 next day',
    '08:00:00' => '08:00 next day',
    _ => offset,
  };
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.fromLTRB(2, 20, 0, 8), child: SectionLabel(text));
}

/// Whether this phone shows alert notifications, with a way to turn them on.
class _NotificationsRow extends StatefulWidget {
  const _NotificationsRow();

  @override
  State<_NotificationsRow> createState() => _NotificationsRowState();
}

class _NotificationsRowState extends State<_NotificationsRow> with WidgetsBindingObserver {
  bool? _on;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final on = await ReaderService.hasNotificationPermission();
    if (mounted) setState(() => _on = on);
  }

  Future<void> _turnOn() async {
    final on = await ReaderService.requestNotificationPermission();
    // Refused before: Android won't ask again, so open the app's settings.
    if (!on) await ReaderService.openAppSettings();
    await _check();
  }

  @override
  Widget build(BuildContext context) => ListTile(
    title: const Text('Notifications on this phone'),
    trailing: switch (_on) {
      null => const SizedBox.shrink(),
      true => const Text(
        'On',
        style: TextStyle(color: Palette.ok, fontWeight: FontWeight.w600),
      ),
      false => TextButton(onPressed: _turnOn, child: const Text('Turn on')),
    },
  );
}
