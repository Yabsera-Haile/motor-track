import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repo.dart';
import '../format.dart';
import '../prefs.dart';
import '../theme.dart';
import 'message_driver_sheet.dart';
import 'vehicle_detail_screen.dart';

/// Recent alerts, the same ones every phone gets as notifications.
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key, required this.repo});
  final Repo repo;

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  /// What this phone had seen before opening the list: newer alerts get a "New" dot.
  final DateTime? _seenBefore = AppPrefs.alertsSeenAt;
  late Future<List<AlertItem>> _alerts = _load();

  // Seeing the list counts as reading the alerts: the bell on Home goes back to zero.
  Future<List<AlertItem>> _load() => widget.repo.alerts().then((rows) {
    if (rows.isNotEmpty) widget.repo.markAlertsSeen(rows.first.createdAt);
    return rows;
  });

  @override
  void initState() {
    super.initState();
    // Another phone's change (a payment resolving an alert, a new alert) reloads the repo.
    widget.repo.addListener(_reload);
  }

  @override
  void dispose() {
    widget.repo.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (mounted) setState(() => _alerts = _load());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Alerts')),
    body: RefreshIndicator(
      onRefresh: () async {
        _reload();
        await _alerts;
      },
      child: FutureBuilder<List<AlertItem>>(
        future: _alerts,
        builder: (context, snap) {
          if (!snap.hasData) {
            return snap.hasError
                ? ListView(
                    children: const [
                      Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(child: Text("Couldn't load alerts.")),
                      ),
                    ],
                  )
                : const Center(child: CircularProgressIndicator());
          }
          final rows = snap.data!;
          if (rows.isEmpty) {
            return ListView(
              children: const [
                Padding(
                  padding: EdgeInsets.all(40),
                  child: Text(
                    'No alerts yet. They appear here and as a notification on every phone.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Palette.ink2),
                  ),
                ),
              ],
            );
          }
          final items = <Widget>[];
          String? lastDay;
          for (final a in rows) {
            final at = toKigali(a.createdAt);
            final day = _dayLabel(at);
            if (day != lastDay) {
              items.add(Padding(padding: const EdgeInsets.fromLTRB(2, 16, 0, 8), child: SectionLabel(day)));
              lastDay = day;
            }
            items.add(
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AlertCard(
                  repo: widget.repo,
                  alert: a,
                  isNew: _seenBefore == null || a.createdAt.isAfter(_seenBefore),
                ),
              ),
            );
          }
          return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: items);
        },
      ),
    ),
  );

  static String _dayLabel(DateTime at) {
    final today = kigaliToday();
    final d = dateOnly(at);
    if (d == today) return 'Today';
    if (d == today.subtract(const Duration(days: 1))) return 'Yesterday · ${shortDate(d)}';
    return shortDate(d);
  }
}

class AlertCard extends StatelessWidget {
  const AlertCard({super.key, required this.repo, required this.alert, this.isNew = false});
  final Repo repo;
  final AlertItem alert;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    final a = alert;
    final resolved = a.resolvedAt != null;
    final vehicle = repo.vehicleById(a.vehicleId);
    final (icon, fg, bg) = switch (a.type) {
      'unpaid_deadline' || 'missed_day' => (Icons.event_busy, Palette.bad, Palette.badBg),
      'short_deadline' => (Icons.schedule, Palette.warn, Palette.warnBg),
      'overpayment' => (Icons.north_east, Palette.warn, Palette.warnBg),
      _ => (Icons.sensors_off, Palette.ink2, Palette.muteBg),
    };
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: vehicle == null
            ? null
            : () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => VehicleDetailScreen(repo: repo, vehicleId: vehicle.id),
                ),
              ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 20, color: fg),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (isNew)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: const BoxDecoration(color: Palette.bad, shape: BoxShape.circle),
                          ),
                        Expanded(
                          child: Text(
                            a.title,
                            semanticsLabel: isNew ? 'New: ${a.title}' : a.title,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(kigaliTime(a.createdAt), style: const TextStyle(fontSize: 13, color: Palette.ink2)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(a.body, style: const TextStyle(fontSize: 14, color: Palette.ink2, height: 1.45)),
                    if (resolved || (a.aboutDriver && vehicle != null)) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (resolved)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: const ShapeDecoration(color: Palette.okBg, shape: StadiumBorder()),
                              child: Text(
                                'Resolved ${kigaliTime(a.resolvedAt!)}',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Palette.ok),
                              ),
                            ),
                          if (a.aboutDriver && vehicle != null && !resolved)
                            OutlinedButton.icon(
                              onPressed: () => showMessageDriverForAlert(context, repo, a),
                              icon: const Icon(Icons.sms_outlined, size: 18),
                              label: const Text('Message driver'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 38),
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
