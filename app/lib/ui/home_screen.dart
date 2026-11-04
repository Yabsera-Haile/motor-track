import 'package:flutter/material.dart';

import '../data/card_state.dart';
import '../data/models.dart';
import '../data/repo.dart';
import '../format.dart';
import '../prefs.dart';
import '../reader/reader_service.dart';
import '../theme.dart';
import 'alerts_screen.dart';
import 'reader_setup_screen.dart';
import 'record_payment_sheet.dart';
import 'vehicle_card.dart';
import 'vehicle_detail_screen.dart';
import 'vehicle_form_screen.dart';

enum _Filter { all, unpaid, paid, inactive }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.repo});
  final Repo repo;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();
  _Filter _filter = _Filter.all;

  Repo get repo => widget.repo;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(Vehicle v) {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    final words = '${v.driverName} ${v.momoUsernames.join(' ')}'.toLowerCase();
    if (words.contains(q)) return true;
    if (v.plate.replaceAll(' ', '').toLowerCase().contains(q.replaceAll(' ', ''))) return true;
    final d = digits(q);
    return d.length >= 3 && digits(v.phone).contains(d);
  }

  static bool _inFilter(_Filter f, Vehicle v, CardKind kind) => switch (f) {
    _Filter.all => true,
    _Filter.unpaid => v.isActive && (kind == CardKind.unpaid || kind == CardKind.partial),
    _Filter.paid => v.isActive && kind == CardKind.paid,
    _Filter.inactive => !v.isActive,
  };

  Future<void> _openForm([Vehicle? v]) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => VehicleFormScreen(repo: repo, vehicle: v),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: repo,
    builder: (context, _) {
      final day = kigaliToday();
      final deadline = repo.settings.deadline;
      final states = {
        for (final v in repo.vehicles) v.id: describeCard(v, repo.today[v.id], deadline: deadline, today: day),
      };
      int count(_Filter f) => repo.vehicles.where((v) => _inFilter(f, v, states[v.id]!.kind)).length;
      final shown = repo.vehicles.where((v) => _inFilter(_filter, v, states[v.id]!.kind) && _matches(v)).toList();
      final summary = TodaySummary.of(repo.vehicles, repo.today, deadline, day);

      return Scaffold(
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _openForm(),
          backgroundColor: Palette.ink,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          icon: const Icon(Icons.add),
          label: const Text('Add vehicle', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: repo.load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
              children: [
                _Header(
                  day: day,
                  alerts: repo.openAlerts,
                  onAlerts: () =>
                      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AlertsScreen(repo: repo))),
                ),
                const SizedBox(height: 8),
                _SummaryCard(summary: summary, deadline: deadline, readerMinutes: repo.readerMinutesAgo),
                if (repo.loadError != null) ...[const SizedBox(height: 10), _Banner(text: repo.loadError!)],
                if (ReaderService.supported &&
                    AppPrefs.readerWanted &&
                    repo.loaded &&
                    !(repo.myDevice?.isReader ?? false)) ...[
                  const SizedBox(height: 10),
                  _ReaderPrompt(
                    onSetUp: () => Navigator.of(
                      context,
                    ).push(MaterialPageRoute<bool>(builder: (_) => ReaderSetupScreen(repo: repo))),
                    onNotNow: () => setState(() => AppPrefs.readerWanted = false),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Name, plate, MoMo name or phone',
                    prefixIcon: const Icon(Icons.search, color: Palette.ink2),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(_search.clear),
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Palette.control),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final (f, label) in [
                        (_Filter.all, 'All'),
                        (_Filter.unpaid, 'Not paid'),
                        (_Filter.paid, 'Paid'),
                        (_Filter.inactive, 'Inactive'),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text('$label  ${count(f)}'),
                            selected: _filter == f,
                            onSelected: (_) => setState(() => _filter = f),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 2),
                  child: Row(children: [SectionLabel('Vehicles'), Spacer(), SectionLabel('Last 7 days')]),
                ),
                const SizedBox(height: 8),
                if (!repo.loaded)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (repo.vehicles.isEmpty)
                  const _Empty(title: 'No vehicles yet', text: 'Tap Add vehicle to register your first bike.')
                else if (shown.isEmpty)
                  const _Empty(title: 'No vehicles match', text: 'Try a name, plate, MoMo name or phone number.')
                else
                  for (final v in shown)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: VehicleCard(
                        vehicle: v,
                        state: states[v.id]!,
                        days: lastSevenDays(repo.recentDues[v.id] ?? const [], day),
                        today: day,
                        onOpen: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => VehicleDetailScreen(repo: repo, vehicleId: v.id),
                          ),
                        ),
                        onRecordPayment: () => showRecordPayment(context, repo, v),
                        onToggle: (on) => repo.setActive(v, on),
                        onEdit: () => _openForm(v),
                        onDelete: () => confirmDelete(context, repo, v),
                      ),
                    ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.day, required this.alerts, required this.onAlerts});
  final DateTime day;
  final int alerts;
  final VoidCallback onAlerts;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10, left: 2),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                headerDate(day),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Palette.ink2),
              ),
              const SizedBox(height: 2),
              const Text('Today', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        IconButton(
          tooltip: alerts == 0 ? 'Alerts' : 'Alerts, $alerts open',
          onPressed: onAlerts,
          icon: Badge(
            isLabelVisible: alerts > 0,
            label: Text('$alerts'),
            backgroundColor: Palette.bad,
            child: const Icon(Icons.notifications_none, size: 26),
          ),
        ),
      ],
    ),
  );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary, required this.deadline, required this.readerMinutes});
  final TodaySummary summary;
  final String deadline;
  final int? readerMinutes;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final paidFlex = s.expected == 0 ? 0 : (s.paidAmount * 1000 ~/ s.expected);
    final partFlex = s.expected == 0 ? 0 : (s.partialAmount * 1000 ~/ s.expected);
    final restFlex = (1000 - paidFlex - partFlex).clamp(0, 1000);
    final reader = switch (readerMinutes) {
      null => ('No Reader set up', Palette.warn),
      < 1 => ('Readers checked just now', Palette.ok),
      < 60 => ('Readers checked ${readerMinutes!} min ago', Palette.ok),
      < 360 => ('Readers checked ${readerMinutes! ~/ 60} h ago', Palette.ok),
      _ => ('No Reader check for ${readerMinutes! ~/ 60} h', Palette.bad),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('Collected today'),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  rwf(s.collected),
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    fontFeatures: tabular,
                  ),
                ),
                const SizedBox(width: 6),
                const Text('RWF', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(
                  'of ${rwf(s.expected)} expected',
                  style: const TextStyle(fontSize: 14, color: Palette.ink2, fontFeatures: tabular),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: SizedBox(
                height: 8,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (paidFlex > 0)
                      Expanded(
                        flex: paidFlex,
                        child: const ColoredBox(color: Palette.ok),
                      ),
                    if (partFlex > 0)
                      Expanded(
                        flex: partFlex,
                        child: const ColoredBox(color: Palette.late),
                      ),
                    if (restFlex > 0)
                      Expanded(
                        flex: restFlex,
                        child: const ColoredBox(color: Palette.divider),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _Legend(cell: DayCell.ok, text: '${s.paidCount} paid'),
                _Legend(cell: DayCell.late, text: '${s.partialCount} partial'),
                _Legend(cell: DayCell.none, text: '${s.notYetCount} not yet'),
              ],
            ),
            const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider()),
            Row(
              children: [
                const Icon(Icons.schedule, size: 16, color: Palette.ink2),
                const SizedBox(width: 6),
                Text('Deadline $deadline', style: const TextStyle(fontSize: 13, color: Palette.ink2)),
                const Spacer(),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: reader.$2, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    reader.$1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: Palette.ink2),
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

class _Legend extends StatelessWidget {
  const _Legend({required this.cell, required this.text});
  final DayCell cell;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      DaySquare(cell: cell, size: 10),
      const SizedBox(width: 6),
      Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
    ],
  );
}

