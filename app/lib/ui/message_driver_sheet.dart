import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/messages.dart';
import '../data/models.dart';
import '../data/repo.dart';
import '../prefs.dart';
import '../theme.dart';

/// "Message driver": a suggested SMS in Kinyarwanda and English that opens in
/// the phone's SMS app. Nothing is ever sent automatically.
Future<void> showMessageDriver(
  BuildContext context,
  Repo repo,
  Vehicle vehicle, {
  MessageKind? kind,
  MessageFacts? facts,
}) {
  final (suggested, suggestedFacts) = suggestFor(vehicle, repo.today[vehicle.id]);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Palette.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) =>
        _MessageDriverSheet(repo: repo, vehicle: vehicle, kind: kind ?? suggested, facts: facts ?? suggestedFacts),
  );
}

/// Opens the sheet for an alert about one driver.
Future<void> showMessageDriverForAlert(BuildContext context, Repo repo, AlertItem alert) async {
  final v = repo.vehicleById(alert.vehicleId);
  if (v == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('That vehicle was deleted.')));
    return;
  }
  final (kind, facts) = suggestForAlert(alert.type, alert.data, v);
  await showMessageDriver(context, repo, v, kind: kind, facts: facts);
}

class _MessageDriverSheet extends StatefulWidget {
  const _MessageDriverSheet({required this.repo, required this.vehicle, required this.kind, required this.facts});
  final Repo repo;
  final Vehicle vehicle;
  final MessageKind kind;
  final MessageFacts facts;

  @override
  State<_MessageDriverSheet> createState() => _MessageDriverSheetState();
}

class _MessageDriverSheetState extends State<_MessageDriverSheet> {
  late MessageKind _kind = widget.kind;
  MessageLanguage _lang = MessageLanguage.byName(AppPrefs.messageLanguage);
  late final _text = TextEditingController(text: _compose());

  String get _phone => widget.vehicle.phone.trim();

  String _compose() =>
      composeMessage(widget.repo.messageTemplates[_kind] ?? MessageTemplate.defaults[_kind]!, _lang, widget.facts);

  void _recompose() => setState(() => _text.text = _compose());

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final ok = await launchUrl(smsUri(_phone, _text.text), mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't open the SMS app. Copy the text instead.")));
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _text.text));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message copied.')));
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vehicle;
    final parts = smsParts(_text.text);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Palette.control, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 14),
            const Text('Message driver', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Row(
              children: [
                PlateChip(v.plate, small: true),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _phone.isEmpty ? v.driverName : '${v.driverName} · $_phone',
                    style: const TextStyle(fontSize: 14, color: Palette.ink2),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final k in MessageKind.values)
                  ChoiceChip(
                    label: Text(k.label),
                    selected: _kind == k,
                    onSelected: (_) {
                      _kind = k;
                      _recompose();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<MessageLanguage>(
              segments: [for (final l in MessageLanguage.values) ButtonSegment(value: l, label: Text(l.label))],
              selected: {_lang},
              showSelectedIcon: false,
              onSelectionChanged: (s) {
                _lang = s.first;
                AppPrefs.messageLanguage = _lang.name;
                _recompose();
              },
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _text,
              minLines: 6,
              maxLines: 14,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 15, height: 1.45),
              decoration: InputDecoration(
                labelText: 'Message',
                alignLabelWithHint: true,
                helperText: '${_text.text.length} characters · $parts SMS. You can edit it.',
              ),
            ),
            if (_phone.isEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Palette.warnBg, borderRadius: BorderRadius.circular(12)),
                child: const Text(
                  "This vehicle has no driver phone number. Add it with Edit, or copy the message.",
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Palette.warn),
                ),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _copy,
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _phone.isEmpty || _text.text.trim().isEmpty ? null : _open,
                    icon: const Icon(Icons.sms_outlined, size: 18),
                    label: const Text('Open in SMS app'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Nothing is sent until you press send in your SMS app.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Palette.ink2),
            ),
          ],
        ),
      ),
    );
  }
}
