import 'package:flutter_test/flutter_test.dart';
import 'package:motor_track/data/messages.dart';
import 'package:motor_track/data/models.dart';

void main() {
  const facts = MessageFacts(name: 'Jean', plate: 'RAD 123 A', amount: 6000, received: 3000);

  test('fills every field and leaves unknown ones alone', () {
    expect(
      fillTemplate('{name} {plate} {amount} {received} {expected} {other}', facts.values),
      'Jean RAD 123 A 6,000 3,000 6,000 {other}',
    );
  });

  test('dates read the same in both languages', () {
    expect(smsDate(DateTime(2026, 11, 2)), '2/11/2026');
    final t = MessageTemplate.defaults[MessageKind.missed]!;
    final text = composeMessage(
      t,
      MessageLanguage.kinyarwanda,
      MessageFacts(name: 'Jean', plate: 'RAD 123 A', amount: 6000, date: DateTime(2026, 11, 2)),
    );
    expect(text, contains('yo ku itariki 2/11/2026'));
  });

  test('both languages: Kinyarwanda first, then English', () {
    final text = composeMessage(MessageTemplate.defaults[MessageKind.reminder]!, MessageLanguage.both, facts);
    final rw = text.indexOf('Muraho Jean');
    final en = text.indexOf('Hello Jean');
    expect(rw, 0);
    expect(en, greaterThan(rw));
    expect(text, contains('6,000 RWF ya moto RAD 123 A'));
    expect(text, isNot(contains('{')));
  });

  test('the amount question says what came in and what was agreed', () {
    final text = composeMessage(MessageTemplate.defaults[MessageKind.amount]!, MessageLanguage.english, facts);
    expect(text, contains('we received 3,000 RWF'));
    expect(text, contains('agreed amount is 6,000 RWF'));
  });

  test('the SMS link keeps spaces and accents intact', () {
    final uri = smsUri('+250 788 123 456', "Muraho Jean, y'uyu munsi?");
    expect(uri.toString(), "sms:+250788123456?body=Muraho%20Jean%2C%20y'uyu%20munsi%3F");
  });

  test('counts SMS parts', () {
    expect(smsParts('a' * 160), 1);
    expect(smsParts('a' * 161), 2);
    expect(smsParts('a' * 306), 2);
    expect(smsParts('a' * 307), 3);
  });

  group('suggested message for an alert', () {
    final v = Vehicle.fromRow({
      'id': 'v1',
      'driver_name': 'Jean',
      'plate': 'RAD 123 A',
      'phone': '0788123456',
      'momo_usernames': <String>[],
      'amount': 6000,
      'frequency': 'daily',
      'first_due_date': null,
      'rest_weekdays': <int>[],
      'start_date': '2026-10-01',
      'is_active': true,
    });

    test('not paid: reminder', () {
      final (kind, f) = suggestForAlert('unpaid_deadline', {'expected': 6000, 'received': 0}, v);
      expect(kind, MessageKind.reminder);
      expect(f.amount, 6000);
    });

    test('short: amount question with what came in', () {
      final (kind, f) = suggestForAlert('short_deadline', {'expected': 6000, 'received': 2000}, v);
      expect(kind, MessageKind.amount);
      expect(f.received, 2000);
    });

    test('missed day: carries the date', () {
      final (kind, f) = suggestForAlert('missed_day', {'expected': 6000, 'received': 0, 'due_date': '2026-11-02'}, v);
      expect(kind, MessageKind.missed);
      expect(f.date, DateTime(2026, 11, 2));
    });

    test('overpayment: amount question with what was sent', () {
      final (kind, f) = suggestForAlert('overpayment', {'expected': 6000, 'sent': 12000, 'credit': 6000}, v);
      expect(kind, MessageKind.amount);
      expect(f.received, 12000);
    });
  });
}
