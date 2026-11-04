import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/card_state.dart' show DayCell;
import '../data/history.dart' show dateOnlyLabel;
import '../data/report.dart';
import '../data/repo.dart';
import '../format.dart';
import '../theme.dart';
import 'deposits_screen.dart' show DepositRow;
import 'record_deposit_sheet.dart';
import 'vehicle_card.dart' show DaySquare;
import 'vehicle_detail_screen.dart';

const _title = TextStyle(fontSize: 16, fontWeight: FontWeight.w700);
const _small = TextStyle(fontSize: 12, color: Palette.ink2);
const _axis = TextStyle(fontSize: 11, color: Palette.ink3, fontFeatures: tabular);

/// Reports tab: Collections and Deposits for a chosen period.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.repo, required this.visible});
  final Repo repo;

  /// The tab sits in an IndexedStack: only fetch while it's on screen.
  final bool visible;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  bool _depositsTab = false;
  ReportPeriod _period = ReportPeriod.thisMonth(kigaliToday());

  /// Chosen vehicle ids; null means all.
  Set<String>? _only;

  ReportData? _data;
  ReportPeriod? _dataPeriod;
  bool _loading = false;
  bool _stale = true;
  String? _error;
  int _request = 0;

  Repo get _repo => widget.repo;

  @override
  void initState() {
    super.initState();
    _repo.addListener(_repoChanged);
    if (widget.visible) WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(ReportsScreen old) {
    super.didUpdateWidget(old);
    if (widget.visible && !old.visible && _stale) scheduleMicrotask(() => unawaited(_load()));
  }

  @override
  void dispose() {
    _repo.removeListener(_repoChanged);
    super.dispose();
  }

  /// A payment, deposit or vehicle changed on some phone.
  void _repoChanged() {
    _stale = true;
    // Not straight away: this can be called while another widget builds.
    if (widget.visible) {
      scheduleMicrotask(() {
        if (mounted && widget.visible) unawaited(_load());
      });
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    final request = ++_request;
    final period = _period.refreshed(kigaliToday());
    setState(() {
      _period = period;
      _stale = false;
      _loading = true;
      _error = null;
    });
    try {
      final data = await _repo.reportData(period.from, period.to);
      if (!mounted || request != _request) return;
      setState(() {
        _data = data;
        _dataPeriod = period;
        _loading = false;
      });
    } catch (e) {
      debugPrint('report failed: $e');
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = "Couldn't load the report. Check your connection, then pull down to try again.";
      });
    }
  }

  void _setPeriod(ReportPeriod p) {
    _period = p;
    _load();
  }

  Future<void> _pickMonth() async {
    final today = kigaliToday();
    final starts = _repo.vehicles.map((v) => v.startDate);
    final first = starts.fold(today, (a, b) => b.isBefore(a) ? b : a);
    final months = [
      for (
        var m = DateTime(today.year, today.month);
        !m.isBefore(DateTime(first.year, first.month));
        m = DateTime(m.year, m.month - 1)
      )
        ReportPeriod.month(m.year, m.month, today),
    ].take(36).toList();
    final picked = await showModalBottomSheet<ReportPeriod>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Palette.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(0, 20, 0, 16),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Pick a month', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
            for (final m in months)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                title: Text(m.monthLabel, style: const TextStyle(fontSize: 16)),
                subtitle: m.to != DateTime(m.from.year, m.from.month + 1, 0) ? Text('So far, to ${shortDate(m.to)}') : null,
                trailing: _period.kind == PeriodKind.pickedMonth && _period.from == m.from
                    ? const Icon(Icons.check, color: Palette.ink)
                    : null,
                onTap: () => Navigator.pop(context, m),
              ),
          ],
        ),
      ),
    );
    if (picked != null) _setPeriod(picked);
  }

  Future<void> _pickRange() async {
    final today = kigaliToday();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year - 3),
      lastDate: today,
      initialDateRange: DateTimeRange(start: _period.from, end: _period.to),
      helpText: 'Report period',
      saveText: 'Show',
    );
    if (range != null) _setPeriod(ReportPeriod.custom(range.start, range.end, kigaliToday()));
  }

  /// All on → just this one; then each tap adds or removes one (never the last).
  void _tapVehicle(String id, List<ReportVehicle> all) {
    final ids = {for (final v in all) v.id};
    final current = _only?.where(ids.contains).toSet();
    setState(() {
      if (current == null || current.isEmpty || current.length == ids.length) {
        _only = {id};
      } else if (current.contains(id)) {
        if (current.length > 1) _only = current..remove(id);
      } else {
        current.add(id);
        _only = current.length == ids.length ? null : current;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = _data, dataPeriod = _dataPeriod;
    final collections = data == null || dataPeriod == null
        ? null
        : CollectionsReport.build(
            data,
            dataPeriod,
            only: _only,
            owed: {for (final v in _repo.vehicles) v.id: _repo.today[v.id]?.overdue ?? 0},
          );
    final deposits = data == null || dataPeriod == null ? null : DepositsReport.build(data, dataPeriod);
    final current = dataPeriod == _period;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          await _repo.load();
          await _load();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 18, 0, 28),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('Reports', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, label: Text('Collections')),
                    ButtonSegment(value: true, label: Text('Deposits')),
                  ],
                  selected: {_depositsTab},
                  onSelectionChanged: (s) => setState(() => _depositsTab = s.first),
                ),
              ),
            ),
            const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 8), child: SectionLabel('Period')),
            _ChipRow(children: _periodChips()),
            if (!_depositsTab && collections != null && collections.vehicles.length > 1) ...[
              const Padding(padding: EdgeInsets.fromLTRB(16, 14, 16, 8), child: SectionLabel('Vehicles')),
              _ChipRow(children: _vehicleChips(collections)),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                [_period.label, if (_whoLabel(collections) case final w?) w].join(' · '),
                style: const TextStyle(fontSize: 13, color: Palette.ink2),
              ),
            ),
            SizedBox(
              height: 12,
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.fromLTRB(16, 5, 16, 5),
                      child: LinearProgressIndicator(minHeight: 2),
                    )
                  : null,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _Note(text: _error!, icon: Icons.cloud_off, color: Palette.bad),
              ),
            if (collections != null && deposits != null)
              AnimatedOpacity(
                opacity: current ? 1 : 0.35,
                duration: const Duration(milliseconds: 150),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _depositsTab
                      ? _DepositsView(report: deposits, repo: _repo)
                      : _CollectionsView(report: collections, repo: _repo),
                ),
              )
            else if (_loading)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
          ],
        ),
      ),
    );
  }

  String? _whoLabel(CollectionsReport? c) {
    if (_depositsTab) return 'all vehicles';
    if (c == null || c.vehicles.isEmpty) return null;
    if (c.rows.length == c.vehicles.length) {
      return c.vehicles.length == 1 ? '1 vehicle' : 'all ${c.vehicles.length} vehicles';
    }
    return c.rows.map((r) => r.vehicle.plate).join(', ');
  }

  List<Widget> _periodChips() {
    final today = kigaliToday();
    final k = _period.kind;
    return [
      ChoiceChip(
        label: const Text('Today'),
        selected: k == PeriodKind.today,
        onSelected: (_) => _setPeriod(ReportPeriod.today(today)),
      ),
      ChoiceChip(
        label: const Text('This week'),
        selected: k == PeriodKind.week,
        onSelected: (_) => _setPeriod(ReportPeriod.thisWeek(today)),
      ),
      ChoiceChip(
        label: const Text('This month'),
        selected: k == PeriodKind.month,
        onSelected: (_) => _setPeriod(ReportPeriod.thisMonth(today)),
      ),
      _IconChoiceChip(
        label: k == PeriodKind.pickedMonth ? _period.monthLabel : 'Pick month',
        selected: k == PeriodKind.pickedMonth,
        trailing: Icons.expand_more,
        onTap: _pickMonth,
      ),
      _IconChoiceChip(
        label: k == PeriodKind.custom ? 'Custom' : 'Custom range',
        selected: k == PeriodKind.custom,
        leading: Icons.calendar_today_outlined,
        onTap: _pickRange,
      ),
    ];
  }

  List<Widget> _vehicleChips(CollectionsReport c) {
    final all = c.rows.length == c.vehicles.length;
    final chosen = {for (final r in c.rows) r.vehicle.id};
    return [
      ChoiceChip(label: const Text('All vehicles'), selected: all, onSelected: (_) => setState(() => _only = null)),
      for (final v in c.vehicles)
        ChoiceChip(
          label: Text(v.isActive ? v.plate : '${v.plate} (off)'),
          selected: !all && chosen.contains(v.id),
          onSelected: (_) => _tapVehicle(v.id, c.vehicles),
        ),
    ];
  }
}

