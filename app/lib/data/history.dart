import '../format.dart';
import 'card_state.dart';
import 'models.dart';

/// A due as shown on the vehicle calendar (a row of v_dues).
class DueRow {
  const DueRow({
    required this.id,
    required this.dueDate,
    required this.kind,
    required this.amountDue,
    required this.amountPaid,
    required this.status,
    required this.sentInPeriod,
  });

  final String id;
  final DateTime dueDate;
  final String kind;
  final int amountDue;
  final int amountPaid;
  final DueStatus status;
  final int sentInPeriod;

  int get remaining => amountDue - amountPaid;

  factory DueRow.fromRow(Map<String, dynamic> r) => DueRow(
    id: r['id'] as String,
    dueDate: parseDate(r['due_date'] as String),
    kind: r['kind'] as String,
    amountDue: r['amount_due'] as int,
    amountPaid: r['amount_paid'] as int,
    status: dueStatusFromDb(r['status'] as String),
    sentInPeriod: r['sent_in_period'] as int,
  );
}

enum PaymentSource { momo, cash, other }

/// A payment with the days it paid (oldest first).
class PaymentRow {
  const PaymentRow({
    required this.id,
    required this.amount,
    required this.paidAt,
    required this.source,
    required this.covers,
    this.txId,
    this.heldById,
    this.recordedById,
    this.note,
  });

  final String id;
  final int amount;
  final DateTime paidAt;
  final PaymentSource source;
  final List<(DateTime, int)> covers;
  final String? txId;
  final String? heldById;
  final String? recordedById;
  final String? note;

  int get credit => amount - covers.fold(0, (t, c) => t + c.$2);

  factory PaymentRow.fromRow(Map<String, dynamic> r) {
    final allocations =
        ((r['allocations'] as List?) ?? const [])
            .map((a) => (parseDate((a['dues'] as Map<String, dynamic>)['due_date'] as String), a['amount'] as int))
            .toList()
          ..sort((a, b) => a.$1.compareTo(b.$1));
    return PaymentRow(
      id: r['id'] as String,
      amount: r['amount'] as int,
      paidAt: DateTime.parse(r['paid_at'] as String),
      source: PaymentSource.values.byName(r['source'] as String),
      covers: allocations,
      txId: r['tx_id'] as String?,
      heldById: r['held_by_member_id'] as String?,
      recordedById: r['recorded_by_member_id'] as String?,
      note: r['note'] as String?,
    );
  }

  /// "Paid Fri 30 Oct + Sat 31 Oct", "Paid Tue 3 Nov · 6,000 credit", "Kept as credit".
  String get coverText {
    if (covers.isEmpty) return credit > 0 ? 'Kept as credit for later days' : 'Not applied';
    final days = covers.length <= 3
        ? covers.map((c) => shortDate(c.$1)).join(' + ')
        : '${shortDate(covers.first.$1)} to ${shortDate(covers.last.$1)} (${covers.length} days)';
    return credit > 0 ? 'Paid $days · ${rwf(credit)} credit' : 'Paid $days';
  }
}

/// The 35 days on the vehicle calendar: five full weeks, Monday first, ending
/// with the current week.
List<DateTime> calendarDays(DateTime today) {
  final monday = today.subtract(Duration(days: today.weekday - 1));
  final start = monday.subtract(const Duration(days: 28));
  return List.generate(35, (i) => DateTime(start.year, start.month, start.day + i));
}

/// The square for one calendar day.
DayCell calendarCell(DateTime day, DueRow? due, Vehicle v, DateTime today) {
  if (due == null) {
    if (!day.isAfter(today) || day.isBefore(v.startDate) || !v.isActive) return DayCell.none;
    if (v.frequency == Frequency.daily && v.restWeekdays.contains(day.weekday)) return DayCell.rest;
    return DayCell.future;
  }
  return switch (due.status) {
    DueStatus.onTime => DayCell.ok,
    DueStatus.late => DayCell.late,
    DueStatus.partial || DueStatus.partialOpen => DayCell.part,
    DueStatus.unpaid => DayCell.miss,
    DueStatus.open => DayCell.due,
    DueStatus.rest => DayCell.rest,
  };
}

