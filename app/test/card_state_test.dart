import 'package:flutter_test/flutter_test.dart';
import 'package:motor_track/data/card_state.dart';
import 'package:motor_track/data/models.dart';
import 'package:motor_track/format.dart';

Vehicle vehicle({bool active = true, Frequency frequency = Frequency.daily}) => Vehicle(
  id: 'v',
  driverName: 'Patrick Uwimana',
  plate: 'RD 907 F',
  phone: '0782412390',
  momoUsernames: const ['Patrick UWIMANA'],
  amount: 6000,
  frequency: frequency,
  firstDueDate: frequency == Frequency.daily ? null : DateTime(2026, 11, 7),
  restWeekdays: const [7],
  startDate: DateTime(2026, 10, 1),
  isActive: active,
);

VehicleToday today({
  String? kind = 'due',
  int due = 6000,
  int paid = 0,
  int sent = 0,
  int overdue = 0,
  DateTime? oldest,
  int credit = 0,
  DateTime? lastPaidAt,
}) => VehicleToday(
  vehicleId: 'v',
  currentKind: kind,
  currentDueDate: DateTime(2026, 11, 3),
  currentDue: due,
  currentPaid: paid,
  sentToday: sent,
  overdue: overdue,
  oldestUnpaid: oldest,
  credit: credit,
  lastPaidAt: lastPaidAt,
);

final day = DateTime(2026, 11, 3);

CardState describe(Vehicle v, VehicleToday t, {int hour = 16}) =>
    describeCard(v, t, deadline: '20:00', today: day, now: DateTime(2026, 11, 3, hour, 40));

void main() {
  test('paid today', () {
    final s = describe(vehicle(), today(paid: 6000, sent: 6000, lastPaidAt: DateTime.utc(2026, 11, 3, 5, 42)));
    expect(s.kind, CardKind.paid);
    expect('${s.label} · ${s.detail}', 'Paid · 6,000 at 07:42');
    expect(s.note, 'Nothing owed');
  });

  test('partial today', () {
    final s = describe(vehicle(), today(paid: 3000, sent: 3000));
    expect(s.kind, CardKind.partial);
    expect('${s.label} · ${s.detail}', 'Partial · 3,000 of 6,000');
    expect(s.note, '3,000 left to pay today');
  });

  test('not paid, with an older unpaid day', () {
    final s = describe(vehicle(), today(overdue: 6000, oldest: DateTime(2026, 11, 2)));
    expect(s.kind, CardKind.unpaid);
    expect(s.tone, Tone.bad);
    expect('${s.label} · ${s.detail}', 'Not paid yet · 0 of 6,000');
    expect(s.note, 'Also owes 6,000 from Mon 2 Nov');
  });

  test('not paid yet, nothing older: neutral until the deadline', () {
    final s = describe(vehicle(), today());
    expect(s.tone, Tone.mute);
    expect(s.note, 'Due by 20:00');
  });

  test('after the deadline it turns red', () {
    final s = describe(vehicle(), today(), hour: 21);
    expect(s.tone, Tone.bad);
    expect(s.note, 'Not paid by 20:00');
  });

  test('the deadline is read in Kigali time, as kigaliNow() gives it', () {
    // kigaliNow() is a UTC DateTime that reads as Kigali time. 19:34 UTC is
    // 21:34 in Kigali: still before a 22:00 deadline, whatever the phone's zone.
    CardState at(int utcHour, int utcMinute) => describeCard(
      vehicle(),
      today(),
      deadline: '22:00',
      today: day,
      now: toKigali(DateTime.utc(2026, 11, 3, utcHour, utcMinute)),
    );
    expect(at(19, 34).note, 'Due by 22:00');
    expect(at(19, 34).tone, Tone.mute);
    expect(at(20, 0).note, 'Not paid by 22:00');
    expect(at(20, 0).tone, Tone.bad);
  });

  test('money sent today that went to an older day is explained', () {
    final s = describe(vehicle(), today(sent: 6000));
    expect(s.kind, CardKind.unpaid);
    expect('${s.label} · ${s.detail}', 'Not paid yet · 0 of 6,000');
    expect(s.note, '6,000 sent today paid older days first');
  });

  test('...and what is still owed from before', () {
    final s = describe(vehicle(), today(sent: 6000, overdue: 6000, oldest: DateTime(2026, 11, 2)));
    expect('${s.label} · ${s.detail}', 'Not paid yet · 0 of 6,000');
    expect(s.note, '6,000 sent today paid older days first. Also owes 6,000 from Mon 2 Nov');
    expect(s.tone, Tone.bad);
  });

  test('covered by credit', () {
    final s = describe(vehicle(), today(paid: 6000, credit: 6000));
    expect(s.kind, CardKind.paid);
    expect(s.detail, 'paid ahead');
    expect(s.note, '6,000 credit for the next days');
  });

  test('rest day', () {
    expect(describe(vehicle(), today(kind: 'rest', due: 0)).kind, CardKind.rest);
  });

  test('switched off', () {
    final s = describe(vehicle(active: false), today());
    expect(s.kind, CardKind.inactive);
    expect(s.label, 'Inactive');
  });

  test('weekly vehicle says when it is due', () {
    final s = describe(vehicle(frequency: Frequency.weekly), today(due: 42000));
    expect(s.note, 'Due Tue 3 Nov by 20:00');
    expect(vehicle(frequency: Frequency.weekly).terms, '6,000 RWF / week · due Sat');
  });

  test('last 7 days strip', () {
    final cells = lastSevenDays([
      DueDay(vehicleId: 'v', dueDate: DateTime(2026, 10, 28), status: DueStatus.onTime),
      DueDay(vehicleId: 'v', dueDate: DateTime(2026, 10, 30), status: DueStatus.late),
      DueDay(vehicleId: 'v', dueDate: DateTime(2026, 11, 1), status: DueStatus.rest),
      DueDay(vehicleId: 'v', dueDate: DateTime(2026, 11, 2), status: DueStatus.unpaid),
      DueDay(vehicleId: 'v', dueDate: DateTime(2026, 11, 3), status: DueStatus.open),
    ], day);
    expect(cells, [DayCell.ok, DayCell.none, DayCell.late, DayCell.none, DayCell.rest, DayCell.miss, DayCell.due]);
  });

  test('today summary counts only what is due today', () {
    final vs = [
      vehicle(),
      Vehicle.fromRow({
        'id': 'w',
        'driver_name': 'Eric',
        'plate': 'RE 115 C',
        'phone': '',
        'momo_usernames': ['Eric MUGISHA'],
        'amount': 6000,
        'frequency': 'daily',
        'first_due_date': null,
        'rest_weekdays': [7],
        'start_date': '2026-10-01',
        'is_active': true,
      }),
    ];
    final s = TodaySummary.of(
      vs,
      {
        'v': today(paid: 6000, sent: 6000),
        'w': VehicleToday(
          vehicleId: 'w',
          currentKind: 'due',
          currentDueDate: day,
          currentDue: 6000,
          currentPaid: 3000,
          sentToday: 3000,
          overdue: 0,
          oldestUnpaid: null,
          credit: 0,
          lastPaidAt: null,
        ),
      },
      '20:00',
      day,
    );
    expect([s.collected, s.expected, s.paidCount, s.partialCount, s.notYetCount], [9000, 12000, 1, 1, 0]);
  });
}