// ---------------------------------------------------------------------------
// Collections
// ---------------------------------------------------------------------------

class _CollectionsView extends StatelessWidget {
  const _CollectionsView({required this.report, required this.repo});
  final CollectionsReport report;
  final Repo repo;

  @override
  Widget build(BuildContext context) {
    final r = report;
    if (r.vehicles.isEmpty) {
      return const _Note(
        text: 'Nothing was due and nothing was paid in this period.',
        icon: Icons.info_outline,
        color: Palette.ink2,
      );
    }
    final rate = r.rate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _KpiGrid([
          _Kpi('Collected', rwf(r.collected), sub: 'RWF, of ${rwf(r.expected)} expected'),
          _Kpi('Collection rate', rate == null ? '–' : '$rate%', bar: rate == null ? null : rate / 100),
          _Kpi('Days missed', '${r.missed}', sub: 'due days with nothing sent'),
          _Kpi('Paid late', '${r.late}', sub: 'days cleared after their date'),
          _Kpi(
            'Owed now',
            rwf(r.owedNow),
            sub: 'RWF overdue, all dates',
            color: r.owedNow > 0 ? Palette.bad : null,
          ),
          _Kpi('Rest days', '${r.rest}', sub: 'no payment expected'),
        ]),
        const SizedBox(height: 10),
        _Note(
          text: r.insight,
          icon: r.missed > 0 ? Icons.warning_amber_rounded : Icons.check_circle_outline,
          color: r.missed > 0 ? Palette.bad : Palette.ok,
        ),
        if (r.buckets.length >= 2) ...[const SizedBox(height: 12), _CollectedChart(report: r)],
        const SizedBox(height: 12),
        _ByVehicle(report: r, repo: repo),
        if (r.showCalendar) ...[const SizedBox(height: 12), _Calendar(report: r)],
        const SizedBox(height: 12),
        _SummaryTable(report: r),
      ],
    );
  }
}

