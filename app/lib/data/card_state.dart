import '../format.dart';
import 'models.dart';

enum Tone { ok, warn, bad, mute }

enum CardKind { paid, partial, unpaid, rest, nothingDue, inactive }

/// What a vehicle card says right now: the pill ("Partial · 3,000 of 6,000")
/// and the line under it ("3,000 left to pay today").
class CardState {
  const CardState(this.kind, this.label, this.detail, this.note, this.tone, this.noteTone);

  final CardKind kind;
  final String label;
  final String detail;
  final String note;
  final Tone tone;
  final Tone noteTone;
}

/// [now] is Kigali wall-clock time (as kigaliNow() gives it); only its
/// date and clock fields are used to decide whether the deadline has passed.
CardState describeCard(Vehicle v, VehicleToday? t, {required String deadline, DateTime? today, DateTime? now}) {
  today ??= kigaliToday();
  now ??= kigaliNow();
  if (!v.isActive) {
    return const CardState(
      CardKind.inactive,
      'Inactive',
      '',
      'Switched off · no dues, no alerts',
      Tone.mute,
      Tone.mute,
    );
  }
  if (t == null || t.currentKind == null) {
    if (t != null && t.overdue > 0) {
      return CardState(
        CardKind.unpaid,
        'Owes',
        rwf(t.overdue),
        'Unpaid since ${shortDate(t.oldestUnpaid!)}',
        Tone.bad,
        Tone.bad,
      );
    }
    final starts = v.startDate.isAfter(today) ? 'starts ${shortDate(v.startDate)}' : 'nothing due now';
    return CardState(CardKind.nothingDue, 'Nothing due', starts, 'Nothing owed', Tone.mute, Tone.mute);
  }

  final owes = t.overdue > 0 ? 'Also owes ${rwf(t.overdue)} from ${shortDate(t.oldestUnpaid!)}' : null;

  if (t.currentKind == 'rest') {
    if (owes != null) {
      return CardState(
        CardKind.unpaid,
        'Rest day',
        'owes ${rwf(t.overdue)}',
        'Unpaid since ${shortDate(t.oldestUnpaid!)}',
        Tone.bad,
        Tone.bad,
      );
    }
    return CardState(
      CardKind.rest,
      'Rest day',
      'no payment expected',
      t.credit > 0 ? '${rwf(t.credit)} credit' : 'Nothing owed',
      Tone.mute,
      Tone.mute,
    );
  }

  final leftNow = t.currentDue - t.currentPaid;
  if (t.overdue + leftNow == 0) {
    final detail = t.sentToday > 0 && t.lastPaidAt != null
        ? '${rwf(t.sentToday)} at ${kigaliTime(t.lastPaidAt!)}'
        : 'paid ahead';
    final note = t.credit > 0 ? '${rwf(t.credit)} credit for the next days' : 'Nothing owed';
    return CardState(CardKind.paid, 'Paid', detail, note, Tone.ok, Tone.mute);
  }

  final detail = '${rwf(t.currentPaid)} of ${rwf(t.currentDue)}';
  final wentToOlder = t.sentToday > t.currentPaid
      ? '${rwf(t.sentToday)} sent ${v.periodWord} paid older days first'
      : null;

  // "Partial" only when part of the current amount is paid. Money that all
  // went to older days leaves today "Not paid yet", with a note saying so.
  if (t.currentPaid > 0) {
    return CardState(
      CardKind.partial,
      'Partial',
      detail,
      owes ?? wentToOlder ?? '${rwf(leftNow)} left to pay ${v.periodWord}',
      Tone.warn,
      owes != null ? Tone.bad : Tone.warn,
    );
  }

  final [h, m] = deadline.split(':').map(int.parse).toList();
  final dueDay = t.currentDueDate!;
  // Compare clock readings, not moments: kigaliNow() is a UTC DateTime that
  // reads as Kigali time, while dueDay is a plain local date. Building both
  // the same way keeps the phone's own time zone out of it.
  final nowAt = DateTime.utc(now.year, now.month, now.day, now.hour, now.minute, now.second);
  final late = !nowAt.isBefore(DateTime.utc(dueDay.year, dueDay.month, dueDay.day, h, m));
  final dueLine = late
      ? 'Not paid by $deadline'
      : v.frequency == Frequency.daily
      ? 'Due by $deadline'
      : 'Due ${shortDate(dueDay)} by $deadline';
  // Grey until the deadline; red once it has passed or older days are unpaid.
  final tone = owes != null || late ? Tone.bad : Tone.mute;
  final note = wentToOlder == null
      ? owes ?? dueLine
      : owes == null
      ? wentToOlder
      : '$wentToOlder. $owes';
  return CardState(CardKind.unpaid, 'Not paid yet', detail, note, tone, tone);
}

/// One square in the "last 7 days" strip.
enum DayCell { ok, late, part, miss, rest, due, none, future }

List<DayCell> lastSevenDays(List<DueDay> dues, DateTime today) {
  final byDate = {for (final d in dues) d.dueDate: d.status};
  return List.generate(7, (i) {
    final day = today.subtract(Duration(days: 6 - i));
    return switch (byDate[day]) {
      DueStatus.onTime => DayCell.ok,
      DueStatus.late => DayCell.late,
      DueStatus.partial || DueStatus.partialOpen => DayCell.part,
      DueStatus.unpaid => DayCell.miss,
      DueStatus.open => DayCell.due,
      DueStatus.rest => DayCell.rest,
      null => DayCell.none,
    };
  });
}

/// The numbers at the top of Home.
class TodaySummary {
  const TodaySummary({
    required this.collected,
    required this.expected,
    required this.paidAmount,
    required this.partialAmount,
    required this.paidCount,
    required this.partialCount,
    required this.notYetCount,
  });

  final int collected;
  final int expected;
  final int paidAmount;
  final int partialAmount;
  final int paidCount;
  final int partialCount;
  final int notYetCount;

  static TodaySummary of(List<Vehicle> vehicles, Map<String, VehicleToday> today, String deadline, DateTime day) {
    var collected = 0, expected = 0, paidAmount = 0, partialAmount = 0, paid = 0, partial = 0, notYet = 0;
    for (final v in vehicles) {
      final t = today[v.id];
      if (t == null) continue;
      collected += t.sentToday;
      if (!v.isActive || t.currentKind != 'due' || t.currentDueDate != day) continue;
      expected += t.currentDue;
      switch (describeCard(v, t, deadline: deadline, today: day).kind) {
        case CardKind.paid:
          paid++;
          paidAmount += t.currentDue;
        case CardKind.partial:
          partial++;
          partialAmount += t.currentPaid;
        default:
          notYet++;
      }
    }
    return TodaySummary(
      collected: collected,
      expected: expected,
      paidAmount: paidAmount,
      partialAmount: partialAmount,
      paidCount: paid,
      partialCount: partial,
      notYetCount: notYet,
    );
  }
}
