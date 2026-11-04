import 'package:flutter/material.dart';

import '../data/messages.dart';
import '../data/repo.dart';
import '../theme.dart';

/// Settings → Messages to drivers → one message, in both languages.
class MessageTemplateScreen extends StatefulWidget {
  const MessageTemplateScreen({super.key, required this.repo, required this.kind});
  final Repo repo;
  final MessageKind kind;

  @override
  State<MessageTemplateScreen> createState() => _MessageTemplateScreenState();
}

class _MessageTemplateScreenState extends State<MessageTemplateScreen> {
  late final MessageTemplate _start =
      widget.repo.messageTemplates[widget.kind] ?? MessageTemplate.defaults[widget.kind]!;
  late final _rw = TextEditingController(text: _start.kinyarwanda);
  late final _en = TextEditingController(text: _start.english);
  bool _saving = false;

  static const _example = MessageFacts(name: 'Jean', plate: 'RAD 123 A', amount: 6000, received: 3000);

  bool get _changed => _rw.text.trim() != _start.kinyarwanda.trim() || _en.text.trim() != _start.english.trim();
  bool get _valid => _rw.text.trim().isNotEmpty && _en.text.trim().isNotEmpty;

  @override
  void dispose() {
    _rw.dispose();
    _en.dispose();
    super.dispose();
  }

  void _reset() {
    final d = MessageTemplate.defaults[widget.kind]!;
    setState(() {
      _rw.text = d.kinyarwanda;
      _en.text = d.english;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.repo.saveMessageTemplate(
        MessageTemplate(kind: widget.kind, english: _en.text, kinyarwanda: _rw.text),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Couldn't save. Check your connection and try again.")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = composeMessage(
      MessageTemplate(kind: widget.kind, english: _en.text, kinyarwanda: _rw.text),
      MessageLanguage.both,
      _example,
    );
    return Scaffold(
      appBar: AppBar(title: Text(widget.kind.label)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const Text(
            'The team shares these messages. Words in {braces} are filled in for you: '
            '{name} {plate} {amount} {received} {expected} {date}.',
            style: TextStyle(fontSize: 13, color: Palette.ink2, height: 1.45),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _rw,
            minLines: 3,
            maxLines: 8,
            maxLength: 600,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Kinyarwanda', alignLabelWithHint: true),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _en,
            minLines: 3,
            maxLines: 8,
            maxLength: 600,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'English', alignLabelWithHint: true),
          ),
          const SizedBox(height: 8),
          const SectionLabel('Example'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFAFBFC),
              border: Border.all(color: Palette.border),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(preview, style: const TextStyle(fontSize: 14, height: 1.45)),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: _reset, child: const Text('Back to the original wording')),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _saving || !_changed || !_valid ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Palette.ink2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
    );
  }
}
