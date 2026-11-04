import 'package:flutter/material.dart';

import '../data/messages.dart';
import '../data/models.dart';
import '../data/repo.dart';
import '../push/push_service.dart';
import '../reader/reader_service.dart';
import '../theme.dart';
import 'message_template_screen.dart';
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
                if (PushService.supported) ...[_TestPushRow(repo: repo), const Divider()],
                ListTile(
                  title: const Text('Payment deadline'),
                  subtitle: const Text("Alert if a bike hasn't paid in full by then"),
                  trailing: _Value(repo.settings.deadline),
                  onTap: () => _pickDeadline(context),
                ),
                const Divider(),
                ListTile(
                  title: const Text('Day missed alert'),
                  subtitle: const Text("One summary of the bikes that didn't pay in full"),
                  trailing: _Value(repo.settings.missedLabel),
                  onTap: () => _pick<String>(
                    context,
                    title: 'Day missed alert',
                    current: repo.settings.missedAlertOffset,
                    choices: TeamSettings.missedChoices,
                    save: (v) => repo.updateSettings({'missed_alert_offset': v}),
                  ),
                ),
                const Divider(),
                SwitchListTile(
                  title: const Text('Payment notifications'),
                  subtitle: const Text('When a driver pays, by MoMo or cash'),
                  value: repo.settings.paymentPush,
                  onChanged: (on) => _save(context, () => repo.updateSettings({'payment_push': on})),
                ),
                const Divider(),
                SwitchListTile(
                  title: const Text('Overpayment alerts'),
                  subtitle: const Text('When a driver sends more than is owed'),
                  value: repo.settings.overpayAlerts,
                  onChanged: (on) => _save(context, () => repo.updateSettings({'overpay_alerts': on})),
                ),
                const Divider(),
                ListTile(
                  title: const Text('Reader offline alert'),
                  subtitle: Text(
                    'Warns everyone if the MoMo phone stops checking SMS for '
                    '${repo.settings.readerSilenceHours} hours. Never at night: waits until 07:00.',
                  ),
                  trailing: _Value('${repo.settings.readerSilenceHours} h'),
                  onTap: () => _pick<int>(
                    context,
                    title: 'Warn when the MoMo phone is quiet for',
                    current: repo.settings.readerSilenceHours,
                    choices: {for (final h in TeamSettings.silenceChoices) h: '$h hours'},
                    save: (v) => repo.updateSettings({'reader_silence_hours': v}),
                  ),
                ),
              ],
            ),
          ),
          const _Heading('Messages to drivers'),
          Card(
            child: Column(
              children: [
                for (final (i, k) in MessageKind.values.indexed) ...[
                  if (i > 0) const Divider(),
                  ListTile(
                    title: Text(k.label),
                    subtitle: Text(
                      repo.messageTemplates[k]?.kinyarwanda ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right, color: Palette.ink2),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => MessageTemplateScreen(repo: repo, kind: k),
                      ),
                    ),
                  ),
                ],
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
                    subtitle: Text(m.momoNumber == null ? 'No MoMo number yet' : 'MoMo ${m.momoNumber}'),
                    trailing: const Icon(Icons.edit_outlined, size: 20, color: Palette.ink2),
                    onTap: () => _editMomo(context, m),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Motor Track 0.5.1 · MVP',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Palette.ink2),
          ),
        ],
      ),
    ),
  );

  Future<void> _editMomo(BuildContext context, Member m) async {
    final controller = TextEditingController(text: m.momoNumber ?? '');
    final number = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("${m.name}'s MoMo number"),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(hintText: 'e.g. 0788 123 456'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save')),
        ],
      ),
    );
    // Not disposed here: the dialog's closing animation still uses it.
    if (number == null || !context.mounted) return;
    await _save(context, () => repo.setMomoNumber(m.id, number));
  }

  Future<void> _pickDeadline(BuildContext context) async {
    final parts = repo.settings.deadline.split(':');
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
      helpText: 'Payment deadline',
      builder: (context, child) =>
          MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (t == null || !context.mounted) return;
    String two(int n) => n.toString().padLeft(2, '0');
    await _save(context, () => repo.updateSettings({'deadline_time': '${two(t.hour)}:${two(t.minute)}'}));
  }

  Future<void> _pick<T>(
    BuildContext context, {
    required String title,
    required T current,
    required Map<T, String> choices,
    required Future<void> Function(T) save,
  }) async {
    final picked = await showDialog<T>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(title),
        children: [
          for (final e in choices.entries)
            RadioListTile<T>(
              value: e.key,
              groupValue: current,
              title: Text(e.value),
              onChanged: (v) => Navigator.pop(context, v),
            ),
        ],
      ),
    );
    if (picked == null || picked == current || !context.mounted) return;
    await _save(context, () => save(picked));
  }

  static Future<void> _save(BuildContext context, Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Couldn't save. Check your connection and try again.")));
      }
    }
  }
}

class _Value extends StatelessWidget {
  const _Value(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Palette.ink),
  );
}

/// Sends one notification to every phone, to check they all get alerts.
class _TestPushRow extends StatefulWidget {
  const _TestPushRow({required this.repo});
  final Repo repo;

  @override
  State<_TestPushRow> createState() => _TestPushRowState();
}

class _TestPushRowState extends State<_TestPushRow> {
  bool _busy = false;

  Future<void> _send() async {
    setState(() => _busy = true);
    String text;
    try {
      await widget.repo.registerPush();
      final (ready, phones) = await widget.repo.sendTestPush();
      text = !ready
          ? "Notifications aren't switched on in the database yet."
          : phones == 0
          ? 'No phone can receive notifications yet. Open the latest app on each phone.'
          : 'Sent to $phones ${phones == 1 ? 'phone' : 'phones'}. It should arrive in a few seconds.';
    } catch (_) {
      text = "Couldn't send. Check your connection and try again.";
    }
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) => ListTile(
    title: const Text('Test notification'),
    subtitle: const Text('Sends one to every phone on the team'),
    trailing: _busy
        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Palette.ink2))
        : TextButton(onPressed: _send, child: const Text('Send')),
  );
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
