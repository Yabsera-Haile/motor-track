import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repo.dart';
import '../format.dart';
import '../theme.dart';
import 'record_deposit_sheet.dart';

/// Deposits tab: what each member still holds, and the bank deposits so far.
class DepositsScreen extends StatefulWidget {
  const DepositsScreen({super.key, required this.repo});
  final Repo repo;

  @override
  State<DepositsScreen> createState() => _DepositsScreenState();
}

class _DepositsScreenState extends State<DepositsScreen> {
  late Future<List<Deposit>> _history = widget.repo.deposits();

  @override
  void initState() {
    super.initState();
    // A deposit or payment on any phone reloads the repo; reload the history with it.
    widget.repo.addListener(_reload);
  }

  @override
  void dispose() {
    widget.repo.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (mounted) setState(() => _history = widget.repo.deposits());
  }

  @override
  Widget build(BuildContext context) {
    final repo = widget.repo;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showRecordDeposit(context, repo),
        backgroundColor: Palette.ink,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Record deposit', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await repo.load();
            await _history;
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 110),
            children: [
              const Text('Deposits', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              _HeldCard(repo: repo),
              const Padding(padding: EdgeInsets.fromLTRB(2, 22, 0, 8), child: SectionLabel('History')),
              FutureBuilder<List<Deposit>>(
                future: _history,
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: snap.hasError
                            ? const Text("Couldn't load deposits. Pull down to try again.")
                            : const CircularProgressIndicator(),
                      ),
                    );
                  }
                  final rows = snap.data!;
                  if (rows.isEmpty) {
                    return const Card(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Text(
                          'No deposits yet. Record one when someone takes collected money to the bank.',
                          style: TextStyle(color: Palette.ink2, height: 1.45),
                        ),
                      ),
                    );
                  }
                  return Card(
                    child: Column(
                      children: [
                        for (final (i, d) in rows.indexed) ...[
                          if (i > 0) const Divider(),
                          DepositRow(repo: repo, deposit: d),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeldCard extends StatelessWidget {
  const _HeldCard({required this.repo});
  final Repo repo;

  @override
  Widget build(BuildContext context) {
    final total = repo.notYetDeposited;
    final people = repo.balances.where((b) => b.received > 0 || b.held != 0).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionLabel('Not yet deposited'),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  rwf(total),
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    fontFeatures: tabular,
                  ),
                ),
                const SizedBox(width: 6),
                const Text('RWF', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Rent collected that is still on MoMo or in cash with the team.',
              style: TextStyle(fontSize: 14, color: Palette.ink2, height: 1.4),
            ),
            const SizedBox(height: 10),
            if (people.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text('Nothing collected yet.', style: TextStyle(color: Palette.ink2)),
              ),
            for (final b in people) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 17,
                      backgroundColor: Palette.muteBg,
                      child: Text(
                        b.name.characters.first.toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.w700, color: Palette.ink),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(b.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(
                            'Collected ${rwf(b.received)} · deposited ${rwf(b.deposited)}'
                            '${b.fees > 0 ? ' · fees ${rwf(b.fees)}' : ''}',
                            style: const TextStyle(fontSize: 12, color: Palette.ink2),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      b.held < 0 ? '−${rwf(-b.held)}' : rwf(b.held),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        fontFeatures: tabular,
                        color: b.held < 0 ? Palette.warn : Palette.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One deposit in a list; tap for details and "Remove this deposit".
class DepositRow extends StatelessWidget {
  const DepositRow({super.key, required this.repo, required this.deposit});
  final Repo repo;
  final Deposit deposit;

  @override
  Widget build(BuildContext context) {
    final d = deposit;
    final parts = [
      repo.memberName(d.memberId),
      shortDate(d.depositedOn),
      if (d.fee > 0) 'fee ${rwf(d.fee)}',
      if (d.reference != null) 'Ref ${d.reference}',
    ];
    return ListTile(
      leading: const CircleAvatar(
        radius: 18,
        backgroundColor: Color(0xFFEAEFFD),
        child: Icon(Icons.account_balance, size: 18, color: Palette.blue),
      ),
      title: Text(
        '${rwf(d.amount)} RWF',
        style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: tabular),
      ),
      subtitle: Text(parts.join(' · ')),
      onTap: () => _details(context),
    );
  }

  Future<void> _details(BuildContext context) async {
    final d = deposit;
    final remove = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      backgroundColor: Palette.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${rwf(d.amount)} RWF deposited', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            _Line('Whose money', repo.memberName(d.memberId)),
            _Line('Date', longDate(d.depositedOn)),
            if (d.fee > 0) _Line('Fee', '${rwf(d.fee)} RWF'),
            if (d.reference != null) _Line('Bank reference', d.reference!),
            if (d.note != null) _Line('Note', d.note!),
            if (d.recordedById != null) _Line('Recorded by', repo.memberName(d.recordedById)),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => Navigator.pop(context, true),
              style: OutlinedButton.styleFrom(foregroundColor: Palette.bad),
              child: const Text('Remove this deposit'),
            ),
          ],
        ),
      ),
    );
    if (remove != true || !context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this deposit?'),
        content: Text(
          'Use this only if it was recorded by mistake. The ${rwf(d.amount + d.fee)} RWF counts as held by '
          '${repo.memberName(d.memberId)} again.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Palette.bad),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await repo.removeDeposit(d.id);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Couldn't remove it. Check your connection and try again.")));
      }
    }
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(label, style: const TextStyle(fontSize: 14, color: Palette.ink2)),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}
