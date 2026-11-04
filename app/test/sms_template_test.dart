import 'package:flutter_test/flutter_test.dart';
import 'package:motor_track/reader/sms_template.dart';

const sample =
    'You have received 6000 RWF from Xxx MUGABO (*********123) at 2026-11-02 19:57:24 . Balance:25000 RWF. FT Id: 30012345678.';

void main() {
  final mtn = SmsTemplate.mtnDefault;

  test('reads the real M-Money sample', () {
    final p = mtn.parse(sample)!;
    expect(p.amount, 6000);
    expect(p.name, 'Xxx MUGABO');
    expect(p.phone, '*********123');
    expect(p.txId, '30012345678');
    expect(p.paidAt, DateTime.utc(2026, 11, 2, 17, 57, 24), reason: '19:57 in Kigali is 17:57 UTC');
  });

  test('amounts with thousands separators and multi-word names', () {
    final p = mtn.parse(
      'You have received 12,000 RWF from Jean Claude NIYONSABA (*********021) at 2026-11-03 07:05:00 . Balance:28,917 RWF. FT Id: 31670000001.',
    )!;
    expect(p.amount, 12000);
    expect(p.name, 'Jean Claude NIYONSABA');
  });

  test('tolerates spacing and line-break differences', () {
    final p = mtn.parse(
      'You have received  6000 RWF from Eric  MUGISHA (*********118)\nat 2026-11-03 15:00:00. Balance:9000 RWF.FT Id:31670000002.',
    )!;
    expect(p.name, 'Eric MUGISHA');
    expect(p.txId, '31670000002');
  });

  test('ignores other M-Money messages', () {
    expect(
      mtn.parse('You have transferred 5000 RWF to Grace (*********777) at 2026-11-03 10:00:00. Fee: 100 RWF.'),
      isNull,
    );
    expect(mtn.parse('Your bundle balance is 1.2 GB'), isNull);
  });

  test('builds a template from a sample and the fields the user confirmed', () {
    final t = SmsTemplate.fromSample(sample, {
      'amount': '6000',
      'name': 'Xxx MUGABO',
      'phone': '*********123',
      'datetime': '2026-11-02 19:57:24',
      'skip': '25000',
      'txid': '30012345678',
    });
    expect(t.pattern, SmsTemplate.mtnDefault.pattern);
    final p = t.parse(
      'You have received 3000 RWF from Eric MUGISHA (*********118) at 2026-11-03 15:00:00 . Balance:19917 RWF. FT Id: 31670000003.',
    )!;
    expect([p.amount, p.name, p.txId], [3000, 'Eric MUGISHA', '31670000003']);
  });

  test('a template must capture amount, name and transaction id', () {
    expect(() => SmsTemplate('You have received {amount} RWF'), throwsArgumentError);
  });

  test('spots messages that look like money received', () {
    expect(SmsTemplate.looksLikeIncoming('Y\'ello! You have received 6000 RWF from ...'), isTrue);
    expect(SmsTemplate.looksLikeIncoming('Your bundle is active'), isFalse);
  });

  test('the pattern handed to Android stays the same (ReaderParserTest.kt pins it too)', () {
    expect(
      SmsTemplate.mtnDefault.regexSource,
      r'^\s*\s*You\s*have\s*received\s*([0-9][0-9,]*(?:\.[0-9]+)?)\s*RWF\s*from\s*(.+?)\s*\(\s*([*0-9][*0-9 ]*?)\s*\)'
      r'\s*at\s*(\d{4}-\d{2}-\d{2}\s+\d{1,2}:\d{2}(?::\d{2})?)\s*\.\s*Balance:\s*(?:.*?)\s*RWF\.\s*FT\s*Id:\s*([A-Za-z0-9]+)\s*\.\s*',
    );
    expect(SmsTemplate.mtnDefault.groups, ['amount', 'name', 'phone', 'datetime', 'txid']);
  });

  test('raw fields give the exact text to highlight', () {
    final f = mtn.rawFields(sample)!;
    expect(f['amount'], '6000');
    expect(f['name'], 'Xxx MUGABO');
    expect(f['datetime'], '2026-11-02 19:57:24');
  });
}
