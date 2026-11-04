import 'package:flutter_test/flutter_test.dart';
import 'package:motor_track/data/models.dart';
import 'package:motor_track/reader/reader_service.dart';
import 'package:motor_track/reader/sms_template.dart';

Vehicle bike(String id, String plate, String phone, List<String> names) => Vehicle(
  id: id,
  driverName: 'Driver $id',
  plate: plate,
  phone: phone,
  momoUsernames: names,
  amount: 6000,
  frequency: Frequency.daily,
  firstDueDate: null,
  restWeekdays: const [],
  startDate: DateTime(2026, 10, 1),
  isActive: true,
);

InboxSms sms(String name, String phone, String tx, {String at = '2026-11-02 19:57:24', int amount = 6000}) => InboxSms(
  body: 'You have received $amount RWF from $name ($phone) at $at . Balance:25000 RWF. FT Id: $tx.',
  date: DateTime.utc(2026, 11, 2, 18),
);

void main() {
  final since = DateTime.utc(2026, 10, 4);
  final vehicles = [
    bike('a', 'RD 482 K', '0788100123', ['Xxx MUGABO']),
    bike('b', 'RD 907 F', '0782412390', ['Patrick UWIMANA', 'Xxx UWIMANA']),
    bike('c', 'RE 115 C', '0789640999', ['Xxx UWIMANA']),
  ];

  test('keeps only payments from registered drivers, once each, oldest first', () {
    final found = findCatchUp(
      [
        sms('Patrick UWIMANA', '*********390', '2', at: '2026-11-03 08:00:00'),
        sms('xxx  mugabo', '*********123', '1'),
        sms('Somebody ELSE', '*********111', '3'),
        sms('Xxx MUGABO', '*********123', '1'),
      ],
      SmsTemplate.mtnDefault,
      vehicles,
      since,
    );
    expect(found.map((f) => (f.vehicle.plate, f.payment.txId)), [('RD 482 K', '1'), ('RD 907 F', '2')]);
  });

  test('a shared username is settled by the last 3 phone digits', () {
    final found = findCatchUp(
      [sms('Xxx UWIMANA', '*********999', '4'), sms('Xxx UWIMANA', '*********123', '5')],
      SmsTemplate.mtnDefault,
      vehicles,
      since,
    );
    expect(found.single.vehicle.plate, 'RE 115 C');
  });

  test('ignores messages older than the catch-up window', () {
    final old = InboxSms(body: sms('Xxx MUGABO', '*********123', '6').body, date: DateTime.utc(2026, 9, 1));
    expect(findCatchUp([old], SmsTemplate.mtnDefault, vehicles, since), isEmpty);
  });
}
