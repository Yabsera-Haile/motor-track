import 'dart:math' as math;

import 'package:intl/intl.dart';

import '../format.dart';
import 'card_state.dart' show DayCell;
import 'history.dart' show cellForStatus;
import 'models.dart';

// ---------------------------------------------------------------------------
// The period a report covers
// ---------------------------------------------------------------------------

enum PeriodKind { today, week, month, pickedMonth, custom }

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// The days a report covers: Kigali dates, both ends included, never past today.
class ReportPeriod {
  const ReportPeriod._(this.kind, this.from, this.to);

  final PeriodKind kind;
  final DateTime from;
  final DateTime to;

  factory ReportPeriod.today(DateTime today) => ReportPeriod._(PeriodKind.today, today, today);

  /// Monday to today.
  factory ReportPeriod.thisWeek(DateTime today) =>
      ReportPeriod._(PeriodKind.week, DateTime(today.year, today.month, today.day - (today.weekday - 1)), today);

  /// The 1st to today.
  factory ReportPeriod.thisMonth(DateTime today) =>
      ReportPeriod._(PeriodKind.month, DateTime(today.year, today.month), today);

  /// A whole month, cut at today when it is the current one.
  factory ReportPeriod.month(int year, int month, DateTime today) {
    final last = DateTime(year, month + 1, 0);
    return ReportPeriod._(PeriodKind.pickedMonth, DateTime(year, month), last.isAfter(today) ? today : last);
  }

  factory ReportPeriod.custom(DateTime from, DateTime to, DateTime today) {
    final a = dateOnly(from), b = dateOnly(to);
    return ReportPeriod._(PeriodKind.custom, a, b.isAfter(today) ? today : b);
  }

  /// "Today", "This week" and "This month" move with the date; the others stay put.
  ReportPeriod refreshed(DateTime today) => switch (kind) {
    PeriodKind.today => ReportPeriod.today(today),
    PeriodKind.week => ReportPeriod.thisWeek(today),
    PeriodKind.month => ReportPeriod.thisMonth(today),
    _ => this,
  };

  int get dayCount => daysBetween(from, to) + 1;

  List<DateTime> get days => List.generate(dayCount, (i) => DateTime(from.year, from.month, from.day + i));

  bool contains(DateTime day) => !day.isBefore(from) && !day.isAfter(to);

  /// "1 – 31 Oct 2026"
  String get label => rangeLabel(from, to);

  /// "October 2026"
  String get monthLabel => DateFormat('MMMM yyyy', 'en_US').format(from);

  /// "October" for a month, otherwise null.
  String? get monthName => kind == PeriodKind.pickedMonth || kind == PeriodKind.month
      ? DateFormat('MMMM', 'en_US').format(from)
      : null;

  @override
  bool operator ==(Object other) => other is ReportPeriod && other.kind == kind && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(kind, from, to);
}

/// Whole days from [a] to [b], ignoring the phone's daylight saving.
int daysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

/// "Wed 4 Nov 2026", "1 – 31 Oct 2026", "28 Sep – 4 Nov 2026", "28 Dec 2025 – 4 Jan 2026".
String rangeLabel(DateTime a, DateTime b) {
  String dm(DateTime d) => '${d.day} ${_months[d.month - 1]}';
  if (a == b) return '${weekdayShort[a.weekday - 1]} ${dm(a)} ${a.year}';
  if (a.year == b.year && a.month == b.month) return '${a.day} – ${dm(b)} ${b.year}';
  if (a.year == b.year) return '${dm(a)} – ${dm(b)} ${b.year}';
  return '${dm(a)} ${a.year} – ${dm(b)} ${b.year}';
}