class _CollectedChart extends StatelessWidget {
  const _CollectedChart({required this.report});
  final CollectionsReport report;

  static const _h = 140.0;

  @override
  Widget build(BuildContext context) {
    final buckets = report.buckets;
    final peak = buckets.fold(0, (m, b) => math.max(m, math.max(b.collected, b.expected)));
    final top = niceTop(peak);
    final title = switch (report.bucketSize) {
      BucketSize.day => 'Collected per day',
      BucketSize.week => 'Collected per week',
      BucketSize.month => 'Collected per month',
    };
    final best = buckets.fold(0, (m, b) => math.max(m, b.collected));
    double h(int v) => v / top * _h;

    return _Card(
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: _title)),
            const Text('RWF', style: _small),
          ],
        ),
        const SizedBox(height: 8),
        const Wrap(
          spacing: 16,
          children: [
            _Key(color: Palette.ink, text: 'Collected'),
            _Key(color: Palette.rest, text: 'Expected'),
          ],
        ),
        const SizedBox(height: 14),
        Semantics(
          label: '$title. Highest ${rwf(best)} RWF.',
          child: ExcludeSemantics(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 30,
                  height: _h,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Transform.translate(offset: const Offset(0, -6), child: Text(compactRwf(top), style: _axis)),
                      Text(compactRwf(top / 2), style: _axis),
                      Transform.translate(offset: const Offset(0, 6), child: const Text('0', style: _axis)),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final slot = c.maxWidth / buckets.length;
                      final gap = slot > 8 ? 2.0 : 1.0;
                      return SizedBox(
                        height: _h + 20,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            const Positioned(left: 0, right: 0, top: 0, child: _Line(Palette.divider)),
                            const Positioned(left: 0, right: 0, top: _h / 2, child: _Line(Palette.divider)),
                            for (final (i, b) in buckets.indexed) ...[
                              Positioned(
                                left: i * slot + gap / 2,
                                width: slot - gap,
                                top: _h - h(b.expected),
                                height: h(b.expected),
                                child: const _BarTop(color: Palette.rest),
                              ),
                              Positioned(
                                left: i * slot + gap / 2 + (slot > 6 ? 1 : 0),
                                width: slot - gap - (slot > 6 ? 2 : 0),
                                top: _h - h(b.collected),
                                height: h(b.collected),
                                child: const _BarTop(color: Palette.ink),
                              ),
                              if (b.label.isNotEmpty)
                                Positioned(
                                  left: i * slot,
                                  top: _h + 6,
                                  child: Text(b.label, style: _axis, softWrap: false),
                                ),
                            ],
                            const Positioned(left: 0, right: 0, top: _h - 1, child: _Line(Palette.control)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BarTop extends StatelessWidget {
  const _BarTop({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.vertical(top: Radius.circular(2))),
  );
}

class _ByVehicle extends StatelessWidget {
  const _ByVehicle({required this.report, required this.repo});
  final CollectionsReport report;
  final Repo repo;

  @override
  Widget build(BuildContext context) => _Card(
    children: [
      const Text('By vehicle', style: _title),
      const SizedBox(height: 4),
      const Text('Collected against expected. Tap one to open it.', style: _small),
      for (final row in report.rows) _VehicleBar(row: row, repo: repo),
    ],
  );
}

class _VehicleBar extends StatelessWidget {
  const _VehicleBar({required this.row, required this.repo});
  final VehicleTotals row;
  final Repo repo;

  @override
  Widget build(BuildContext context) {
    final v = row.vehicle;
    final rate = row.rate;
    final open = repo.vehicleById(v.id) == null
        ? null
        : () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => VehicleDetailScreen(repo: repo, vehicleId: v.id)));
    return InkWell(
      onTap: open,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(v.plate, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    v.isActive ? v.driverName : '${v.driverName} · switched off',
                    style: const TextStyle(fontSize: 13, color: Palette.ink2),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  rate == null ? '–' : '$rate%',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, fontFeatures: tabular),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: ((rate ?? 0) / 100).clamp(0.0, 1.0),
                minHeight: 10,
                backgroundColor: Palette.rest,
                color: Palette.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text('${rwf(row.collected)} of ${rwf(row.expected)} RWF', style: _small),
          ],
        ),
      ),
    );
  }
}

