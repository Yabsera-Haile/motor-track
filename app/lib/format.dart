import 'package:intl/intl.dart';

final _rwf = NumberFormat('#,##0', 'en_US');
final _short = DateFormat('EEE d MMM', 'en_US');
final _long = DateFormat('EEE, d MMM yyyy', 'en_US');
final _weekdayLong = DateFormat('EEEE, d MMMM', 'en_US');
final _time = DateFormat('HH:mm', 'en_US');

/// 6000 -> "6,000"
String rwf(num n) => _rwf.format(n);

/// "Mon 2 Nov"
String shortDate(DateTime d) => _short.format(d);

/// "Tue, 3 Nov 2026"
String longDate(DateTime d) => _long.format(d);

/// "Tuesday, 3 November"
String headerDate(DateTime d) => _weekdayLong.format(d);

/// "07:42" in Kigali time.
String kigaliTime(DateTime t) => _time.format(toKigali(t));

/// Payments are tracked in Kigali time (UTC+2, no daylight saving), whatever
/// time zone the phone is set to.
DateTime toKigali(DateTime t) => t.toUtc().add(const Duration(hours: 2));

DateTime kigaliNow() => toKigali(DateTime.now());

/// Today's date in Kigali, at midnight (no time part).
DateTime kigaliToday() {
  final n = kigaliNow();
  return DateTime(n.year, n.month, n.day);
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// "2026-11-03" for the database.
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseDate(String s) {
  final p = s.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

const weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const weekdayLong = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// "1 rest day a week: Sunday" style list, from ISO weekdays (1 = Monday).
String restDaysLabel(List<int> days) {
  if (days.isEmpty) return 'No rest days';
  final names = (days.toList()..sort()).map((d) => weekdayShort[d - 1]).join(', ');
  return 'Rest day${days.length == 1 ? '' : 's'} $names';
}

/// Digits only, for phone search.
String digits(String s) => s.replaceAll(RegExp(r'\D'), '');
