import 'package:flutter/material.dart';

import '../data/card_state.dart';
import '../data/history.dart';
import '../data/models.dart';
import '../data/repo.dart';
import '../format.dart';
import '../theme.dart';
import 'home_screen.dart' show confirmDelete;
import 'message_driver_sheet.dart';
import 'record_payment_sheet.dart';
import 'vehicle_form_screen.dart';

class VehicleDetailScreen extends StatefulWidget {
  const VehicleDetailScreen({super.key, required this.repo, required this.vehicleId});
  final Repo repo;
  final String vehicleId;

  @override
  State<VehicleDetailScreen> createState() => _VehicleDetailScreenState();
}

class _VehicleDetailScreenState extends State<VehicleDetailScreen> {
  late Future<VehicleHistory> _history;
  late List<DateTime> _days;
  DateTime? _selected;

  Repo get repo => widget.repo;

  @override
  void initState() {
    super.initState();
    _history = _fetch();
    // Reload when anything changes, on this phone or another.
    repo.addListener(_reload);
  }

  @override
  void dispose() {
    repo.removeListener(_reload);
    super.dispose();
  }

  Future<VehicleHistory> _fetch() {
    _days = calendarDays(kigaliToday());
    return repo.history(widget.vehicleId, from: _days.first, to: _days.last);
  }

  void _reload() {
    if (mounted) setState(() => _history = _fetch());
  }

