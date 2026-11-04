import 'dart:async';

import 'package:flutter/material.dart';

import '../data/repo.dart';
import '../reader/reader_service.dart';
import '../theme.dart';
import 'reader_setup_screen.dart';

/// Settings → Reader: this phone's Reader, and every Reader on the team.
class ReaderCard extends StatefulWidget {
  const ReaderCard({super.key, required this.repo});
  final Repo repo;

  @override
  State<ReaderCard> createState() => _ReaderCardState();
}

class _ReaderCardState extends State<ReaderCard> {
  ReaderStatus? _status;
  bool _busy = false;

  Repo get repo => widget.repo;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (!ReaderService.supported) return;
    final s = await ReaderService.status();
    if (mounted) setState(() => _status = s);
  }

  Future<void> _setUp() async {
    final on = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => ReaderSetupScreen(repo: repo)));
    if (on == true) await _refresh();
  }

  Future<void> _turnOff() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Turn off the Reader on this phone?'),
        content: const Text('New M-Money payments to this phone will no longer be recorded automatically.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Turn off')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ReaderService.disable();
      await repo.disableReader();
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refresh();
    }
  }

  Future<void> _checkNow() async {
    setState(() => _busy = true);
    await ReaderService.runNow();
    // The check runs in the background; look again shortly.
    await Future<void>.delayed(const Duration(seconds: 4));
    await _refresh();
    await repo.load();
    if (mounted) setState(() => _busy = false);
  }

  static String ago(DateTime? t) {
    if (t == null) return 'never';
    final m = DateTime.now().difference(t).inMinutes;
    if (m < 1) return 'just now';
    if (m < 60) return '$m min ago';
    if (m < 60 * 24) return '${m ~/ 60} h ago';
    return '${m ~/ (60 * 24)} days ago';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: repo,
    builder: (context, _) {
      final readers = repo.devices.where((d) => d.isReader).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(child: ReaderService.supported ? _thisPhone() : _notAndroid()),
          if (readers.isNotEmpty) ...[
            const Padding(padding: EdgeInsets.fromLTRB(2, 20, 0, 8), child: SectionLabel('Team readers')),
            Card(
              child: Column(
                children: [
                  for (final (i, d) in readers.indexed) ...[
                    if (i > 0) const Divider(),
                    ListTile(
                      leading: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: _quiet(d.lastCheckedAt) ? Palette.bad : Palette.ok,
                          shape: BoxShape.circle,
                        ),
                      ),
                      minLeadingWidth: 10,
                      title: Text(
                        '${repo.memberName(d.memberId)}\'s phone${d.id == repo.deviceId ? ' (this one)' : ''}',
                      ),
                      subtitle: d.unreadableCount > 0
                          ? Text(
                              '${d.unreadableCount} M-Money message${d.unreadableCount == 1 ? '' : 's'} couldn\'t be read',
                              style: const TextStyle(color: Palette.warn),
                            )
                          : null,
                      trailing: Text(
                        'checked ${ago(d.lastCheckedAt?.toLocal())}',
                        style: const TextStyle(color: Palette.ink2),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      );
    },
  );

  static bool _quiet(DateTime? t) => t == null || DateTime.now().difference(t) > const Duration(hours: 6);

  Widget _notAndroid() => const ListTile(
    title: Text('Read M-Money SMS on this phone'),
    subtitle: Text('The Reader only works on Android phones.'),
  );

  Widget _thisPhone() {
    final s = _status;
    final on = (s?.enabled ?? false) && (repo.myDevice?.isReader ?? false);
    final (dot, line) = !on
        ? (Palette.ink3, 'Off')
        : s!.lastError != null
        ? (Palette.warn, s.lastError!)
        : (Palette.ok, 'On · checked ${ago(s.lastRun?.toLocal())}${s.lastResult == null ? '' : ' · ${s.lastResult}'}');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Read M-Money SMS on this phone',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            line,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: dot == Palette.ink3 ? Palette.ink2 : dot,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Switch(value: on, onChanged: _busy ? null : (v) => v ? _setUp() : _turnOff()),
            ],
          ),
        ),
        if (on) ...[
          const Divider(),
          _Row('Sender', s!.sender ?? '-'),
          const Divider(),
          _Row('Payments sent from this phone', '${s.uploadedTotal}'),
          if (s.queued > 0) ...[const Divider(), _Row('Waiting for internet', '${s.queued}')],
          if (s.unreadable > 0) ...[
            const Divider(),
            _Row(
              'Couldn\'t read',
              '${s.unreadable} message${s.unreadable == 1 ? '' : 's'}',
              note: 'If M-Money changed its wording, set the Reader up again.',
              warn: true,
            ),
          ],
          if (!s.hasSmsPermission) ...[
            const Divider(),
            _Row('SMS permission', 'Off', warn: true, action: ('Fix', ReaderService.openAppSettings)),
          ],
          const Divider(),
          _Row(
            'Battery saver',
            s.ignoringBatteryOptimizations ? 'Off for this app' : 'On',
            good: s.ignoringBatteryOptimizations,
            warn: !s.ignoringBatteryOptimizations,
            action: s.ignoringBatteryOptimizations
                ? null
                : (
                    'Fix',
                    () async {
                      await ReaderService.requestIgnoreBatteryOptimizations();
                      unawaited(Future<void>.delayed(const Duration(seconds: 2), _refresh));
                    },
                  ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : _checkNow,
                    child: _busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Check now'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(onPressed: _busy ? null : _setUp, child: const Text('Set up again')),
                ),
              ],
            ),
          ),
        ] else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Turn this on for the phone whose MoMo number drivers pay into. Only payments from registered drivers are shared with the team.',
                  style: TextStyle(fontSize: 14, color: Palette.ink2, height: 1.45),
                ),
                const SizedBox(height: 12),
                FilledButton(onPressed: _busy ? null : _setUp, child: const Text('Set up Reader')),
              ],
            ),
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.note, this.warn = false, this.good = false, this.action});
  final String label;
  final String value;
  final String? note;
  final bool warn;
  final bool good;
  final (String, VoidCallback)? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 15)),
              if (note != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(note!, style: const TextStyle(fontSize: 12, color: Palette.ink2)),
                ),
            ],
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: good || warn ? FontWeight.w600 : FontWeight.w400,
            color: good ? Palette.ok : (warn ? Palette.warn : Palette.ink2),
          ),
        ),
        if (action != null) TextButton(onPressed: action!.$2, child: Text(action!.$1)) else const SizedBox(width: 8),
      ],
    ),
  );
}
