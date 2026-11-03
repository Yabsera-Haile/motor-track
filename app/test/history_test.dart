import 'package:flutter_test/flutter_test.dart';
import 'package:motor_track/data/card_state.dart';
import 'package:motor_track/data/history.dart';
import 'package:motor_track/data/models.dart';

final today = DateTime(2026, 11, 3);

final patrick = Vehicle(
  id: 'v',
  driverName: 'Patrick Uwimana',
  plate: 'RD 907 F',
  phone: '0782412390',
  momoUsernames: const ['Patrick UWIMANA'],
  amount: 6000,
  frequency: Frequency.daily,
  firstDueDate: null,
  restWeekdays: const [7],
  startDate: DateTime(2026, 10, 1),
  isActive: true,
);

DueRow due(DateTime d, DueStatus s, {int paid = 0, int sent = 0, int amount = 6000, String kind = 'due'}) =>
    DueRow(id: 'd${d.day}', dueDate: d, kind: kind, amountDue: amount, amountPaid: paid, status: s, sentInPeriod: sent);

PaymentRow payment(int amount, DateTime paidAtUtc, List<(DateTime, int)> covers) =>
    PaymentRow(id: 'p$amount', amount: amount, paidAt: paidAtUtc, source: PaymentSource.momo, covers: covers);

void main() {
  test('calendar shows five Monday-first weeks ending this week', () {
    final days = calendarDays(today);
    expect(days.length, 35);
    expect(days.first, DateTime(2026, 10, 5));
    expect(days.last, DateTime(2026, 11, 8));
    expect(days.first.weekday, DateTime.monday);
  });

  test('a payment fills the oldest open day first', () {
    final open = [due(DateTime(2026, 11, 3), DueStatus.open), due(DateTime(2026, 11, 2), DueStatus.unpaid)];
    final p = previewPayment(open, 9000);
    expect(p.lines.map((l) => (l.$1.dueDate.day, l.$2)), [(2, 6000), (3, 3000)]);
    expect(p.credit, 0);

    final more = previewPayment(open, 15000);
    expect(more.credit, 3000, reason: 'left over after both days is credit');
  });

  test('cover text names the days a payment paid', () {
    final p = payment(12000, DateTime.utc(2026, 11, 2, 16, 44), [
      (DateTime(2026, 10, 30), 6000),
      (DateTime(2026, 10, 31), 6000),
    ]);
    expect(p.coverText, 'Paid Fri 30 Oct + Sat 31 Oct');
    final ahead = payment(12000, DateTime.utc(2026, 11, 1, 16, 20), [(DateTime(2026, 11, 1), 6000)]);
    expect(ahead.coverText, 'Paid Sun 1 Nov · 6,000 credit');
  });

  test('explains a late day and which payment covered it', () {
    final day = DateTime(2026, 10, 30);
    final p = payment(12000, DateTime.utc(2026, 11, 2, 16, 44), [(day, 6000), (DateTime(2026, 10, 31), 6000)]);
    final (title, text) = describeDay(
      day,
      due(day, DueStatus.late, paid: 6000),
      [p],
      patrick,
      today: today,
      deadline: '20:00',
    );
    expect(title, 'Fri 30 Oct · Paid late');
    expect(text, 'Nothing was sent that day. Covered by the 12,000 sent Mon 2 Nov at 18:44.');
  });

  test('explains an unpaid day whose money went to older days', () {
    final day = DateTime(2026, 11, 2);
    final (title, text) = describeDay(
      day,
      due(day, DueStatus.unpaid, sent: 12000),
      const [],
      patrick,
      today: today,
      deadline: '20:00',
    );
    expect(title, 'Mon 2 Nov · Unpaid');
    expect(text, 'The 12,000 sent that day paid older days first, so this day is still open.');
  });

  test('future days and rest days', () {
    expect(
      describeDay(DateTime(2026, 11, 5), null, const [], patrick, today: today, deadline: '20:00').$2,
      '6,000 RWF due by 20:00.',
    );
    expect(calendarCell(DateTime(2026, 11, 8), null, patrick, today), DayCell.rest, reason: 'Sundays are rest days');
    expect(calendarCell(DateTime(2026, 11, 5), null, patrick, today), DayCell.future);
    expect(calendarCell(DateTime(2026, 9, 30), null, patrick, today), DayCell.none, reason: 'before the start date');
  });
}
