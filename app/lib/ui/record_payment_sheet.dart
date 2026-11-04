import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/history.dart';
import '../data/models.dart';
import '../data/repo.dart';
import '../format.dart';
import '../theme.dart';
import 'inputs.dart';

/// Opens the "Record payment" sheet for a cash (or other) payment.
Future<void> showRecordPayment(BuildContext context, Repo repo, Vehicle vehicle) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Palette.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _RecordPaymentSheet(repo: repo, vehicle: vehicle),
  );
  if (saved == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Payment saved for ${vehicle.plate}.')));
  }
}

class _RecordPaymentSheet extends StatefulWidget {
  const _RecordPaymentSheet({required this.repo, required this.vehicle});
  final Repo repo;
  final Vehicle vehicle;

  @override
  State<_RecordPaymentSheet> createState() => _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends State<_RecordPaymentSheet> {
  late final _amount = TextEditingController(text: rwf(widget.vehicle.amount));
  final _note = TextEditingController();
  late final Future<List<DueRow>> _open = widget.repo.openDues(widget.vehicle.id);
  PaymentSource _source = PaymentSource.cash;
  late String? _holder = widget.repo.me?.id;
  DateTime _when = kigaliNow();
  bool _saving = false;
  String? _error;

  int get _value => int.tryParse(digits(_amount.text)) ?? 0;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickWhen() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: widget.vehicle.startDate.subtract(const Duration(days: 1)),
      lastDate: kigaliNow(),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_when));
    if (t == null) return;
    setState(() => _when = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  Future<void> _save() async {
    if (_value <= 0) {
      setState(() => _error = 'Enter the amount received.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repo.recordPayment(
        vehicleId: widget.vehicle.id,
        amount: _value,
        // _when is Kigali wall-clock time (UTC+2).
        paidAt: DateTime.utc(
          _when.year,
          _when.month,
          _when.day,
          _when.hour,
          _when.minute,
        ).subtract(const Duration(hours: 2)),
        source: _source,
        heldById: _holder,
        note: _note.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      setState(() => _error = 'Couldn\'t save. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vehicle;
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
            const Text('Record payment', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Row(
              children: [
                PlateChip(v.plate, small: true),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(v.driverName, style: const TextStyle(fontSize: 14, color: Palette.ink2)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, ThousandsFormatter()],
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, fontFeatures: tabular),
              decoration: InputDecoration(labelText: 'Amount', suffixText: 'RWF', errorText: _error),
            ),
            const SizedBox(height: 10),
            FutureBuilder<List<DueRow>>(
              future: _open,
              builder: (context, snap) {
                final open = snap.data ?? const <DueRow>[];
                final owed = open.fold<int>(0, (t, d) => t + d.remaining);
                final quick = {v.amount, v.amount * 2, if (owed > 0) owed}.toList()..sort();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final q in quick)
                          ChoiceChip(
                            label: Text(q == owed && owed > 0 ? 'All owed · ${rwf(q)}' : rwf(q)),
                            selected: _value == q,
                            onSelected: (_) => setState(() => _amount.text = rwf(q)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _Preview(
                      loading: snap.connectionState != ConnectionState.done,
                      preview: previewPayment(open, _value),
                      today: kigaliToday(),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            const _Label('Type'),
            Wrap(
              spacing: 8,
              children: [
                for (final (s, label) in [(PaymentSource.cash, 'Cash'), (PaymentSource.other, 'Other')])
                  ChoiceChip(
                    label: Text(label),
                    selected: _source == s,
                    onSelected: (_) => setState(() => _source = s),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const _Label('Who has the money?'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in widget.repo.members)
                  ChoiceChip(
                    label: Text(m.name),
                    selected: _holder == m.id,
                    onSelected: (_) => setState(() => _holder = m.id),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _pickWhen,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date and time received',
                  suffixIcon: Icon(Icons.calendar_today_outlined, size: 20, color: Palette.ink2),
                ),
                child: Text(
                  '${longDate(_when)} · ${_two(_when.hour)}:${_two(_when.minute)}',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Note (optional)', hintText: 'e.g. paid at the parking'),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Palette.ink2),
                          )
                        : const Text('Save payment'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}

class _Preview extends StatelessWidget {
  const _Preview({required this.loading, required this.preview, required this.today});
  final bool loading;
  final PaymentPreview preview;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (final (due, pay) in preview.lines) {
      final full = pay == due.remaining;
      final label = due.dueDate == today
          ? 'Today, ${shortDate(due.dueDate)}'
          : due.dueDate.isBefore(today)
          ? '${shortDate(due.dueDate)} (overdue)'
          : 'Due ${shortDate(due.dueDate)}';
      final (text, color, dot) = full
          ? ('Paid in full', Palette.ok, Palette.ok)
          : pay > 0
          ? ('${rwf(due.amountPaid + pay)} of ${rwf(due.amountDue)}', Palette.warn, Palette.late)
          : ('Still open', Palette.ink2, Palette.control);
      rows.add(
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                child: pay > 0 ? const Icon(Icons.check, size: 13, color: Colors.white) : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
              Text(
                text,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color, fontFeatures: tabular),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBFC),
        border: Border.all(color: Palette.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('This payment covers'),
          if (loading)
            const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator())
          else if (preview.lines.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text('Nothing is owed right now.', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ...rows,
          if (!loading && preview.credit > 0)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '${rwf(preview.credit)} RWF left over becomes credit for the next days.',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Palette.warn),
              ),
            ),
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text('Oldest unpaid day first.', style: TextStyle(fontSize: 12, color: Palette.ink2)),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
  );
}
