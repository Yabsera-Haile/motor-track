import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repo.dart';
import '../theme.dart';

/// First launch: team code plus your name, or pick your name if you joined before.
class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key, required this.repo, required this.onJoined});

  final Repo repo;
  final Future<void> Function() onJoined;

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  bool _returning = false;
  bool _busy = false;
  bool _showCode = false;
  String? _error;
  List<Member>? _people;
  String? _pickedId;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on JoinError catch (e) {
      setState(() => _error = joinErrorMessage(e.code));
    } catch (_) {
      setState(() => _error = joinErrorMessage('unknown'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() => _run(() async {
    final err = await widget.repo.join(
      _code.text.trim(),
      name: _returning ? null : _name.text.trim(),
      memberId: _returning ? _pickedId : null,
    );
    if (err != null) throw JoinError(err);
    await widget.onJoined();
  });

  Future<void> _findNames() => _run(() async {
    final people = await widget.repo.teamMembers(_code.text.trim());
    setState(() {
      _people = people;
      _pickedId = null;
    });
  });

  @override
  Widget build(BuildContext context) {
    final canJoin =
        !_busy && _code.text.trim().isNotEmpty && (_returning ? _pickedId != null : _name.text.trim().isNotEmpty);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: Palette.ink, borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.two_wheeler, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 12),
                const Text('Motor Track', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 36),
            const Text('Join your team', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, height: 1.2)),
            const SizedBox(height: 8),
            const Text(
              'Everyone on the team sees the same vehicles, payments and deposits.',
              style: TextStyle(fontSize: 15, color: Palette.ink2, height: 1.45),
            ),
            const SizedBox(height: 28),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text("I'm new")),
                ButtonSegment(value: true, label: Text("I've joined before")),
              ],
              selected: {_returning},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() {
                _returning = s.first;
                _error = null;
              }),
            ),
            const SizedBox(height: 22),
            TextField(
              controller: _code,
              obscureText: !_showCode,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (_) => setState(() => _people = null),
              decoration: InputDecoration(
                labelText: 'Team code',
                helperText: 'Ask a team member for it.',
                suffixIcon: IconButton(
                  tooltip: _showCode ? 'Hide code' : 'Show code',
                  icon: Icon(_showCode ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _showCode = !_showCode),
                ),
              ),
            ),
            const SizedBox(height: 18),
            if (!_returning)
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Your name',
                  helperText: 'Shown on payments and deposits you record.',
                ),
              )
            else if (_people == null)
              OutlinedButton(
                onPressed: _busy || _code.text.trim().isEmpty ? null : _findNames,
                child: const Text('Find my name'),
              )
            else ...[
              const Text('Which one is you?', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              for (final p in _people!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _PersonOption(
                    name: p.name,
                    selected: _pickedId == p.id,
                    onTap: () => setState(() => _pickedId = p.id),
                  ),
                ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Palette.badBg, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Palette.bad, fontWeight: FontWeight.w500),
                ),
              ),
            ],
            const SizedBox(height: 28),
            FilledButton(
              onPressed: canJoin ? _join : null,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Palette.ink2),
                    )
                  : const Text('Join team'),
            ),
            const SizedBox(height: 12),
            const Text(
              'No password or account needed.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Palette.ink2),
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonOption extends StatelessWidget {
  const _PersonOption({required this.name, required this.selected, required this.onTap});
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Palette.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: selected ? Palette.ink : Palette.control, width: selected ? 2 : 1),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: Palette.muteBg,
              child: Text(
                name.characters.first.toUpperCase(),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Palette.ink),
              ),
            ),
            const SizedBox(width: 12),
            Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            const Spacer(),
            if (selected) const Icon(Icons.check, size: 20),
          ],
        ),
      ),
    ),
  );
}