  Future<void> _removePayment(PaymentRow p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove this ${rwf(p.amount)} RWF payment?'),
        content: const Text('Use this only for a mistake. The days it paid will show as unpaid again.'),
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
    if (ok == true) await repo.removePayment(p.id);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: repo,
    builder: (context, _) {
      final v = repo.vehicles.where((x) => x.id == widget.vehicleId).firstOrNull;
      if (v == null) {
        return Scaffold(
          appBar: AppBar(),
          body: const Center(child: Text('This vehicle was deleted.')),
        );
      }
      final today = kigaliToday();
      return Scaffold(
        appBar: AppBar(
          title: PlateChip(v.plate),
          actions: [
            IconButton(
              tooltip: 'Edit vehicle',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => VehicleFormScreen(repo: repo, vehicle: v),
                ),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (_) => confirmDelete(context, repo, v),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete vehicle', style: TextStyle(color: Palette.bad)),
                ),
              ],
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            _reload();
            await _history;
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              _Header(vehicle: v, onToggle: (on) => repo.setActive(v, on)),
              const SizedBox(height: 12),
              _OwesCard(
                vehicle: v,
                today: repo.today[v.id],
                deadline: repo.settings.deadline,
                onRecord: () => showRecordPayment(context, repo, v),
                onMessage: () => showMessageDriver(context, repo, v),
              ),
              const SizedBox(height: 12),
              FutureBuilder<VehicleHistory>(
                future: _history,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return const Card(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Text("Couldn't load the history. Pull down to try again."),
                      ),
                    );
                  }
                  final h = snap.data;
                  if (h == null) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final selected = _selected ?? today;
                  return Column(
                    children: [
                      _CalendarCard(
                        vehicle: v,
                        days: _days,
                        history: h,
                        today: today,
                        selected: selected,
                        deadline: repo.settings.deadline,
                        onSelect: (d) => setState(() => _selected = d),
                      ),
                      const SizedBox(height: 12),
                      _PaymentsCard(payments: h.payments, repo: repo, onRemove: _removePayment),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.vehicle, required this.onToggle});
  final Vehicle vehicle;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final v = vehicle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(v.driverName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          '${v.phone} · since ${shortDate(v.startDate)} ${v.startDate.year}',
          style: const TextStyle(fontSize: 14, color: Palette.ink2),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final u in v.momoUsernames)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: Palette.muteBg, borderRadius: BorderRadius.circular(8)),
                child: Text(u, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(v.terms, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                Text(v.isActive ? 'Active' : 'Off', style: const TextStyle(fontSize: 13, color: Palette.ink2)),
                Switch(value: v.isActive, onChanged: onToggle),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _OwesCard extends StatelessWidget {
  const _OwesCard({
    required this.vehicle,
    required this.today,
    required this.deadline,
    required this.onRecord,
    required this.onMessage,
  });
  final Vehicle vehicle;
  final VehicleToday? today;
  final String deadline;
  final VoidCallback onRecord;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    final v = vehicle;
    final t = today;
    final overdue = t?.overdue ?? 0;
    final leftNow = t != null && t.currentKind == 'due' ? t.currentDue - t.currentPaid : 0;
    final credit = t?.credit ?? 0;
    final dueWhen = v.frequency == Frequency.daily || t?.currentDueDate == null
        ? 'by $deadline'
        : 'on ${shortDate(t!.currentDueDate!)} by $deadline';

    final (label, amount, color, line) = overdue > 0
        ? (
            'Owes',
            overdue,
            Palette.bad,
            'Unpaid since ${shortDate(t!.oldestUnpaid!)}.${leftNow > 0 ? ' Plus ${rwf(leftNow)} due ${v.periodWord} $dueWhen.' : ''}',
          )
        : leftNow > 0
        ? ('Due ${v.periodWord}', leftNow, Palette.ink, 'Nothing owed from before. Due $dueWhen.')
        : credit > 0
        ? ('Credit', credit, Palette.ok, 'Paid ahead. It covers the next days automatically.')
        : ('Owes', 0, Palette.ok, v.isActive ? 'Nothing owed.' : 'Switched off. No payments expected.');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionLabel(label),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  rwf(amount),
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    color: color,
                    fontFeatures: tabular,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'RWF',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: color),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(line, style: const TextStyle(fontSize: 14, color: Palette.ink2, height: 1.4)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRecord,
              icon: const Icon(Icons.payments_outlined, size: 20),
              label: const Text('Record cash payment'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onMessage,
              icon: const Icon(Icons.sms_outlined, size: 20),
              label: const Text('Message driver'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarCard extends StatelessWidget {
  const _CalendarCard({
    required this.vehicle,
    required this.days,
    required this.history,
    required this.today,
    required this.selected,
    required this.deadline,
    required this.onSelect,
  });

  final Vehicle vehicle;
  final List<DateTime> days;
  final VehicleHistory history;
  final DateTime today;
  final DateTime selected;
  final String deadline;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final past = days.where((d) => !d.isAfter(today)).map((d) => history.dues[d]).whereType<DueRow>();
    int count(bool Function(DueStatus) f) => past.where((d) => f(d.status)).length;
    final (title, text) = describeDay(
      selected,
      history.dues[selected],
      history.payments,
      vehicle,
      today: today,
      deadline: deadline,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text('Last 5 weeks', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const Spacer(),
                Text(
                  '${dateOnlyLabel(days.first)} – ${dateOnlyLabel(days.last)}',
                  style: const TextStyle(fontSize: 13, color: Palette.ink2),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (final l in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                  Expanded(
                    child: Text(
                      l,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Palette.ink3),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            for (var w = 0; w < 5; w++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    for (var i = 0; i < 7; i++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
                          child: _DayButton(
                            day: days[w * 7 + i],
                            cell: calendarCell(days[w * 7 + i], history.dues[days[w * 7 + i]], vehicle, today),
                            selected: days[w * 7 + i] == selected,
                            onTap: () => onSelect(days[w * 7 + i]),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(color: Palette.ground, borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(text, style: const TextStyle(fontSize: 13, color: Palette.ink2, height: 1.45)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Wrap(
              spacing: 14,
              runSpacing: 8,
              children: [
                _Legend(DayCell.ok, 'On time'),
                _Legend(DayCell.late, 'Paid late'),
                _Legend(DayCell.part, 'Partly paid'),
                _Legend(DayCell.miss, 'Unpaid'),
                _Legend(DayCell.rest, 'Rest day'),
                _Legend(DayCell.due, 'Due today'),
              ],
            ),
            const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Divider()),
            Row(
              children: [
                _Stat('${count((s) => s == DueStatus.onTime)}', 'on time', Palette.ink),
                _Stat('${count((s) => s == DueStatus.late)}', 'paid late', Palette.warn),
                _Stat('${count((s) => s == DueStatus.unpaid || s == DueStatus.partial)}', 'unpaid', Palette.bad),
                _Stat('${count((s) => s == DueStatus.rest)}', 'rest days', Palette.ink),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DayButton extends StatelessWidget {
  const _DayButton({required this.day, required this.cell, required this.selected, required this.onTap});
  final DateTime day;
  final DayCell cell;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (cell) {
      DayCell.ok => (Palette.ok, Colors.white, null),
      DayCell.late => (Palette.late, Palette.ink, null),
      DayCell.part => (Palette.warnBg, Palette.warn, Border.all(color: Palette.lateLine, width: 2)),
      DayCell.miss => (Palette.missFill, Palette.bad, Border.all(color: Palette.missLine, width: 2)),
      DayCell.rest => (Palette.rest, Palette.ink2, null),
      DayCell.due => (Palette.surface, Palette.ink, Border.all(color: Palette.ink, width: 2)),
      DayCell.none || DayCell.future => (Palette.surface, Palette.ink3, Border.all(color: Palette.control)),
    };
    return Semantics(
      button: true,
      selected: selected,
      label: '${weekdayLong[day.weekday - 1]} ${dateOnlyLabel(day)}: ${cell.name}',
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              border: border,
              borderRadius: BorderRadius.circular(9),
              boxShadow: selected ? const [BoxShadow(color: Palette.blue, spreadRadius: 2.5)] : null,
            ),
            child: Text(
              '${day.day}',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: fg),
            ),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.cell, this.text);
  final DayCell cell;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _MiniSquare(cell),
      const SizedBox(width: 6),
      Text(
        text,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Palette.ink2),
      ),
    ],
  );
}

class _MiniSquare extends StatelessWidget {
  const _MiniSquare(this.cell);
  final DayCell cell;

  @override
  Widget build(BuildContext context) {
    final (bg, border) = switch (cell) {
      DayCell.ok => (Palette.ok, null),
      DayCell.late => (Palette.late, null),
      DayCell.part => (Palette.warnBg, Border.all(color: Palette.lateLine, width: 1.5)),
      DayCell.miss => (Palette.missFill, Border.all(color: Palette.missLine, width: 1.5)),
      DayCell.rest => (Palette.rest, null),
      DayCell.due => (Palette.surface, Border.all(color: Palette.ink, width: 1.5)),
      DayCell.none || DayCell.future => (Palette.surface, Border.all(color: Palette.control)),
    };
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: bg, border: border, borderRadius: BorderRadius.circular(3)),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label, this.color);
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color, fontFeatures: tabular),
        ),
        Text(label, style: const TextStyle(fontSize: 12, color: Palette.ink2)),
      ],
    ),
  );
}

class _PaymentsCard extends StatelessWidget {
  const _PaymentsCard({required this.payments, required this.repo, required this.onRemove});
  final List<PaymentRow> payments;
  final Repo repo;
  final ValueChanged<PaymentRow> onRemove;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 4, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Payments', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          if (payments.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('No payments yet.', style: TextStyle(color: Palette.ink2)),
            ),
          for (final (i, p) in payments.indexed) ...[
            if (i > 0) const Padding(padding: EdgeInsets.only(right: 12), child: Divider()),
            _PaymentRowTile(payment: p, repo: repo, onRemove: () => onRemove(p)),
          ],
        ],
      ),
    ),
  );
}

class _PaymentRowTile extends StatelessWidget {
  const _PaymentRowTile({required this.payment, required this.repo, required this.onRemove});
  final PaymentRow payment;
  final Repo repo;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final p = payment;
    final at = toKigali(p.paidAt);
    final (tag, tagBg, tagFg) = switch (p.source) {
      PaymentSource.momo => ('MoMo', const Color(0xFFFFF4C2), const Color(0xFF5C4A00)),
      PaymentSource.cash => ('Cash', Palette.okBg, Palette.ok),
      PaymentSource.other => ('Other', Palette.muteBg, Palette.ink2),
    };
    final meta = p.source == PaymentSource.momo
        ? 'FT ${p.txId ?? '-'} · held by ${repo.memberName(p.heldById)}'
        : 'Recorded by ${repo.memberName(p.recordedById)} · held by ${repo.memberName(p.heldById)}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${shortDate(at)} · ${kigaliTime(p.paidAt)}',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: tagBg, borderRadius: BorderRadius.circular(6)),
                      child: Text(
                        tag,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: tagFg),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(p.coverText, style: const TextStyle(fontSize: 13, color: Palette.ink2)),
                const SizedBox(height: 2),
                Text(meta, style: const TextStyle(fontSize: 12, color: Palette.ink2)),
                if ((p.note ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('"${p.note}"', style: const TextStyle(fontSize: 12, color: Palette.ink2)),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              rwf(p.amount),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, fontFeatures: tabular),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Payment actions',
            icon: const Icon(Icons.more_vert, size: 20, color: Palette.ink2),
            onSelected: (_) => onRemove(),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'remove',
                child: Text('Remove payment', style: TextStyle(color: Palette.bad)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