/// Shown on the phone that said "this is the MoMo phone" during the intro,
/// until its Reader is set up.
class _ReaderPrompt extends StatelessWidget {
  const _ReaderPrompt({required this.onSetUp, required this.onNotNow});
  final VoidCallback onSetUp;
  final VoidCallback onNotNow;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.sms_outlined, size: 20),
              SizedBox(width: 8),
              Text('Finish setting up the Reader', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Text(
              'Pick the M-Money sender and check the message format, so payments to this phone are recorded automatically.',
              style: TextStyle(fontSize: 14, color: Palette.ink2, height: 1.45),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              FilledButton(onPressed: onSetUp, child: const Text('Set up')),
              const SizedBox(width: 8),
              TextButton(onPressed: onNotNow, child: const Text('Not now')),
            ],
          ),
        ],
      ),
    ),
  );
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: Palette.warnBg, borderRadius: BorderRadius.circular(12)),
    child: Text(
      text,
      style: const TextStyle(color: Palette.warn, fontWeight: FontWeight.w500),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.title, required this.text});
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
      child: Column(
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: Palette.ink2),
          ),
        ],
      ),
    ),
  );
}

Future<void> confirmDelete(BuildContext context, Repo repo, Vehicle v) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Delete ${v.plate}?'),
      content: const Text(
        'It disappears from the list, but its payments stay in reports.\n\nTo pause a vehicle instead, use its switch.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: TextButton.styleFrom(foregroundColor: Palette.bad),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (ok == true) await repo.deleteVehicle(v);
}
