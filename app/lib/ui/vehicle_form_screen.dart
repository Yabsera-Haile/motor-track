import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../data/repo.dart';
import '../format.dart';
import '../theme.dart';
import 'inputs.dart';
import 'home_screen.dart' show confirmDelete;

/// Add a vehicle, or edit one when [vehicle] is given.
class VehicleFormScreen extends StatefulWidget {
  const VehicleFormScreen({super.key, required this.repo, this.vehicle});
  final Repo repo;
  final Vehicle? vehicle;

  @override
  State<VehicleFormScreen> createState() => _VehicleFormScreenState();
}

class _VehicleFormScreenState extends State<VehicleFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _driver = TextEditingController(text: widget.vehicle?.driverName);
  late final _phone = TextEditingController(text: widget.vehicle?.phone);
  late final _plate = TextEditingController(text: widget.vehicle?.plate);
  late final _amount = TextEditingController(text: widget.vehicle == null ? '6,000' : rwf(widget.vehicle!.amount));
  final _username = TextEditingController();

  late List<String> _usernames = [...?widget.vehicle?.momoUsernames];
  late Frequency _frequency = widget.vehicle?.frequency ?? Frequency.daily;
  late bool _hasRest = widget.vehicle == null || widget.vehicle!.restWeekdays.isNotEmpty;
  late final Set<int> _rest = {...?widget.vehicle?.restWeekdays, if (widget.vehicle == null) 7};
  late DateTime _start = widget.vehicle?.startDate ?? kigaliToday();
  late DateTime? _firstDue = widget.vehicle?.firstDueDate;
  late bool _active = widget.vehicle?.isActive ?? true;
  bool _saving = false;
  String? _usernameError;

  bool get _editing => widget.vehicle != null;

  @override
  void dispose() {
    for (final c in [_driver, _phone, _plate, _amount, _username]) {
      c.dispose();
    }
    super.dispose();
  }

  void _addUsername() {
    final n = _username.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (n.isEmpty) return;
    if (!_usernames.any((u) => u.toUpperCase() == n.toUpperCase())) {
      setState(() => _usernames = [..._usernames, n]);
    }
    _username.clear();
    setState(() => _usernameError = null);
  }

  Future<DateTime?> _pickDate(DateTime initial) =>
      showDatePicker(context: context, initialDate: initial, firstDate: DateTime(2024), lastDate: DateTime(2035));

  Future<void> _save() async {
    _addUsername();
    final formOk = _form.currentState!.validate();
    if (_usernames.isEmpty) {
      setState(() => _usernameError = 'Add the MoMo username the driver pays from.');
    }
    if (!formOk || _usernames.isEmpty) return;
    if (_frequency != Frequency.daily && _firstDue == null) {
      _snack('Pick the first payment due date.');
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.repo.saveVehicle(
        VehicleDraft(
          driverName: _driver.text.trim(),
          plate: _plate.text.trim(),
          phone: _phone.text.trim(),
          momoUsernames: _usernames,
          amount: int.parse(digits(_amount.text)),
          frequency: _frequency,
          firstDueDate: _firstDue,
          restWeekdays: _hasRest ? (_rest.toList()..sort()) : const [],
          startDate: _start,
          isActive: _active,
        ),
        id: widget.vehicle?.id,
      );
      if (mounted) Navigator.of(context).pop();
    } on SaveError catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Couldn\'t save. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final restDays = (_rest.toList()..sort());
    final restSummary = restDays.isEmpty
        ? 'Pick at least one day, or turn rest days off.'
        : '${restDays.length} rest day${restDays.length == 1 ? '' : 's'} a week: '
              '${restDays.map((d) => weekdayLong[d - 1]).join(', ')}. No payment is expected on '
              '${restDays.length == 1 ? 'that day' : 'those days'}.';
    final amountLabel = switch (_frequency) {
      Frequency.daily => 'Amount per day',
      Frequency.weekly => 'Amount per week',
      Frequency.monthly => 'Amount per month',
    };
    final repeat = _firstDue == null
        ? 'Payments then repeat from this date.'
        : _frequency == Frequency.weekly
        ? 'Then every ${weekdayLong[_firstDue!.weekday - 1]}, deadline ${widget.repo.settings.deadline}.'
        : 'Then on the ${_firstDue!.day}${ordinal(_firstDue!.day)} of every month, deadline ${widget.repo.settings.deadline}.';

    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Edit vehicle' : 'Add vehicle'),
        actions: [
          if (_editing)
            IconButton(
              tooltip: 'Delete vehicle',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await confirmDelete(context, widget.repo, widget.vehicle!);
                if (context.mounted && !widget.repo.vehicles.any((v) => v.id == widget.vehicle!.id)) {
                  Navigator.of(context).pop();
                }
              },
            ),
          TextButton(onPressed: _saving ? null : _save, child: const Text('Save')),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            _Section(
              label: 'Driver and vehicle',
              children: [
                TextFormField(
                  controller: _driver,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Driver name'),
                  validator: (s) => (s ?? '').trim().isEmpty ? 'Enter the driver\'s name.' : null,
                ),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone number',
                    helperText: 'Used when you message the driver.',
                  ),
                  validator: (s) => digits(s ?? '').length < 9 ? 'Enter a full phone number.' : null,
                ),
                TextFormField(
                  controller: _plate,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.8),
                  decoration: const InputDecoration(labelText: 'License plate'),
                  validator: (s) => (s ?? '').trim().length < 2 ? 'Enter the plate.' : null,
                ),
              ],
            ),
            _Section(
              label: 'MoMo usernames',
              help:
                  'Type each name exactly as it appears in the M-Money SMS, including "Xxx". '
                  'Add more than one if the driver sometimes pays from another number.',
              children: [
                if (_usernames.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final u in _usernames)
                        InputChip(
                          label: Text(u, style: const TextStyle(fontWeight: FontWeight.w600)),
                          backgroundColor: Palette.muteBg,
                          side: BorderSide.none,
                          deleteButtonTooltipMessage: 'Remove $u',
                          onDeleted: () => setState(() => _usernames = [..._usernames]..remove(u)),
                        ),
                    ],
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _username,
                        onSubmitted: (_) => _addUsername(),
                        decoration: InputDecoration(
                          hintText: _usernames.isEmpty ? 'e.g. Xxx MUGABO' : 'Add another username',
                          errorText: _usernameError,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(onPressed: _addUsername, child: const Text('Add')),
                  ],
                ),
              ],
            ),
            _Section(
              label: 'Payment',
              children: [
                SegmentedButton<Frequency>(
                  segments: const [
                    ButtonSegment(value: Frequency.daily, label: Text('Daily')),
                    ButtonSegment(value: Frequency.weekly, label: Text('Weekly')),
                    ButtonSegment(value: Frequency.monthly, label: Text('Monthly')),
                  ],
                  selected: {_frequency},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _frequency = s.first),
                ),
                TextFormField(
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, ThousandsFormatter()],
                  style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: tabular),
                  decoration: InputDecoration(labelText: amountLabel, suffixText: 'RWF'),
                  validator: (s) => (int.tryParse(digits(s ?? '')) ?? 0) <= 0 ? 'Enter the amount.' : null,
                ),
                if (_frequency == Frequency.daily) ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Rest days', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Fixed days each week with no payment'),
                    value: _hasRest,
                    onChanged: (on) => setState(() => _hasRest = on),
                  ),
                  if (_hasRest) ...[
                    Row(
                      children: [
                        for (var d = 1; d <= 7; d++)
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(left: d == 1 ? 0 : 6),
                              child: _DayToggle(
                                label: weekdayShort[d - 1],
                                tooltip: weekdayLong[d - 1],
                                on: _rest.contains(d),
                                onTap: () => setState(() => _rest.contains(d) ? _rest.remove(d) : _rest.add(d)),
                              ),
                            ),
                          ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(color: Palette.ground, borderRadius: BorderRadius.circular(10)),
                      child: Text(restSummary, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                    ),
                  ],
                ] else
                  _DateField(
                    label: 'First payment due',
                    value: _firstDue,
                    help: repeat,
                    onTap: () async {
                      final d = await _pickDate(_firstDue ?? kigaliToday());
                      if (d != null) setState(() => _firstDue = d);
                    },
                  ),
              ],
            ),
            _Section(
              children: [
                _DateField(
                  label: 'Start date',
                  value: _start,
                  help: 'Payments are expected from this date.',
                  onTap: () async {
                    final d = await _pickDate(_start);
                    if (d != null) setState(() => _start = d);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Expect payments and send alerts'),
                  value: _active,
                  onChanged: (on) => setState(() => _active = on),
                ),
              ],
            ),
            const SizedBox(height: 4),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Palette.ink2),
                    )
                  : Text(_editing ? 'Save changes' : 'Save vehicle'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({this.label, this.help, required this.children});
  final String? label;
  final String? help;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (label != null) SectionLabel(label!),
            if (help != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(help!, style: const TextStyle(fontSize: 13, color: Palette.ink2, height: 1.45)),
              ),
            for (final c in children) Padding(padding: const EdgeInsets.only(top: 16), child: c),
          ],
        ),
      ),
    ),
  );
}

class _DayToggle extends StatelessWidget {
  const _DayToggle({required this.label, required this.tooltip, required this.on, required this.onTap});
  final String label;
  final String tooltip;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Semantics(
      button: true,
      toggled: on,
      label: tooltip,
      child: Material(
        color: on ? Palette.ink : Palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: on ? Palette.ink : Palette.control),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            height: 44,
            child: Center(
              child: Text(
                label,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: on ? Colors.white : Palette.ink),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.value, required this.help, required this.onTap});
  final String label;
  final DateTime? value;
  final String help;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        helperText: help,
        suffixIcon: const Icon(Icons.calendar_today_outlined, size: 20, color: Palette.ink2),
      ),
      child: Text(value == null ? 'Pick a date' : longDate(value!), style: const TextStyle(fontSize: 16)),
    ),
  );
}
