/// Reads payments out of M-Money SMS using a template such as
///
///   You have received {amount} RWF from {name} ({phone}) at {datetime} . Balance:{skip} RWF. FT Id: {txid}.
///
/// Literal text must match (spacing and case may vary); placeholders capture
/// the parts we need. {skip} matches anything and is thrown away (the balance
/// is never read or shared).
class SmsTemplate {
  SmsTemplate(this.pattern) : _regex = _compile(pattern) {
    for (final f in const ['amount', 'name', 'txid']) {
      if (!_order.contains(f)) throw ArgumentError('Template needs a {$f} placeholder: $pattern');
    }
  }

  /// MTN Rwanda's wording as of November 2026.
  static final mtnDefault = SmsTemplate(
    'You have received {amount} RWF from {name} ({phone}) at {datetime} . Balance:{skip} RWF. FT Id: {txid}.',
  );

  static const placeholders = ['amount', 'name', 'phone', 'datetime', 'txid', 'skip'];

  final String pattern;
  final RegExp _regex;

  /// The compiled pattern, handed to the Android background reader. It only
  /// uses syntax Java regex reads the same way (flags: case-insensitive, dot-all).
  String get regexSource => _regex.pattern;

  /// Which field each capture group of [regexSource] holds, in order.
  List<String> get groups => List.unmodifiable(_order);

  /// The exact text each field matched in [body], for highlighting; null if it doesn't fit.
  Map<String, String>? rawFields(String body) {
    final m = _regex.firstMatch(body);
    if (m == null) return null;
    return {for (var i = 0; i < _order.length; i++) _order[i]: m.group(i + 1)!};
  }

  late final List<String> _order = _placeholder
      .allMatches(pattern)
      .map((m) => m.group(1)!)
      .where((f) => f != 'skip')
      .toList();

  static final _placeholder = RegExp(r'\{(amount|name|phone|datetime|txid|skip)\}');

  static const _captures = {
    'amount': r'([0-9][0-9,]*(?:\.[0-9]+)?)',
    'name': r'(.+?)',
    'phone': r'([*0-9][*0-9 ]*?)',
    'datetime': r'(\d{4}-\d{2}-\d{2}\s+\d{1,2}:\d{2}(?::\d{2})?)',
    'txid': r'([A-Za-z0-9]+)',
    'skip': r'(?:.*?)',
  };

  static RegExp _compile(String pattern) {
    final out = StringBuffer(r'^\s*');
    var last = 0;
    for (final m in _placeholder.allMatches(pattern)) {
      out.write(_literal(pattern.substring(last, m.start)));
      out.write(_captures[m.group(1)!]);
      last = m.end;
    }
    out.write(_literal(pattern.substring(last)));
    return RegExp(out.toString(), caseSensitive: false, dotAll: true);
  }

  /// Escapes literal text; any run of spaces may be missing or repeated.
  static String _literal(String s) => s
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map(RegExp.escape)
      .join(r'\s*')
      .let((body) => body.isEmpty ? r'\s*' : '\\s*$body\\s*');

  /// Null when the message doesn't fit the template.
  ParsedPayment? parse(String body) {
    final m = _regex.firstMatch(body);
    if (m == null) return null;
    final values = <String, String>{};
    for (var i = 0; i < _order.length; i++) {
      values[_order[i]] = m.group(i + 1)!.trim();
    }
    final amount = num.tryParse(values['amount']!.replaceAll(',', ''));
    if (amount == null || amount <= 0) return null;
    final name = values['name']!.replaceAll(RegExp(r'\s+'), ' ');
    final txId = values['txid']!;
    if (name.isEmpty || txId.isEmpty) return null;
    return ParsedPayment(
      amount: amount.floor(),
      name: name,
      phone: values['phone']?.replaceAll(' ', ''),
      paidAt: values['datetime'] == null ? null : _kigaliToUtc(values['datetime']!),
      txId: txId,
    );
  }

  /// Builds a template from a sample message and the exact text the user
  /// confirmed for each field, e.g. {'amount': '6000', 'name': 'Xxx MUGABO', ...}.
  /// Anything between the fields that changes from message to message (like the
  /// balance) should be passed as 'skip'.
  factory SmsTemplate.fromSample(String sample, Map<String, String> fields) {
    final spans = <(int, int, String)>[];
    var searchFrom = 0;
    final ordered = fields.entries.toList()..sort((a, b) => sample.indexOf(a.value).compareTo(sample.indexOf(b.value)));
    for (final e in ordered) {
      final at = sample.indexOf(e.value, searchFrom);
      if (e.value.isEmpty || at < 0) throw ArgumentError('"${e.value}" is not in the sample');
      spans.add((at, at + e.value.length, e.key));
      searchFrom = at + e.value.length;
    }
    final out = StringBuffer();
    var last = 0;
    for (final (start, end, field) in spans) {
      out.write(sample.substring(last, start));
      out.write('{$field}');
      last = end;
    }
    out.write(sample.substring(last));
    return SmsTemplate(out.toString());
  }

  /// A message that looks like money received but doesn't fit the template:
  /// counted on the Reader phone so a wording change gets noticed.
  static bool looksLikeIncoming(String body) => RegExp(r'\breceived\b', caseSensitive: false).hasMatch(body);

  /// SMS times are Kigali wall-clock time (UTC+2).
  static DateTime _kigaliToUtc(String s) {
    final m = RegExp(r'(\d{4})-(\d{2})-(\d{2})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?').firstMatch(s)!;
    int g(int i) => int.parse(m.group(i) ?? '0');
    return DateTime.utc(g(1), g(2), g(3), g(4), g(5), g(6)).subtract(const Duration(hours: 2));
  }
}

class ParsedPayment {
  const ParsedPayment({required this.amount, required this.name, required this.txId, this.phone, this.paidAt});

  final int amount;
  final String name;
  final String txId;
  final String? phone;

  /// In UTC. Null if the template has no {datetime}; the phone's receive time is used then.
  final DateTime? paidAt;

  @override
  String toString() => 'ParsedPayment($amount, $name, $phone, $paidAt, $txId)';
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
