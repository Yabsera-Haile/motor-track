import 'package:flutter/material.dart';

import '../data/repo.dart';
import '../format.dart';
import '../theme.dart';

/// Recent alerts. Messaging the driver from here comes with the alerts milestone.
class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key, required this.repo});
  final Repo repo;

  Future<List<Map<String, dynamic>>> _load() => repo.client
      .from('alerts')
      .select('id, type, title, body, created_at, resolved_at')
      .order('created_at', ascending: false)
      .limit(100);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Alerts')),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _load(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return snap.hasError
              ? const Center(child: Text("Couldn't load alerts."))
              : const Center(child: CircularProgressIndicator());
        }
        final rows = snap.data!;
        if (rows.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No alerts yet. They appear here and on every phone.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Palette.ink2),
              ),
            ),
          );
        }
        final items = <Widget>[];
        String? lastDay;
        for (final r in rows) {
          final at = toKigali(DateTime.parse(r['created_at'] as String));
          final day = _dayLabel(at);
          if (day != lastDay) {
            items.add(Padding(padding: const EdgeInsets.fromLTRB(2, 16, 0, 8), child: SectionLabel(day)));
            lastDay = day;
          }
          items.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _AlertCard(row: r, at: at),
            ),
          );
        }
        return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: items);
      },
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

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.row, required this.at});
  final Map<String, dynamic> row;
  final DateTime at;

  @override
  Widget build(BuildContext context) {
    final type = row['type'] as String;
    final resolved = row['resolved_at'] != null;
    final (icon, fg, bg) = switch (type) {
      'unpaid_deadline' || 'missed_day' => (Icons.event_busy, Palette.bad, Palette.badBg),
      'short_deadline' => (Icons.schedule, Palette.warn, Palette.warnBg),
      'overpayment' => (Icons.north_east, Palette.warn, Palette.warnBg),
      _ => (Icons.sensors_off, Palette.ink2, Palette.muteBg),
    };
    return Card(
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
                      Expanded(
                        child: Text(
                          row['title'] as String,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(kigaliTime(at), style: const TextStyle(fontSize: 13, color: Palette.ink2)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(row['body'] as String, style: const TextStyle(fontSize: 14, color: Palette.ink2, height: 1.45)),
                  if (resolved) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: const ShapeDecoration(color: Palette.okBg, shape: StadiumBorder()),
                      child: Text(
                        'Resolved ${kigaliTime(DateTime.parse(row['resolved_at'] as String))}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Palette.ok),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
