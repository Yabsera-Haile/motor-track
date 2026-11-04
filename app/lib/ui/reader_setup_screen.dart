import 'package:flutter/material.dart';

import '../config.dart';
import '../data/repo.dart';
import '../format.dart';
import '../reader/reader_service.dart';
import '../reader/sms_template.dart';
import '../theme.dart';

/// The four Reader setup steps from the design: permissions, sender, message
/// format, then wallet and catch-up. Pops with true once the Reader is on.
class ReaderSetupScreen extends StatefulWidget {
  const ReaderSetupScreen({super.key, required this.repo});
  final Repo repo;

  @override
  State<ReaderSetupScreen> createState() => _ReaderSetupScreenState();
}

const _fieldColors = {
  'amount': Color(0xFFDCE6FF),
  'name': Color(0xFFFCE7C8),
  'phone': Color(0xFFE3E6EA),
  'datetime': Color(0xFFE6F4EC),
  'txid': Color(0xFFEDE4FB),
  'skip': Color(0xFFF4F5F7),
};

const _fieldLabels = {
  'amount': 'Amount',
  'name': 'MoMo username',
  'phone': 'Phone ending',
  'datetime': 'Date and time',
  'skip': 'Balance',
  'txid': 'Transaction ID',
};

class _ReaderSetupScreenState extends State<ReaderSetupScreen> with WidgetsBindingObserver {
  int _step = 0;

  // Step 1: permissions.
  bool _sms = false;
  bool _battery = false;
  bool _smsRefused = false;

  // Step 2: sender.
  Future<List<SmsSender>>? _senders;
  String? _sender;

  // Step 3: message format.
  List<InboxSms> _messages = const [];
  bool _loadingMessages = false;
  InboxSms? _sample;
  SmsTemplate? _template;
  String _selected = 'name';
  bool _fixing = false;
  final _fix = {for (final f in _fieldLabels.keys) f: TextEditingController()};
  String? _fixError;

  // Step 4: wallet and catch-up.
  late final _momo = TextEditingController(text: widget.repo.me?.momoNumber ?? '');
  List<CatchUpItem> _catchUp = const [];
  bool _import = true;
  bool _saving = false;
  String? _error;