/// 24000 -> "24k", 1500000 -> "1.5M", for chart axes.
String compactRwf(num n) {
  String trim(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  if (n.abs() >= 1000000) return '${trim(n / 1000000)}M';
  if (n.abs() >= 1000) return '${trim(n / 1000)}k';
  return trim(n.toDouble());
}

/// A round axis top at or above [peak] whose half is round too.
int niceTop(int peak) {
  if (peak <= 0) return 6000;
  final unit = math.pow(10, (math.log(peak) / math.ln10).floor()).toDouble();
  for (final m in const [1, 1.2, 1.6, 2, 2.4, 3, 4, 5, 6, 8, 10]) {
    // 2.4 × 10,000 can come out a hair under 24,000 in floating point.
    if (m * unit + 1e-6 >= peak) return (m * unit).round();
  }
  return (10 * unit).round();
}

/// [a] as a whole percentage of [b]; null when nothing was expected.
int? percent(int a, int b) => b == 0 ? null : (a * 100 / b).round();

// ---------------------------------------------------------------------------
// Rows fetched for a report
// ---------------------------------------------------------------------------

/// A vehicle that isn't deleted. Deleting is for mistakes, so deleted
/// vehicles and their money are left out of reports entirely.
class ReportVehicle {
  const ReportVehicle({
    required this.id,
    required this.plate,
    required this.driverName,
    required this.startDate,
    this.isActive = true,
  });

  final String id;
  final String plate;
  final String driverName;
  final DateTime startDate;

  /// Switched off: still listed, with whatever it owed or paid.
  final bool isActive;

  static const columns = 'id, plate, driver_name, start_date, is_active';

  factory ReportVehicle.fromRow(Map<String, dynamic> r) => ReportVehicle(
    id: r['id'] as String,
    plate: r['plate'] as String,
    driverName: r['driver_name'] as String,
    startDate: parseDate(r['start_date'] as String),
    isActive: r['is_active'] as bool,
  );
}

/// One day (or week, or month) a vehicle owed, from v_dues.
class ReportDue {
  const ReportDue({
    required this.vehicleId,
    required this.day,
    required this.amountDue,
    required this.status,
    this.sentInPeriod = 0,
  });

  final String vehicleId;
  final DateTime day;
  final int amountDue;
  final DueStatus status;

  /// Money the driver sent during this due's period, wherever it went.
  final int sentInPeriod;

  static const columns = 'vehicle_id, due_date, amount_due, status, sent_in_period';

  factory ReportDue.fromRow(Map<String, dynamic> r) => ReportDue(
    vehicleId: r['vehicle_id'] as String,
    day: parseDate(r['due_date'] as String),
    amountDue: (r['amount_due'] as num).toInt(),
    status: dueStatusFromDb(r['status'] as String),
    sentInPeriod: (r['sent_in_period'] as num).toInt(),
  );

  bool get isRest => status == DueStatus.rest;

  /// The day is over, it wasn't covered in time, and the driver sent nothing
  /// during it. Days paid ahead by credit don't count.
  bool get missed =>
      !isRest &&
      sentInPeriod == 0 &&
      (status == DueStatus.late || status == DueStatus.partial || status == DueStatus.unpaid);

  bool get paidLate => status == DueStatus.late;
}

class ReportPayment {
  const ReportPayment({required this.vehicleId, required this.amount, required this.day});

  final String vehicleId;
  final int amount;

  /// The Kigali date it was paid.
  final DateTime day;

  static const columns = 'vehicle_id, amount, paid_at';

  factory ReportPayment.fromRow(Map<String, dynamic> r) => ReportPayment(
    vehicleId: r['vehicle_id'] as String,
    amount: (r['amount'] as num).toInt(),
    day: dateOnly(toKigali(DateTime.parse(r['paid_at'] as String))),
  );
}

/// Everything fetched for one period. Dues and payments of vehicles not in
/// [vehicles] (deleted ones) are dropped.
class ReportData {
  ReportData({
    required this.vehicles,
    required List<ReportDue> dues,
    required List<ReportPayment> payments,
    required this.deposits,
  }) : dues = dues.where((d) => _ids(vehicles).contains(d.vehicleId)).toList(),
       payments = payments.where((p) => _ids(vehicles).contains(p.vehicleId)).toList();

  final List<ReportVehicle> vehicles;
  final List<ReportDue> dues;
  final List<ReportPayment> payments;
  final List<Deposit> deposits;

  static Set<String> _ids(List<ReportVehicle> vehicles) => {for (final v in vehicles) v.id};
}

// ---------------------------------------------------------------------------
// Collections
// ---------------------------------------------------------------------------

class VehicleTotals {
  VehicleTotals(this.vehicle);

  final ReportVehicle vehicle;
  int collected = 0;
  int expected = 0;
  int missed = 0;
  int late = 0;
  int rest = 0;

  int? get rate => percent(collected, expected);
}

enum BucketSize { day, week, month }

/// One bar of the "Collected" chart.
class Bucket {
  Bucket(this.start, this.label);

  final DateTime start;

  /// Axis label, or '' when this bar has none.
  final String label;
  int collected = 0;
  int expected = 0;
}

class CollectionsReport {
  CollectionsReport._({
    required this.period,
    required this.vehicles,
    required this.rows,
    required this.owedNow,
    required this.bucketSize,
    required this.buckets,
    required this.calendar,
  });

  final ReportPeriod period;

  /// Every vehicle that had started by the end of the period, switched off
  /// or not (the filter chips).
  final List<ReportVehicle> vehicles;

  /// The chosen ones, with their totals.
  final List<VehicleTotals> rows;
  final int owedNow;
  final BucketSize bucketSize;
  final List<Bucket> buckets;

  /// Per vehicle id: one square per day of the period.
  final Map<String, List<DayCell>> calendar;

  int get collected => rows.fold(0, (t, r) => t + r.collected);
  int get expected => rows.fold(0, (t, r) => t + r.expected);
  int get missed => rows.fold(0, (t, r) => t + r.missed);
  int get late => rows.fold(0, (t, r) => t + r.late);
  int get rest => rows.fold(0, (t, r) => t + r.rest);
  int? get rate => percent(collected, expected);

  /// The calendar is only readable for up to about two months.
  bool get showCalendar => period.dayCount >= 2 && period.dayCount <= 62;

  /// One line under the numbers: who missed most, or that nobody did.
  String get insight {
    final worst = rows.where((r) => r.missed > 0).toList()..sort((a, b) => b.missed.compareTo(a.missed));
    if (worst.isNotEmpty) {
      final w = worst.first;
      final days = w.missed == 1 ? '1 day' : '${w.missed} days';
      return rows.length == 1
          ? '$days with nothing sent.'
          : 'Most missed days: ${w.vehicle.plate}, $days with nothing sent.';
    }
    if (late > 0) return 'No missed days. ${late == 1 ? '1 day was' : '$late days were'} paid late.';
    return 'No missed days in this period.';
  }

  /// [only] is the chosen vehicle ids (null = all). [owed] is what each
  /// vehicle owes right now, from Home.
  factory CollectionsReport.build(
    ReportData data,
    ReportPeriod period, {
    Set<String>? only,
    Map<String, int> owed = const {},
  }) {
    final dues = data.dues.where((d) => period.contains(d.day)).toList();
    final payments = data.payments.where((p) => period.contains(p.day)).toList();

    final present = {for (final d in dues) d.vehicleId, for (final p in payments) p.vehicleId};
    // Active ones first, then switched off; by plate.
    final vehicles = data.vehicles.where((v) => present.contains(v.id) || !v.startDate.isAfter(period.to)).toList()
      ..sort((a, b) => a.isActive != b.isActive ? (a.isActive ? -1 : 1) : a.plate.compareTo(b.plate));

    var chosen = only == null ? vehicles : vehicles.where((v) => only.contains(v.id)).toList();
    if (chosen.isEmpty) chosen = vehicles;
    final ids = {for (final v in chosen) v.id};

    final rows = {for (final v in chosen) v.id: VehicleTotals(v)};
    for (final p in payments) {
      rows[p.vehicleId]?.collected += p.amount;
    }
    for (final d in dues) {
      final r = rows[d.vehicleId];
      if (r == null) continue;
      if (d.isRest) {
        r.rest++;
      } else {
        r.expected += d.amountDue;
      }
      if (d.missed) r.missed++;
      if (d.paidLate) r.late++;
    }

    // Bars: days for up to ~6 weeks, then weeks for up to ~6 months, then months.
    final n = period.dayCount;
    final size = n <= 45
        ? BucketSize.day
        : n <= 183
        ? BucketSize.week
        : BucketSize.month;
    DateTime startOf(DateTime d) => switch (size) {
      BucketSize.day => d,
      BucketSize.week => DateTime(d.year, d.month, d.day - (d.weekday - 1)),
      BucketSize.month => DateTime(d.year, d.month),
    };
    // Each bar's start, and the first day of the period that falls in it.
    final starts = <DateTime, DateTime>{};
    for (final day in period.days) {
      starts.putIfAbsent(startOf(day), () => day);
    }
    // Label about every 4th to 7th bar, so labels never overlap.
    final every = switch (size) {
      BucketSize.day => 7,
      BucketSize.week => starts.length <= 13 ? 2 : 4,
      BucketSize.month => starts.length <= 7 ? 1 : 2,
    };
    final buckets = <DateTime, Bucket>{
      for (final (i, MapEntry(key: s, value: day)) in starts.entries.indexed)
        s: Bucket(
          s,
          i % every != 0
              ? ''
              : switch (size) {
                  BucketSize.day => '${day.day}',
                  BucketSize.week => '${day.day} ${_months[day.month - 1]}',
                  BucketSize.month => _months[s.month - 1],
                },
        ),
    };
    for (final p in payments) {
      if (ids.contains(p.vehicleId)) buckets[startOf(p.day)]?.collected += p.amount;
    }
    for (final d in dues) {
      if (ids.contains(d.vehicleId) && !d.isRest) buckets[startOf(d.day)]?.expected += d.amountDue;
    }

    final byDay = {for (final d in dues) (d.vehicleId, d.day): d};
    final calendar = {
      for (final v in chosen)
        v.id: [
          for (final day in period.days)
            if (byDay[(v.id, day)] case final d?) cellForStatus(d.status) else DayCell.none,
        ],
    };

    return CollectionsReport._(
      period: period,
      vehicles: vehicles,
      rows: rows.values.toList(),
      owedNow: chosen.fold(0, (t, v) => t + (owed[v.id] ?? 0)),
      bucketSize: size,
      buckets: buckets.values.toList(),
      calendar: calendar,
    );
  }
}

// ---------------------------------------------------------------------------
// Deposits
// ---------------------------------------------------------------------------

class DepositsReport {
  DepositsReport._({
    required this.period,
    required this.collected,
    required this.deposited,
    required this.fees,
    required this.history,
    required this.running,
  });

  final ReportPeriod period;

  /// Rent received in the period, all vehicles.
  final int collected;
  final int deposited;
  final int fees;

  /// Deposits made in the period, newest first.
  final List<Deposit> history;

  /// Per day: running totals of money collected, and of money deposited
  /// (with fees, so the gap between them is what isn't deposited yet).
  final List<(DateTime, int, int)> running;

  /// The period's money not deposited (negative when deposits also covered
  /// money collected earlier).
  int get notDeposited => collected - deposited - fees;

  factory DepositsReport.build(ReportData data, ReportPeriod period) {
    final payments = data.payments.where((p) => period.contains(p.day)).toList();
    final deposits = data.deposits.where((d) => period.contains(d.depositedOn)).toList()
      ..sort((a, b) => b.depositedOn.compareTo(a.depositedOn));

    final inByDay = <DateTime, int>{};
    for (final p in payments) {
      inByDay[p.day] = (inByDay[p.day] ?? 0) + p.amount;
    }
    final outByDay = <DateTime, int>{};
    for (final d in deposits) {
      outByDay[d.depositedOn] = (outByDay[d.depositedOn] ?? 0) + d.amount + d.fee;
    }
    var c = 0, o = 0;
    final running = [
      for (final day in period.days) (day, c += inByDay[day] ?? 0, o += outByDay[day] ?? 0),
    ];

    return DepositsReport._(
      period: period,
      collected: payments.fold(0, (t, p) => t + p.amount),
      deposited: deposits.fold(0, (t, d) => t + d.amount),
      fees: deposits.fold(0, (t, d) => t + d.fee),
      history: deposits,
      running: running,
    );
  }
}