class _Calendar extends StatelessWidget {
  const _Calendar({required this.report});
  final CollectionsReport report;

  static const _legend = [
    (DayCell.ok, 'On time'),
    (DayCell.late, 'Paid late'),
    (DayCell.part, 'Partly paid'),
    (DayCell.miss, 'Unpaid'),
    (DayCell.due, 'Due, not yet paid'),
    (DayCell.rest, 'Rest day'),
    (DayCell.none, 'Nothing due'),
  ];

  @override
  Widget build(BuildContext context) {
    final r = report;
    final blanks = r.period.from.weekday - 1;
    final shown = {for (final cells in r.calendar.values) ...cells};
    return _Card(
      children: [
        const Text('Payment calendar', style: _title),
        const SizedBox(height: 4),
        const Text('Each square is one day, Monday first', style: _small),
        const SizedBox(height: 14),
        Wrap(
          spacing: 18,
          runSpacing: 16,
          children: [
            for (final row in r.rows)
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.vehicle.plate, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: 7 * 12 + 6 * 2,
                    child: Wrap(
                      spacing: 2,
                      runSpacing: 2,
                      children: [
                        for (var i = 0; i < blanks; i++) const SizedBox(width: 12, height: 12),
                        for (final cell in r.calendar[row.vehicle.id]!) DaySquare(cell: cell, size: 12),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 14,
          runSpacing: 8,
          children: [
            for (final (cell, text) in _legend)
              if (shown.contains(cell))
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DaySquare(cell: cell, size: 12),
                    const SizedBox(width: 6),
                    Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Palette.ink2)),
                  ],
                ),
          ],
        ),
      ],
    );
  }
}

