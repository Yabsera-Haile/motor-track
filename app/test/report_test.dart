import 'package:flutter_test/flutter_test.dart';
import 'package:motor_track/data/card_state.dart';
import 'package:motor_track/data/models.dart';
import 'package:motor_track/data/report.dart';

/// October 2026 from the design: three bikes at 6,000 a day. RD 482 K pays
/// every day; the other two rest on Sundays and miss a few days.
final v1 = ReportVehicle(id: 'v1', plate: 'RD 482 K', driverName: 'Emmanuel', startDate: oct(1));
final v2 = ReportVehicle(id: 'v2', plate: 'RE 115 C', driverName: 'Eric', startDate: oct(1));
final v3 = ReportVehicle(id: 'v3', plate: 'RD 907 F', driverName: 'Patrick', startDate: oct(1));

final october = ReportPeriod.month(2026, 10, DateTime(2026, 11, 4));

DateTime oct(int d) => DateTime(2026, 10, d);

ReportData octoberData({List<Deposit> deposits = const []}) {
  final dues = <ReportDue>[];
  final payments = <ReportPayment>[];
  void day(String id, int d, int sent, {bool rest = false, DueStatus? status}) {
    dues.add(
      ReportDue(
        vehicleId: id,
        day: oct(d),
        amountDue: rest ? 0 : 6000,
        status: rest ? DueStatus.rest : status ?? DueStatus.onTime,
        sentInPeriod: sent,
      ),
    );
    if (sent > 0) payments.add(ReportPayment(vehicleId: id, amount: sent, day: oct(d)));
  }

  final v2Sent = {7: 0, 8: 12000, 20: 0, 22: 12000, 28: 3000, 29: 9000};
  const v2Late = {7, 20, 21, 28};
  final v3Sent = {14: 0, 15: 12000, 21: 0, 23: 12000, 30: 0, 31: 0};
  const v3Late = {14, 21, 22, 30, 31};
  for (var d = 1; d <= 31; d++) {
    final sunday = oct(d).weekday == DateTime.sunday;
    day('v1', d, 6000);
    if (sunday) {
      day('v2', d, 0, rest: true);
      day('v3', d, 0, rest: true);
    } else {
      day('v2', d, v2Sent[d] ?? 6000, status: v2Late.contains(d) ? DueStatus.late : null);
      day('v3', d, v3Sent[d] ?? 6000, status: v3Late.contains(d) ? DueStatus.late : null);
    }
  }
  return ReportData(vehicles: [v1, v2, v3], dues: dues, payments: payments, deposits: deposits);
}

Deposit deposit(String member, int day, int amount, {int fee = 500}) => Deposit(
  id: '$member-$day',
  memberId: member,
  amount: amount,
  fee: fee,
  depositedOn: oct(day),
);

