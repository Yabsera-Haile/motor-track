import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/repo.dart';
import '../format.dart';
import '../theme.dart';
import 'inputs.dart';

/// Opens "Record deposit": money one member took to the bank.
Future<void> showRecordDeposit(BuildContext context, Repo repo) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Palette.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _RecordDepositSheet(repo: repo),
  );
  if (saved == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deposit saved.')));
  }
}

class _RecordDepositSheet extends StatefulWidget {
  const _RecordDepositSheet({required this.repo});
  final Repo repo;

  @override
  State<_RecordDepositSheet> createState() => _RecordDepositSheetState();
}

class _RecordDepositSheetState extends State<_RecordDepositSheet> {
  late String? _member = _defaultMember();
  late final _amount = TextEditingController(text: _held > 0 ? rwf(_held) : '');
  final _fee = TextEditingController();
  final _reference = TextEditingController();
  final _note = TextEditingController();
  DateTime _on = kigaliToday();
  bool _saving = false;
  String? _error;

  Repo get _repo => widget.repo;
  int get _held => _repo.heldBy(_member);
  int get _value => int.tryParse(digits(_amount.text)) ?? 0;
  int get _feeValue => int.tryParse(digits(_fee.text)) ?? 0;
  String get _name => _repo.memberName(_member);

  /// Me, unless I hold nothing and someone else does.
  String? _defaultMember() {
    final me = _repo.me?.id;
    if (_repo.heldBy(me) > 0) return me;
    final top = _repo.balances.where((b) => b.held > 0).firstOrNull;
    return top?.memberId ?? me;
  }

  @override
  void dispose() {
    _amount.dispose();
    _fee.dispose();
    _reference.dispose();
    _note.dispose();
    super.dispose();
  }

  void _pickMember(String id) => setState(() {
    _member = id;
    _amount.text = _held > 0 ? rwf(_held) : '';
    _error = null;
  });

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _on,
      firstDate: kigaliToday().subtract(const Duration(days: 365)),
      lastDate: kigaliToday(),
      helpText: 'Date of the deposit',
    );
    if (d != null) setState(() => _on = d);
  }

  Future<void> _save() async {
    if (_member == null) {
      setState(() => _error = 'Choose whose money it was.');
      return;
    }
    if (_value <= 0) {
      setState(() => _error = 'Enter the amount deposited.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _repo.recordDeposit(
        memberId: _member!,
        amount: _value,
        fee: _feeValue,
        depositedOn: _on,
        reference: _reference.text,
        note: _note.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      setState(() => _error = "Couldn't save. Check your connection and try again.");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final left = _held - _value - _feeValue;
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
            const Text('Record deposit', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            const _Label('Whose money was deposited?'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in _repo.members)
                  ChoiceChip(
                    label: Text('${m.name} · ${rwf(_repo.heldBy(m.id))}'),
                    selected: _member == m.id,
                    onSelected: (_) => _pickMember(m.id),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                // Up to 999,999,999 RWF.
                LengthLimitingTextInputFormatter(9),
                ThousandsFormatter(),
              ],
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, fontFeatures: tabular),
              decoration: InputDecoration(labelText: 'Amount deposited', suffixText: 'RWF', errorText: _error),
            ),
            if (_held > 0 && _value != _held) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: ActionChip(
                  label: Text('All $_name holds · ${rwf(_held)}'),
                  onPressed: () => setState(() => _amount.text = rwf(_held)),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _fee,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                // Up to 999,999,999 RWF.
                LengthLimitingTextInputFormatter(9),
                ThousandsFormatter(),
              ],
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Fees (optional)',
                suffixText: 'RWF',
                helperText: 'Withdrawal or bank charges paid from the same money',
              ),
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date',
                  suffixIcon: Icon(Icons.calendar_today_outlined, size: 20, color: Palette.ink2),
                ),
                child: Text(longDate(_on), style: const TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reference,
              decoration: const InputDecoration(labelText: 'Bank reference (optional)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Note (optional)', hintText: 'e.g. Bank of Kigali, Remera'),
            ),
            if (_member != null && _value > 0) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: left < 0 ? Palette.warnBg : const Color(0xFFFAFBFC),
                  border: Border.all(color: left < 0 ? Palette.warnBg : Palette.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  left < 0
                      ? "That's ${rwf(-left)} RWF more than $_name holds. Check the amount, or record any missing "
                            'payments first.'
                      : left == 0
                      ? '$_name will have deposited everything they hold.'
                      : '$_name will still hold ${rwf(left)} RWF.',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: left < 0 ? Palette.warn : Palette.ink2,
                  ),
                ),
              ),
            ],
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
                        : const Text('Save deposit'),
                  ),
                ),
              ],
            ),
          ],
        ),
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
