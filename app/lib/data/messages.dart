import '../format.dart';
import 'models.dart';

/// The three suggested messages to a driver (Settings → Messages to drivers).
enum MessageKind {
  reminder('Reminder'),
  amount('Amount question'),
  missed('Missed day');

  const MessageKind(this.label);
  final String label;

  static MessageKind? byName(String name) => values.where((k) => k.name == name).firstOrNull;
}

enum MessageLanguage {
  both('Both'),
  kinyarwanda('Kinyarwanda'),
  english('English');

  const MessageLanguage(this.label);
  final String label;

  static MessageLanguage byName(String? name) => values.where((l) => l.name == name).firstOrNull ?? both;
}

class MessageTemplate {
  const MessageTemplate({required this.kind, required this.english, required this.kinyarwanda});

  final MessageKind kind;
  final String english;
  final String kinyarwanda;

  static MessageTemplate? fromRow(Map<String, dynamic> r) {
    final kind = MessageKind.byName(r['kind'] as String);
    if (kind == null) return null;
    return MessageTemplate(kind: kind, english: r['english'] as String, kinyarwanda: r['kinyarwanda'] as String);
  }

  /// The wording before anyone edits it. Same text as the alerts migration.
  static const defaults = {
    MessageKind.reminder: MessageTemplate(
      kind: MessageKind.reminder,
      english:
          "Hello {name}, a reminder that today's payment of {amount} RWF for motorcycle {plate} has not been "
          'received yet. Please send it today. Thank you.',
      kinyarwanda:
          "Muraho {name}, turabibutsa ko amafaranga y'uyu munsi angana na {amount} RWF ya moto {plate} "
          'ataratugeraho. Mwayohereza uyu munsi. Murakoze.',
    ),
    MessageKind.amount: MessageTemplate(
      kind: MessageKind.amount,
      english:
          'Hello {name}, today we received {received} RWF for motorcycle {plate}, but the agreed amount is '
          '{expected} RWF. Could you tell us why the amount is different? Thank you.',
      kinyarwanda:
          'Muraho {name}, uyu munsi twakiriye {received} RWF ya moto {plate}, ariko amafaranga twumvikanye ni '
          '{expected} RWF. Mwatubwira impamvu amafaranga atandukanye? Murakoze.',
    ),
    MessageKind.missed: MessageTemplate(
      kind: MessageKind.missed,
      english:
          'Hello {name}, we did not receive the payment of {amount} RWF for motorcycle {plate} for {date}. '
          'Please send it as soon as possible. Thank you.',
      kinyarwanda:
          'Muraho {name}, ntitwakiriye amafaranga {amount} RWF ya moto {plate} yo ku itariki {date}. '
          'Turabasaba kuyohereza vuba bishoboka. Murakoze.',
    ),
  };
}

/// The fill-in values for one message.
class MessageFacts {
  const MessageFacts({required this.name, required this.plate, required this.amount, this.received = 0, this.date});

  final String name;
  final String plate;

  /// What the driver should pay for the day (or week / month).
  final int amount;
  final int received;
  final DateTime? date;

  Map<String, String> get values => {
    'name': name,
    'plate': plate,
    'amount': rwf(amount),
    'expected': rwf(amount),
    'received': rwf(received),
    'date': smsDate(date ?? kigaliToday()),
  };
}

/// 2/11/2026: reads the same in Kinyarwanda and English.
String smsDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

/// Fills `{name}`-style fields. Unknown fields are left as they are.
String fillTemplate(String text, Map<String, String> values) =>
    text.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) => values[m[1]] ?? m[0]!);

/// The SMS text: Kinyarwanda first when both, then English.
String composeMessage(MessageTemplate t, MessageLanguage lang, MessageFacts facts) {
  final v = facts.values;
  final rw = fillTemplate(t.kinyarwanda.trim(), v);
  final en = fillTemplate(t.english.trim(), v);
  return switch (lang) {
    MessageLanguage.kinyarwanda => rw,
    MessageLanguage.english => en,
    MessageLanguage.both => '$rw\n\n$en',
  };
}

/// Which message fits a vehicle right now, and its facts.
(MessageKind, MessageFacts) suggestFor(Vehicle v, VehicleToday? t) {
  final facts = MessageFacts(
    name: v.driverName,
    plate: v.plate,
    amount: t != null && t.currentKind == 'due' && t.currentDue > 0 ? t.currentDue : v.amount,
    received: t?.sentToday ?? 0,
    date: t?.oldestUnpaid,
  );
  if (t == null) return (MessageKind.reminder, facts);
  final dueNow = t.currentKind == 'due' && t.currentPaid < t.currentDue;
  if (dueNow && t.sentToday > 0) return (MessageKind.amount, facts);
  if (!dueNow && t.overdue > 0 && t.oldestUnpaid != null) return (MessageKind.missed, facts);
  return (MessageKind.reminder, facts);
}

/// Roughly how many SMS the text takes (160 characters, or 153 each when split).
int smsParts(String text) => text.length <= 160 ? 1 : (text.length / 153).ceil();

/// Which message fits an alert, and its facts (from the alert's saved data).
(MessageKind, MessageFacts) suggestForAlert(String type, Map<String, dynamic> data, Vehicle v) {
  int n(String k) => (data[k] as num?)?.toInt() ?? 0;
  final expected = n('expected') > 0 ? n('expected') : v.amount;
  final date = data['due_date'] is String ? parseDate(data['due_date'] as String) : null;
  final facts = MessageFacts(name: v.driverName, plate: v.plate, amount: expected, received: n('received'), date: date);
  return switch (type) {
    'short_deadline' => (MessageKind.amount, facts),
    'overpayment' => (
      MessageKind.amount,
      MessageFacts(name: v.driverName, plate: v.plate, amount: expected, received: n('sent')),
    ),
    'missed_day' => (MessageKind.missed, facts),
    _ => (MessageKind.reminder, facts),
  };
}

/// An `sms:` link that opens the phone's SMS app with the text filled in.
Uri smsUri(String phone, String text) {
  final to = phone.replaceAll(RegExp(r'[^\d+]'), '');
  // Uri(queryParameters:) would encode spaces as "+", which some SMS apps show as-is.
  return Uri.parse('sms:$to?body=${Uri.encodeComponent(text)}');
}