void main() {
  group('periods', () {
    final today = DateTime(2026, 11, 4); // a Wednesday

    test('this week starts on Monday, this month on the 1st', () {
      expect(ReportPeriod.thisWeek(today).from, DateTime(2026, 11, 2));
      expect(ReportPeriod.thisMonth(today).from, DateTime(2026, 11, 1));
      expect(ReportPeriod.thisMonth(today).dayCount, 4);
    });

    test('a past month is whole; the current one stops at today', () {
      expect(october.from, oct(1));
      expect(october.to, oct(31));
      expect(october.dayCount, 31);
      expect(october.label, '1 – 31 Oct 2026');
      expect(october.monthLabel, 'October 2026');
      expect(ReportPeriod.month(2026, 11, today).to, today);
    });

    test('a custom range never goes past today', () {
      final p = ReportPeriod.custom(DateTime(2026, 9, 28), DateTime(2026, 12, 1), today);
      expect(p.to, today);
      expect(p.label, '28 Sep – 4 Nov 2026');
      expect(rangeLabel(today, today), 'Wed 4 Nov 2026');
      expect(rangeLabel(DateTime(2025, 12, 28), DateTime(2026, 1, 4)), '28 Dec 2025 – 4 Jan 2026');
    });

    test('today, this week and this month move with the date', () {
      expect(ReportPeriod.today(today).refreshed(DateTime(2026, 11, 5)).from, DateTime(2026, 11, 5));
      expect(october.refreshed(DateTime(2026, 12, 1)), october);
    });
  });

  group('collections', () {
    test('October in the design: totals and counts', () {
      final r = CollectionsReport.build(octoberData(), october, owed: {'v3': 6000});
      expect(r.collected, 498000);
      expect(r.expected, 186000 + 162000 + 162000);
      expect(r.rate, 98);
      expect(r.missed, 6); // Eric 7 + 20, Patrick 14, 21, 30, 31
      expect(r.late, 9);
      expect(r.rest, 8);
      expect(r.owedNow, 6000);
      expect(r.insight, 'Most missed days: RD 907 F, 4 days with nothing sent.');
    });

    test('per vehicle, sorted by plate', () {
      final r = CollectionsReport.build(octoberData(), october);
      expect(r.rows.map((x) => x.vehicle.plate), ['RD 482 K', 'RD 907 F', 'RE 115 C']);
      final patrick = r.rows[1];
      expect([patrick.collected, patrick.expected, patrick.rate, patrick.missed, patrick.late], [
        150000,
        162000,
        93,
        4,
        5,
      ]);
    });

    test('choosing vehicles narrows every number', () {
      final r = CollectionsReport.build(octoberData(), october, only: {'v2'}, owed: {'v3': 6000});
      expect(r.rows.single.vehicle.plate, 'RE 115 C');
      expect(r.collected, 162000);
      expect(r.rate, 100);
      expect(r.owedNow, 0);
      expect(r.insight, '2 days with nothing sent.');
      expect(r.vehicles.length, 3, reason: 'the chips still offer all three');
    });

    test('a choice that no longer applies falls back to all vehicles', () {
      final r = CollectionsReport.build(octoberData(), october, only: {'gone'});
      expect(r.rows.length, 3);
    });

    test('a day paid ahead by credit is not missed; nothing sent but covered late is', () {
      ReportDue due(DueStatus s, {int sent = 0}) =>
          ReportDue(vehicleId: 'v', day: oct(1), amountDue: 6000, status: s, sentInPeriod: sent);
      final ahead = due(DueStatus.onTime);
      final behind = due(DueStatus.late);
      final sentForOlder = due(DueStatus.unpaid, sent: 6000);
      final today = due(DueStatus.open);
      expect([ahead.missed, behind.missed, sentForOlder.missed, today.missed], [false, true, false, false]);
    });

    test('daily bars for a month, labelled every 7 days', () {
      final r = CollectionsReport.build(octoberData(), october);
      expect(r.bucketSize, BucketSize.day);
      expect(r.buckets.length, 31);
      expect(r.buckets.where((b) => b.label.isNotEmpty).map((b) => b.label), ['1', '8', '15', '22', '29']);
      expect(r.buckets[7].collected, 6000 + 12000 + 6000); // 8 Oct
      expect(r.buckets[3].expected, 6000); // Sun 4 Oct: only RD 482 K works
    });

    test('weekly bars from 46 days, monthly from 184', () {
      final today = DateTime(2026, 11, 4);
      final sixWeeks = ReportPeriod.custom(DateTime(2026, 9, 20), today, today);
      expect(sixWeeks.dayCount, 46);
      final r = CollectionsReport.build(octoberData(), sixWeeks);
      expect(r.bucketSize, BucketSize.week);
      expect(r.buckets.first.start, DateTime(2026, 9, 14), reason: 'weeks start on Monday');
      expect(r.buckets.length, 8);
      expect(r.buckets.where((b) => b.label.isNotEmpty).map((b) => b.label), ['20 Sep', '28 Sep', '12 Oct', '26 Oct']);
      expect(r.collected, 498000);
      expect(r.showCalendar, true);
      final nineWeeks = ReportPeriod.custom(DateTime(2026, 9, 1), today, today);
      expect(CollectionsReport.build(octoberData(), nineWeeks).showCalendar, false);
      final year = ReportPeriod.custom(DateTime(2025, 11, 5), today, today);
      final byMonth = CollectionsReport.build(octoberData(), year);
      expect(byMonth.bucketSize, BucketSize.month);
      expect(byMonth.buckets.length, 13);
      expect(byMonth.buckets.where((b) => b.label.isNotEmpty).first.label, 'Nov');
      expect(byMonth.collected, 498000);
      expect(CollectionsReport.build(octoberData(), year).showCalendar, false);
    });

    test('calendar squares follow each day', () {
      final r = CollectionsReport.build(octoberData(), october);
      final eric = r.calendar['v2']!;
      expect(eric.length, 31);
      expect(eric[3], DayCell.rest); // Sun 4 Oct
      expect(eric[6], DayCell.late); // 7 Oct
      expect(eric[7], DayCell.ok);
    });

    test('switched-off vehicles stay listed (last); ones not started yet are left out', () {
      final off = ReportVehicle(
        id: 'off',
        plate: 'RA 100 A',
        driverName: 'Jean',
        startDate: DateTime(2026, 9, 1),
        isActive: false,
      );
      final later = ReportVehicle(id: 'new', plate: 'RF 230 A', driverName: 'Eric', startDate: DateTime(2026, 11, 3));
      final r = CollectionsReport.build(
        ReportData(
          vehicles: [off, later, v1],
          dues: const [],
          payments: [ReportPayment(vehicleId: 'v1', amount: 6000, day: oct(2))],
          deposits: const [],
        ),
        october,
        owed: {'off': 12000},
      );
      expect(r.vehicles.map((v) => v.plate), ['RD 482 K', 'RA 100 A']);
      expect(r.rows.last.collected, 0);
      expect(r.owedNow, 12000, reason: 'a switched-off bike can still owe');
      expect(r.rate, null, reason: 'nothing was expected');
    });

    test("deleted vehicles (not in the list) don't count anywhere", () {
      final data = ReportData(
        vehicles: [v1],
        dues: [ReportDue(vehicleId: 'deleted', day: oct(3), amountDue: 6000, status: DueStatus.unpaid)],
        payments: [
          ReportPayment(vehicleId: 'deleted', amount: 6000, day: oct(1)),
          ReportPayment(vehicleId: 'v1', amount: 6000, day: oct(1)),
        ],
        deposits: const [],
      );
      final r = CollectionsReport.build(data, october, owed: {'deleted': 6000});
      expect(r.vehicles.map((v) => v.plate), ['RD 482 K']);
      expect([r.collected, r.expected, r.missed, r.owedNow], [6000, 0, 0, 0]);
      expect(DepositsReport.build(data, october).collected, 6000);
    });
  });

  group('deposits', () {
    final deposits = [
      deposit('aline', 10, 100000),
      deposit('kevin', 15, 60000),
      deposit('aline', 20, 100000),
      deposit('kevin', 30, 60000),
      deposit('aline', 31, 100000),
    ];

    test('October in the design', () {
      final r = DepositsReport.build(octoberData(deposits: deposits), october);
      expect([r.collected, r.deposited, r.fees, r.notDeposited], [498000, 420000, 2500, 75500]);
      expect(r.history.map((d) => d.depositedOn.day), [31, 30, 20, 15, 10]);
    });

    test('running totals include fees, so the gap is what is left', () {
      final r = DepositsReport.build(octoberData(deposits: deposits), october);
      expect(r.running.length, 31);
      final (day, collected, out) = r.running.last;
      expect(day, oct(31));
      expect(collected, 498000);
      expect(out, 422500);
      expect(r.running[9].$3, 100500); // 10 Oct
      expect(r.running[8].$3, 0);
    });

    test('depositing older money makes "not deposited" negative', () {
      final week = ReportPeriod.custom(oct(29), oct(31), DateTime(2026, 11, 4));
      final r = DepositsReport.build(octoberData(deposits: deposits), week);
      // 29–31 Oct: RD 482 K 3 × 6,000; RE 115 C 9,000 + 6,000 + 6,000; RD 907 F 6,000.
      expect(r.collected, 18000 + 21000 + 6000);
      expect(r.deposited, 160000);
      expect(r.notDeposited, lessThan(0));
    });
  });

  test('chart helpers', () {
    expect(niceTop(24000), 24000);
    expect(niceTop(19000), 20000);
    expect(niceTop(498000), 500000);
    expect(niceTop(0), 6000);
    expect(compactRwf(24000), '24k');
    expect(compactRwf(12500), '12.5k');
    expect(compactRwf(1500000), '1.5M');
    expect(compactRwf(0), '0');
    expect(percent(498000, 510000), 98);
    expect(percent(1, 0), null);
  });
}