  Repo get repo => widget.repo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _momo.dispose();
    for (final c in _fix.values) {
      c.dispose();
    }
    super.dispose();
  }

  // Coming back from Android settings: check again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final sms = await ReaderService.hasSmsPermission();
    final battery = await ReaderService.isIgnoringBatteryOptimizations();
    if (!mounted) return;
    setState(() {
      _sms = sms;
      _battery = battery;
    });
  }

  Future<void> _go(int step) async {
    setState(() => _step = step);
    if (step == 1) {
      _senders ??= ReaderService.listSenders().then((list) {
        _sender ??= _guessSender(list);
        if (mounted) setState(() {});
        return list;
      });
    } else if (step == 2) {
      await _loadMessages();
    } else if (step == 3) {
      final since = DateTime.now().toUtc().subtract(const Duration(days: 30));
      setState(() => _catchUp = findCatchUp(_messages, _template!, repo.vehicles, since));
    }
  }

  static String? _guessSender(List<SmsSender> list) {
    final money = list.where((s) => RegExp(r'm-?money|momo', caseSensitive: false).hasMatch(s.address));
    if (money.isNotEmpty) return money.first.address;
    final incoming = list.where((s) => SmsTemplate.looksLikeIncoming(s.latestBody));
    return incoming.isNotEmpty ? incoming.first.address : (list.isEmpty ? null : list.first.address);
  }

  Future<void> _loadMessages() async {
    setState(() => _loadingMessages = true);
    final messages = await ReaderService.messages(_sender!, limit: 500);
    InboxSms? sample;
    SmsTemplate? template;
    for (final m in messages) {
      if (SmsTemplate.mtnDefault.parse(m.body) != null) {
        sample = m;
        template = SmsTemplate.mtnDefault;
        break;
      }
    }
    sample ??= messages.where((m) => SmsTemplate.looksLikeIncoming(m.body)).firstOrNull ?? messages.firstOrNull;
    if (!mounted) return;
    setState(() {
      _messages = messages;
      _sample = sample;
      _template = template;
      _fixing = template == null && sample != null;
      _loadingMessages = false;
    });
    if (template == null) _prefillFix();
  }

  void _pickSample(InboxSms m) {
    // Keep the current format if it reads this message, else try MTN's, else fix by hand.
    final t = [
      _template,
      SmsTemplate.mtnDefault,
    ].whereType<SmsTemplate>().where((t) => t.parse(m.body) != null).firstOrNull;
    setState(() {
      _sample = m;
      _template = t;
      _fixing = t == null;
      _fixError = null;
    });
    _prefillFix();
  }

  void _prefillFix() {
    final raw = _template?.rawFields(_sample?.body ?? '') ?? const {};
    for (final e in _fix.entries) {
      e.value.text = raw[e.key] ?? '';
    }
    // The balance is not captured by the template, so find it next to "Balance".
    final balance = RegExp(r'Balance\s*:?\s*([0-9][0-9,.]*)', caseSensitive: false).firstMatch(_sample?.body ?? '');
    if (balance != null) _fix['skip']!.text = balance.group(1)!;
  }

  void _applyFix() {
    final body = _sample!.body;
    final fields = {
      for (final e in _fix.entries)
        if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
    };
    for (final need in const ['amount', 'name', 'txid']) {
      if (!fields.containsKey(need)) {
        setState(() => _fixError = 'Fill in ${_fieldLabels[need]!.toLowerCase()}.');
        return;
      }
    }
    for (final e in fields.entries) {
      if (!body.contains(e.value)) {
        setState(() => _fixError = '"${e.value}" isn\'t in the message. Copy it exactly as it appears.');
        return;
      }
    }
    try {
      final t = SmsTemplate.fromSample(body, fields);
      if (t.parse(body) == null) throw ArgumentError('no match');
      setState(() {
        _template = t;
        _fixing = false;
        _fixError = null;
      });
    } catch (_) {
      setState(() => _fixError = 'That doesn\'t work. Make sure the fields are in the same order as in the message.');
    }
  }

  Future<void> _finish() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await repo.setMyMomoNumber(_momo.text);
      final templateId = await repo.saveTemplate(sender: _sender!, pattern: _template!.pattern, sample: _sample!.body);
      final key = await repo.enableReader(sender: _sender!, templateId: templateId);
      await ReaderService.configure(
        url: Config.supabaseUrl,
        publishableKey: Config.supabasePublishableKey,
        readerKey: key,
        sender: _sender!,
        template: _template!,
        usernames: repo.allUsernames,
        checkpoint: DateTime.now(),
      );
      var imported = 0;
      if (_import) {
        for (final item in _catchUp) {
          if (await repo.importPayment(item) == 'inserted') imported++;
        }
      }
      await repo.load();
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            imported > 0
                ? 'Reader is on. Imported $imported past payment${imported == 1 ? '' : 's'}.'
                : 'Reader is on. New M-Money payments will be recorded automatically.',
          ),
        ),
      );
    } catch (e) {
      setState(() => _error = 'Couldn\'t turn the Reader on. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (body, canContinue, next) = switch (_step) {
      0 => (_permissionsStep(), _sms, 'Continue'),
      1 => (_senderStep(), _sender != null, 'Continue'),
      2 => (_formatStep(), _template != null && !_fixing, 'Looks right'),
      _ => (_finishStep(), !_saving, 'Turn on Reader'),
    };
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _step--);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Reader setup'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text('Step ${_step + 1} of 4', style: const TextStyle(fontSize: 13, color: Palette.ink2)),
              ),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Row(
                children: [
                  for (var i = 0; i < 4; i++)
                    Expanded(
                      child: Container(
                        height: 4,
                        margin: EdgeInsets.only(left: i == 0 ? 0 : 4),
                        decoration: BoxDecoration(
                          color: i <= _step ? Palette.ink : Palette.control,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(child: body),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    if (_step == 2 && _sample != null && !_fixing) ...[
                      Expanded(
                        child: OutlinedButton(onPressed: _chooseOtherMessage, child: const Text('Other message')),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: canContinue ? (_step == 3 ? _finish : () => _go(_step + 1)) : null,
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Palette.ink2),
                              )
                            : Text(next),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Step 1 ----

  Widget _permissionsStep() => ListView(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
    children: [
      const Text(
        'Read M-Money on this phone',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.2),
      ),
      const SizedBox(height: 8),
      const Text(
        'Turn this on for the phone whose MoMo number drivers pay into. It reads M-Money messages and records '
        'payments from your registered drivers automatically. Your other messages stay on this phone.',
        style: TextStyle(fontSize: 15, color: Palette.ink2, height: 1.45),
      ),
      const SizedBox(height: 20),
      _PermissionRow(
        title: 'Read SMS',
        text: 'Needed to see M-Money messages.',
        done: _sms,
        onAllow: () async {
          final ok = await ReaderService.requestSmsPermission();
          setState(() {
            _sms = ok;
            _smsRefused = !ok;
          });
        },
      ),
      if (_smsRefused && !_sms)
        Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Palette.warnBg, borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Android didn\'t allow it. Open App info, tap ⋮ at the top right and choose "Allow restricted settings" '
                'if you see it, then go to Permissions → SMS → Allow.',
                style: TextStyle(fontSize: 14, color: Palette.warn, height: 1.45, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 10),
              OutlinedButton(onPressed: ReaderService.openAppSettings, child: const Text('Open App info')),
            ],
          ),
        ),
      const SizedBox(height: 10),
      _PermissionRow(
        title: 'Battery saver off for this app',
        text: 'Phones like Tecno, Infinix and Samsung stop apps in the background. This keeps the Reader checking.',
        done: _battery,
        onAllow: ReaderService.requestIgnoreBatteryOptimizations,
      ),
    ],
  );

  // ---- Step 2 ----

  Widget _senderStep() => FutureBuilder<List<SmsSender>>(
    future: _senders,
    builder: (context, snap) {
      if (snap.hasError) {
        return const Center(child: Text('Couldn\'t read the SMS inbox. Check the SMS permission.'));
      }
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final list = snap.data!;
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        children: [
          const Text(
            'Who sends your MoMo messages?',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.2),
          ),
          const SizedBox(height: 8),
          const Text(
            'Pick the sender from this phone\'s SMS inbox.',
            style: TextStyle(fontSize: 15, color: Palette.ink2),
          ),
          const SizedBox(height: 16),
          if (list.isEmpty) const Text('The inbox is empty.', style: TextStyle(color: Palette.ink2)),
          for (final s in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _Option(
                selected: _sender == s.address,
                onTap: () => setState(() {
                  if (_sender != s.address) {
                    _messages = const [];
                    _template = null;
                    _sample = null;
                  }
                  _sender = s.address;
                }),
                title: s.address,
                trailing: '${s.count} message${s.count == 1 ? '' : 's'}',
                subtitle: s.latestBody,
              ),
            ),
        ],
      );
    },
  );

  // ---- Step 3 ----

  Widget _formatStep() {
    if (_loadingMessages) return const Center(child: CircularProgressIndicator());
    final sample = _sample;
    if (sample == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('No messages from this sender yet. Go back and pick another sender.'),
      );
    }
    final raw = _fixing ? null : _template?.rawFields(sample.body);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        Text(
          _fixing ? 'Show the app where each part is' : 'Check what the app found',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.2),
        ),
        const SizedBox(height: 8),
        Text(
          _fixing
              ? 'Copy each part exactly as it appears in the message below. The app learns the format from it.'
              : 'This sample tells the app where each part sits in an M-Money message. Tap a row to see it highlighted.',
          style: const TextStyle(fontSize: 15, color: Palette.ink2, height: 1.45),
        ),
        const SizedBox(height: 16),
        SectionLabel('Sample from $_sender · ${shortDate(toKigali(sample.date))}, ${kigaliTime(sample.date)}'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: Palette.surface,
            border: Border.all(color: Palette.border),
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(18),
              topLeft: Radius.circular(4),
            ),
          ),
          child: Text.rich(
            TextSpan(children: _highlight(sample.body, raw ?? const {})),
            style: const TextStyle(fontSize: 15, height: 1.7, color: Palette.ink),
          ),
        ),
        const SizedBox(height: 14),
        if (_fixing) ..._fixFields() else if (raw != null) _fieldList(raw),
      ],
    );
  }

  List<InlineSpan> _highlight(String body, Map<String, String> fields) {
    final spans = <InlineSpan>[];
    var at = 0;
    for (final f in const ['amount', 'name', 'phone', 'datetime', 'txid']) {
      final value = fields[f];
      if (value == null || value.isEmpty) continue;
      final i = body.indexOf(value, at);
      if (i < 0) continue;
      spans.add(TextSpan(text: body.substring(at, i)));
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(
              color: _fieldColors[f],
              borderRadius: BorderRadius.circular(4),
              border: _selected == f ? Border.all(color: Palette.ink, width: 2) : null,
            ),
            child: Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
      );
      at = i + value.length;
    }
    spans.add(TextSpan(text: body.substring(at)));
    return spans;
  }

  Widget _fieldList(Map<String, String> raw) {
    final parsed = _template!.parse(_sample!.body)!;
    final matches = repo.vehicles.where(
      (v) => v.momoUsernames.any((u) => u.trim().toUpperCase() == parsed.name.toUpperCase()),
    );
    final rows = [
      ('amount', '${rwf(parsed.amount)} RWF', ''),
      (
        'name',
        parsed.name,
        matches.isEmpty
            ? 'No bike has this MoMo username yet'
            : 'Matches ${matches.first.plate} · ${matches.first.driverName}',
      ),
      if ((parsed.phone ?? '').length >= 3)
        ('phone', parsed.phone!.substring(parsed.phone!.length - 3), 'Second check when two drivers share a name'),
      if (parsed.paidAt != null)
        (
          'datetime',
          '${shortDate(toKigali(parsed.paidAt!))}, ${kigaliTime(parsed.paidAt!)}',
          'Used as the payment time',
        ),
      ('txid', parsed.txId, 'Stops the same payment counting twice'),
      ('skip', 'Ignored', 'Never read or shared'),
    ];
    return Card(
      child: Column(
        children: [
          for (final (i, (f, value, note)) in rows.indexed) ...[
            if (i > 0) const Divider(),
            InkWell(
              onTap: () => setState(() => _selected = f),
              child: Container(
                color: _selected == f ? Palette.ground : null,
                padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                child: Row(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: _fieldColors[f],
                        borderRadius: BorderRadius.circular(4),
                        border: f == 'skip' ? Border.all(color: Palette.control) : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _fieldLabels[f]!,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Palette.ink2),
                          ),
                          const SizedBox(height: 2),
                          Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          if (note.isNotEmpty)
                            Text(
                              note,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: f == 'name' && matches.isNotEmpty ? Palette.ok : Palette.ink2,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (f != 'skip')
                      TextButton(
                        onPressed: () {
                          _prefillFix();
                          setState(() => _fixing = true);
                        },
                        child: const Text('Fix'),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _fixFields() => [
    for (final f in _fieldLabels.keys)
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: _fix[f],
          decoration: InputDecoration(
            labelText: _fieldLabels[f],
            helperText: switch (f) {
              'name' => 'Exactly as in the message, e.g. Xxx MUGABO',
              'skip' => 'The balance, so the app can skip it (optional)',
              'phone' || 'datetime' => 'Optional',
              _ => null,
            },
            prefixIcon: Padding(
              padding: const EdgeInsets.all(14),
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(color: _fieldColors[f], borderRadius: BorderRadius.circular(4)),
              ),
            ),
          ),
        ),
      ),
    if (_fixError != null)
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          _fixError!,
          style: const TextStyle(color: Palette.bad, fontWeight: FontWeight.w500),
        ),
      ),
    Row(
      children: [
        Expanded(
          child: OutlinedButton(onPressed: _chooseOtherMessage, child: const Text('Other message')),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(onPressed: _applyFix, child: const Text('Use these')),
        ),
      ],
    ),
  ];

  Future<void> _chooseOtherMessage() async {
    final picked = await showModalBottomSheet<InboxSms>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Palette.surface,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          children: [
            const Text(
              'Pick a "You have received" message',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            for (final m in _messages.take(40))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _Option(
                  selected: identical(m, _sample),
                  onTap: () => Navigator.pop(context, m),
                  title: '${shortDate(toKigali(m.date))}, ${kigaliTime(m.date)}',
                  subtitle: m.body,
                  maxLines: 3,
                ),
              ),
          ],
        ),
      ),
    );
    if (picked != null) _pickSample(picked);
  }

  // ---- Step 4 ----

  Widget _finishStep() => ListView(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
    children: [
      const Text('Almost done', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Your MoMo wallet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                'Money that arrives on this phone is counted as held by ${repo.me?.name ?? 'you'} until it is deposited.',
                style: const TextStyle(fontSize: 14, color: Palette.ink2, height: 1.45),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _momo,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'MoMo number on this phone'),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Catch up on past payments', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                _catchUp.isEmpty
                    ? 'No payments from registered drivers in the last 30 days.'
                    : 'Found ${_catchUp.length} payment${_catchUp.length == 1 ? '' : 's'} from registered drivers in the last 30 days.',
                style: const TextStyle(fontSize: 14, color: Palette.ink2),
              ),
              for (final c in _catchUp.reversed.take(3)) ...[
                const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider()),
                Row(
                  children: [
                    SizedBox(
                      width: 86,
                      child: Text(shortDate(toKigali(c.paidAt)), style: const TextStyle(fontSize: 14)),
                    ),
                    PlateChip(c.vehicle.plate, small: true),
                    const Spacer(),
                    Text(
                      rwf(c.payment.amount),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, fontFeatures: tabular),
                    ),
                  ],
                ),
              ],
              if (_catchUp.length > 3) ...[
                const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider()),
                Text('and ${_catchUp.length - 3} more', style: const TextStyle(fontSize: 13, color: Palette.ink2)),
              ],
              if (_catchUp.isNotEmpty) ...[
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: _import,
                  onChanged: (v) => setState(() => _import = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Import these payments', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Ones already counted, or from before a bike\'s start date, are skipped.'),
                ),
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: 14),
      const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 18, color: Palette.ink2),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Only payments from registered drivers leave this phone. Your other messages stay private.',
              style: TextStyle(fontSize: 13, color: Palette.ink2, height: 1.45),
            ),
          ),
        ],
      ),
      if (_error != null) ...[
        const SizedBox(height: 14),
        Text(
          _error!,
          style: const TextStyle(color: Palette.bad, fontWeight: FontWeight.w500),
        ),
      ],
    ],
  );
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({required this.title, required this.text, required this.done, required this.onAllow});
  final String title;
  final String text;
  final bool done;
  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(done ? Icons.check_circle : Icons.radio_button_unchecked, color: done ? Palette.ok : Palette.ink3),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(text, style: const TextStyle(fontSize: 13, color: Palette.ink2, height: 1.4)),
              ],
            ),
          ),
          if (!done) ...[const SizedBox(width: 8), OutlinedButton(onPressed: onAllow, child: const Text('Allow'))],
        ],
      ),
    ),
  );
}

class _Option extends StatelessWidget {
  const _Option({
    required this.selected,
    required this.onTap,
    required this.title,
    this.trailing,
    required this.subtitle,
    this.maxLines = 1,
  });

  final bool selected;
  final VoidCallback onTap;
  final String title;
  final String? trailing;
  final String subtitle;
  final int maxLines;

  @override
  Widget build(BuildContext context) => Material(
    color: Palette.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: selected ? Palette.ink : Palette.border, width: selected ? 2 : 1),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: selected ? Palette.ink : Palette.ink3,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      ),
                      if (trailing != null) Text(trailing!, style: const TextStyle(fontSize: 12, color: Palette.ink2)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: maxLines,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: Palette.ink2),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