/// The explanation shown when a calendar day is tapped.
(String, String) describeDay(
  DateTime day,
  DueRow? due,
  List<PaymentRow> payments,
  Vehicle v, {
  required DateTime today,
  required String deadline,
}) {
  final title = '${weekdayShort[day.weekday - 1]} ${dateOnlyLabel(day)}';
  if (due == null) {
    if (day.isAfter(today) && v.isActive && !day.isBefore(v.startDate)) {
      final rest = v.frequency == Frequency.daily && v.restWeekdays.contains(day.weekday);
      return rest
          ? ('$title · Rest day', 'No payment expected.')
          : (
              '$title · Upcoming',
              v.frequency == Frequency.daily ? '${rwf(v.amount)} RWF due by $deadline.' : 'No payment due on this day.',
            );
    }
    return (
      '$title · No payment expected',
      day.isBefore(v.startDate) ? 'Before the start date.' : 'Nothing was due on this day.',
    );
  }

  String coveredBy() {
    final by = payments.where((p) => p.covers.any((c) => c.$1 == due.dueDate)).toList()
      ..sort((a, b) => a.paidAt.compareTo(b.paidAt));
    if (by.isEmpty) return 'Covered by credit from an earlier payment.';
    final p = by.last;
    final when = dateOnly(toKigali(p.paidAt)) == due.dueDate
        ? 'at ${kigaliTime(p.paidAt)}'
        : '${shortDate(toKigali(p.paidAt))} at ${kigaliTime(p.paidAt)}';
    return 'Covered by the ${rwf(p.amount)} sent $when.';
  }

  final nothingSent = due.sentInPeriod == 0 && due.kind == 'due' ? 'Nothing was sent that day. ' : '';
  return switch (due.status) {
    DueStatus.rest => ('$title · Rest day', 'No payment expected.'),
    DueStatus.onTime => ('$title · Paid on time', '${rwf(due.amountDue)} RWF. ${coveredBy()}'),
    DueStatus.late => ('$title · Paid late', '$nothingSent${coveredBy()}'),
    DueStatus.open => (
      '$title · Due ${due.dueDate == today ? 'today' : shortDate(due.dueDate)}',
      due.sentInPeriod > 0
          ? 'The ${rwf(due.sentInPeriod)} sent so far paid older days first. ${rwf(due.remaining)} RWF still due by $deadline.'
          : 'Nothing received yet. ${rwf(due.amountDue)} RWF due by $deadline.',
    ),
    DueStatus.partialOpen => (
      '$title · Partly paid',
      '${rwf(due.amountPaid)} of ${rwf(due.amountDue)} received. ${rwf(due.remaining)} RWF still due by $deadline.',
    ),
    DueStatus.partial => (
      '$title · Partly paid',
      '${rwf(due.amountPaid)} of ${rwf(due.amountDue)} paid. ${rwf(due.remaining)} RWF still owed.',
    ),
    DueStatus.unpaid => (
      '$title · Unpaid',
      due.sentInPeriod > 0
          ? 'The ${rwf(due.sentInPeriod)} sent that day paid older days first, so this day is still open.'
          : 'Nothing paid toward this day yet.',
    ),
  };
}

/// "30 Oct"
String dateOnlyLabel(DateTime d) =>
    '${d.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]}';

/// What a new payment would pay off, oldest unpaid day first.
class PaymentPreview {
  const PaymentPreview(this.lines, this.credit);
  final List<(DueRow, int)> lines;
  final int credit;
}

PaymentPreview previewPayment(List<DueRow> open, int amount) {
  final sorted = [...open]..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  var left = amount;
  final lines = <(DueRow, int)>[];
  for (final d in sorted) {
    if (d.remaining <= 0) continue;
    final pay = left < d.remaining ? left : d.remaining;
    lines.add((d, pay));
    left -= pay;
  }
  return PaymentPreview(lines, left);
}