class _SummaryTable extends StatelessWidget {
  const _SummaryTable({required this.report});
  final CollectionsReport report;

  @override
  Widget build(BuildContext context) {
    String rate(int? r) => r == null ? '–' : '$r%';
    return _Card(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      children: [
        const Padding(padding: EdgeInsets.fromLTRB(0, 10, 0, 8), child: Text('Summary', style: _title)),
        const _TableRow(['Vehicle', 'Collected', 'Rate', 'Missed', 'Late'], header: true),
        for (final row in report.rows)
          _TableRow([row.vehicle.plate, rwf(row.collected), rate(row.rate), '${row.missed}', '${row.late}']),
        if (report.rows.length > 1)
          _TableRow([
            'Total',
            rwf(report.collected),
            rate(report.rate),
            '${report.missed}',
            '${report.late}',
          ], bold: true),
      ],
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow(this.cells, {this.header = false, this.bold = false});
  final List<String> cells;
  final bool header;
  final bool bold;

  static const _flex = [27, 25, 14, 15, 12];

  @override
  Widget build(BuildContext context) {
    final style = header
        ? const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Palette.ink3)
        : TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w700 : FontWeight.w400, fontFeatures: tabular);
    return Container(
      padding: EdgeInsets.only(top: header ? 4 : 11, bottom: 11),
      decoration: header ? null : const BoxDecoration(border: Border(top: BorderSide(color: Palette.divider))),
      child: Row(
        children: [
          for (final (i, c) in cells.indexed)
            Expanded(
              flex: _flex[i],
              child: Text(
                c,
                textAlign: i == 0 ? TextAlign.left : TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: i == 0 && !header ? style.copyWith(fontWeight: FontWeight.w600) : style,
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Deposits
// ---------------------------------------------------------------------------

class _DepositsView extends StatelessWidget {
  const _DepositsView({required this.report, required this.repo});
  final DepositsReport report;
  final Repo repo;

  @override
  Widget build(BuildContext context) {
    final r = report;
    final month = r.period.monthName;
    final n = r.history.length;
    final left = r.notDeposited;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _KpiGrid([
          _Kpi('Collected', rwf(r.collected), sub: 'RWF received in ${month ?? 'this period'}'),
          _Kpi(
            'Deposited',
            rwf(r.deposited),
            color: n == 0 ? null : Palette.blue,
            sub: n == 0 ? 'no deposits in ${month ?? 'this period'}' : 'RWF, $n deposit${n == 1 ? '' : 's'} to the bank',
          ),
          _Kpi('Fees', rwf(r.fees), sub: 'RWF in bank and transfer fees'),
          left >= 0
              ? _Kpi(
                  'Not deposited',
                  rwf(left),
                  color: left > 0 ? Palette.warn : null,
                  sub: "RWF of ${month == null ? "this period's" : "$month's"} money",
                )
              : _Kpi('Not deposited', '0', sub: 'Deposits also covered ${rwf(-left)} RWF collected earlier'),
        ]),
        const SizedBox(height: 12),
        _HeldNow(repo: repo),
        if (r.running.length >= 2) ...[const SizedBox(height: 12), _RunningChart(report: r)],
        const SizedBox(height: 12),
        _Card(
          padding: const EdgeInsets.fromLTRB(0, 6, 0, 6),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Row(
                children: [
                  const Expanded(child: Text('Deposit history', style: _title)),
                  Text(month ?? r.period.label, style: const TextStyle(fontSize: 13, color: Palette.ink2)),
                ],
              ),
            ),
            if (r.history.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text('No deposits in this period.', style: TextStyle(color: Palette.ink2)),
              ),
            for (final d in r.history) ...[const Divider(), DepositRow(repo: repo, deposit: d)],
          ],
        ),
      ],
    );
  }
}

/// What each member holds right now, whatever the period.
class _HeldNow extends StatelessWidget {
  const _HeldNow({required this.repo});
  final Repo repo;

  static const _shades = [Palette.ink, Color(0xFF6B7280), Palette.switchOff, Palette.rest];

  @override
  Widget build(BuildContext context) {
    final people = repo.balances.where((b) => b.held != 0).toList();
    final holding = people.where((b) => b.held > 0).toList();
    Color shade(int i) => _shades[i % _shades.length];
    return _Card(
      children: [
        const Row(
          children: [
            Expanded(child: Text('Held by members now', style: _title)),
            Text('all dates', style: _small),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              rwf(repo.notYetDeposited),
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.5, fontFeatures: tabular),
            ),
            const SizedBox(width: 6),
            const Text('RWF', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ],
        ),
        const Text('collected, not yet deposited', style: TextStyle(fontSize: 13, color: Palette.ink2)),
        if (holding.length > 1) ...[
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 10,
              child: Row(
                // Stretch: an empty ColoredBox is otherwise 0 high.
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, b) in holding.indexed) ...[
                    if (i > 0) const SizedBox(width: 2),
                    Expanded(flex: b.held, child: ColoredBox(color: shade(i))),
                  ],
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        for (final (i, b) in people.indexed)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: i == 0 ? null : const BoxDecoration(border: Border(top: BorderSide(color: Palette.divider))),
            child: Row(
              children: [
                if (holding.length > 1 && b.held > 0)
                  Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(color: shade(holding.indexOf(b)), borderRadius: BorderRadius.circular(3)),
                  ),
                Expanded(
                  child: Text(b.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                Text(
                  b.held < 0 ? '−${rwf(-b.held)}' : rwf(b.held),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    fontFeatures: tabular,
                    color: b.held < 0 ? Palette.warn : Palette.ink,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: () => showRecordDeposit(context, repo), child: const Text('Record deposit')),
      ],
    );
  }
}

class _RunningChart extends StatelessWidget {
  const _RunningChart({required this.report});
  final DepositsReport report;

  static const _h = 160.0;
  static const _gap = Color(0xFFFCE7C8);

  @override
  Widget build(BuildContext context) {
    final points = report.running;
    final peak = points.fold(0, (m, p) => math.max(m, math.max(p.$2, p.$3)));
    final top = niceTop(peak);
    final last = points.last;
    final n = points.length;
    final ticks = {0, n ~/ 4, n ~/ 2, 3 * n ~/ 4, n - 1}.toList()..sort();
    String tick(int i) {
      final d = points[i].$1;
      return i == 0 || i == n - 1 || d.month != points.first.$1.month ? dateOnlyLabel(d) : '${d.day}';
    }

    return _Card(
      children: [
        const Text('Collected vs deposited', style: _title),
        const SizedBox(height: 4),
        const Text('Running total over the period, RWF', style: _small),
        const SizedBox(height: 10),
        const Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _Key(color: Palette.ink, text: 'Collected', line: true),
            _Key(color: Palette.blue, text: 'Deposited, with fees', line: true),
            _Key(color: _gap, text: 'Not yet deposited'),
          ],
        ),
        const SizedBox(height: 14),
        Semantics(
          label:
              'By ${dateOnlyLabel(last.$1)}, ${rwf(last.$2)} RWF collected and ${rwf(last.$3)} RWF deposited with fees.',
          child: ExcludeSemantics(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 34,
                  height: _h,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Transform.translate(offset: const Offset(0, -6), child: Text(compactRwf(top), style: _axis)),
                      Text(compactRwf(top / 2), style: _axis),
                      Transform.translate(offset: const Offset(0, 6), child: const Text('0', style: _axis)),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    children: [
                      SizedBox(
                        height: _h,
                        width: double.infinity,
                        child: CustomPaint(painter: _RunningPainter(points, top, _gap)),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [for (final i in ticks) Text(tick(i), style: _axis)],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RunningPainter extends CustomPainter {
  _RunningPainter(this.points, this.top, this.gapColor);
  final List<(DateTime, int, int)> points;
  final int top;
  final Color gapColor;

  @override
  void paint(Canvas canvas, Size size) {
    final n = points.length;
    double x(int i) => n == 1 ? 0 : i * size.width / (n - 1);
    double y(int v) => size.height - v / top * size.height;

    final grid = Paint()
      ..color = Palette.divider
      ..strokeWidth = 1;
    canvas
      ..drawLine(Offset(0, 0.5), Offset(size.width, 0.5), grid)
      ..drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), grid);

    final collected = <Offset>[for (final (i, p) in points.indexed) Offset(x(i), y(p.$2))];
    // Deposits land on a day: draw them as steps.
    final deposited = <Offset>[Offset(x(0), y(points[0].$3))];
    for (var i = 1; i < n; i++) {
      deposited
        ..add(Offset(x(i), y(points[i - 1].$3)))
        ..add(Offset(x(i), y(points[i].$3)));
    }

    canvas.drawPath(
      Path()..addPolygon([...collected, ...deposited.reversed], true),
      Paint()..color = gapColor,
    );
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..drawLine(Offset(0, size.height - 0.5), Offset(size.width, size.height - 0.5), grid..color = Palette.control)
      ..drawPath(Path()..addPolygon(deposited, false), line..color = Palette.blue)
      ..drawPath(Path()..addPolygon(collected, false), line..color = Palette.ink);
  }

  @override
  bool shouldRepaint(_RunningPainter old) => old.points != points || old.top != top;
}

// ---------------------------------------------------------------------------
// Small pieces
// ---------------------------------------------------------------------------

class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      children: [
        for (final (i, c) in children.indexed) ...[if (i > 0) const SizedBox(width: 8), c],
      ],
    ),
  );
}

/// A chip that opens a picker, with an icon before or after the label.
class _IconChoiceChip extends StatelessWidget {
  const _IconChoiceChip({required this.label, required this.selected, required this.onTap, this.leading, this.trailing});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? leading;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : Palette.ink;
    return ChoiceChip(
      selected: selected,
      onSelected: (_) => onTap(),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[Icon(leading, size: 16, color: color), const SizedBox(width: 6)],
          Text(label),
          if (trailing != null) ...[const SizedBox(width: 4), Icon(trailing, size: 18, color: color)],
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children, this.padding = const EdgeInsets.all(16)});
  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: padding,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    ),
  );
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid(this.tiles);
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < tiles.length; i += 2) ...[
        if (i > 0) const SizedBox(height: 10),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: tiles[i]),
              const SizedBox(width: 10),
              Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox()),
            ],
          ),
        ),
      ],
    ],
  );
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value, {this.sub, this.color, this.bar});
  final String label;
  final String value;
  final String? sub;
  final Color? color;

  /// 0..1 for a small progress bar under the value.
  final double? bar;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Palette.surface,
      border: Border.all(color: Palette.border),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(label),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              color: color ?? Palette.ink,
              fontFeatures: tabular,
            ),
          ),
        ),
        if (bar case final b?) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: b.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: Palette.divider,
              color: Palette.ink,
            ),
          ),
        ],
        if (sub case final s?) ...[
          const SizedBox(height: 4),
          Text(s, style: const TextStyle(fontSize: 12, color: Palette.ink2, height: 1.35)),
        ],
      ],
    ),
  );
}

/// A one-line message with an icon (insight, empty or error).
class _Note extends StatelessWidget {
  const _Note({required this.text, required this.icon, required this.color});
  final String text;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: Palette.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Palette.control),
    ),
    child: Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 14, height: 1.35))),
      ],
    ),
  );
}

/// A legend entry: a square, or a short line for line charts.
class _Key extends StatelessWidget {
  const _Key({required this.color, required this.text, this.line = false});
  final Color color;
  final String text;
  final bool line;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: line ? 14 : 12,
        height: line ? 3 : 12,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(line ? 2 : 3)),
      ),
      const SizedBox(width: 6),
      Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Palette.ink2)),
    ],
  );
}

class _Line extends StatelessWidget {
  const _Line(this.color);
  final Color color;

  @override
  Widget build(BuildContext context) => Container(height: 1, color: color);
}
