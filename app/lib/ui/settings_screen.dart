import 'package:flutter/material.dart';

import '../data/repo.dart';
import '../theme.dart';

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
          const Card(
            child: ListTile(
              title: Text('Read M-Money SMS on this phone'),
              subtitle: Text('Coming in the Reader milestone.'),
              trailing: Switch(value: false, onChanged: null),
            ),
          ),
          const _Heading('Alerts'),
          Card(
            child: Column(
              children: [
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
            'Motor Track 0.1.0 · MVP',
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
