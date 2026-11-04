import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import 'sms_template.dart';

/// The Android side of the Reader (android/app/src/main/kotlin/.../reader).
/// Reading SMS is Android-only; on other platforms [supported] is false.
abstract final class ReaderService {
  static const _channel = MethodChannel('motor_track/reader');

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> hasNotificationPermission() async =>
      await _channel.invokeMethod<bool>('hasNotificationPermission') ?? false;

  /// Shows Android's notification prompt (Android 13+). True if notifications are allowed afterwards.
  static Future<bool> requestNotificationPermission() async =>
      await _channel.invokeMethod<bool>('requestNotificationPermission') ?? false;

  static Future<bool> hasSmsPermission() async => await _channel.invokeMethod<bool>('hasSmsPermission') ?? false;

  static Future<bool> requestSmsPermission() async =>
      await _channel.invokeMethod<bool>('requestSmsPermission') ?? false;

  static Future<bool> isIgnoringBatteryOptimizations() async =>
      await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ?? false;

  static Future<void> requestIgnoreBatteryOptimizations() =>
      _channel.invokeMethod<void>('requestIgnoreBatteryOptimizations');

  static Future<void> openAppSettings() => _channel.invokeMethod<void>('openAppSettings');

  static Future<List<SmsSender>> listSenders() async {
    final rows = await _channel.invokeListMethod<Map<Object?, Object?>>('listSenders') ?? const [];
    return rows.map(SmsSender.fromMap).toList();
  }

  /// Recent messages from [sender], newest first.
  static Future<List<InboxSms>> messages(String sender, {int limit = 60}) async {
    final rows =
        await _channel.invokeListMethod<Map<Object?, Object?>>('messages', {'sender': sender, 'limit': limit}) ??
        const [];
    return rows.map(InboxSms.fromMap).toList();
  }

  /// Turns on background reading on this phone.
  static Future<void> configure({
    required String url,
    required String publishableKey,
    required String readerKey,
    required String sender,
    required SmsTemplate template,
    required Iterable<String> usernames,
    required DateTime checkpoint,
  }) => _channel.invokeMethod<void>('configure', {
    'url': url,
    'publishableKey': publishableKey,
    'readerKey': readerKey,
    'sender': sender,
    'regex': template.regexSource,
    'groups': template.groups,
    'usernames': usernames.toList(),
    'checkpointMillis': checkpoint.millisecondsSinceEpoch,
  });

  static Future<void> updateUsernames(Iterable<String> usernames) =>
      _channel.invokeMethod<void>('updateUsernames', {'usernames': usernames.toList()});

  static Future<void> disable() => _channel.invokeMethod<void>('disable');

  /// Checks the inbox now (in the background). Returns false if the Reader is off.
  static Future<bool> runNow() async => await _channel.invokeMethod<bool>('runNow') ?? false;

  static Future<ReaderStatus> status() async =>
      ReaderStatus.fromMap(await _channel.invokeMapMethod<Object?, Object?>('status') ?? const {});
}

class SmsSender {
  const SmsSender({required this.address, required this.count, required this.latestBody, required this.latestDate});
  final String address;
  final int count;
  final String latestBody;
  final DateTime latestDate;

  factory SmsSender.fromMap(Map<Object?, Object?> m) => SmsSender(
    address: m['address'] as String,
    count: m['count'] as int,
    latestBody: m['latestBody'] as String? ?? '',
    latestDate: DateTime.fromMillisecondsSinceEpoch(m['latestDate'] as int, isUtc: true),
  );
}

class InboxSms {
  const InboxSms({required this.body, required this.date});
  final String body;

  /// When the phone received it (UTC).
  final DateTime date;

  factory InboxSms.fromMap(Map<Object?, Object?> m) => InboxSms(
    body: m['body'] as String? ?? '',
    date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int, isUtc: true),
  );
}

class ReaderStatus {
  const ReaderStatus({
    required this.enabled,
    required this.sender,
    required this.lastRun,
    required this.lastResult,
    required this.lastError,
    required this.unreadable,
    required this.queued,
    required this.uploadedTotal,
    required this.hasSmsPermission,
    required this.ignoringBatteryOptimizations,
  });

  final bool enabled;
  final String? sender;
  final DateTime? lastRun;
  final String? lastResult;
  final String? lastError;
  final int unreadable;
  final int queued;
  final int uploadedTotal;
  final bool hasSmsPermission;
  final bool ignoringBatteryOptimizations;

  factory ReaderStatus.fromMap(Map<Object?, Object?> m) {
    final last = (m['lastRunMillis'] as int?) ?? 0;
    return ReaderStatus(
      enabled: m['enabled'] as bool? ?? false,
      sender: m['sender'] as String?,
      lastRun: last == 0 ? null : DateTime.fromMillisecondsSinceEpoch(last, isUtc: true),
      lastResult: m['lastResult'] as String?,
      lastError: m['lastError'] as String?,
      unreadable: m['unreadable'] as int? ?? 0,
      queued: m['queued'] as int? ?? 0,
      uploadedTotal: m['uploadedTotal'] as int? ?? 0,
      hasSmsPermission: m['hasSmsPermission'] as bool? ?? false,
      ignoringBatteryOptimizations: m['ignoringBatteryOptimizations'] as bool? ?? false,
    );
  }
}

/// A payment found in the inbox during setup, for the catch-up import.
class CatchUpItem {
  const CatchUpItem({required this.payment, required this.vehicle, required this.receivedAt});
  final ParsedPayment payment;
  final Vehicle vehicle;
  final DateTime receivedAt;

  /// The SMS's own time when it has one, else when the phone got it.
  DateTime get paidAt => payment.paidAt ?? receivedAt;
}

/// Payments from registered drivers in [messages] since [since], oldest first.
/// Messages from anyone else are left out (and never uploaded).
List<CatchUpItem> findCatchUp(List<InboxSms> messages, SmsTemplate template, List<Vehicle> vehicles, DateTime since) {
  String norm(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
  final byName = <String, List<Vehicle>>{};
  for (final v in vehicles) {
    for (final u in v.momoUsernames) {
      (byName[norm(u)] ??= []).add(v);
    }
  }
  final seen = <String>{};
  final out = <CatchUpItem>[];
  for (final m in messages) {
    if (m.date.isBefore(since)) continue;
    final p = template.parse(m.body);
    if (p == null || !seen.add(p.txId)) continue;
    final matches = byName[norm(p.name)];
    if (matches == null) continue;
    var vehicle = matches.first;
    if (matches.length > 1) {
      // Two bikes share the username: the last 3 phone digits decide, as on the server.
      String last3(String s) {
        final d = s.replaceAll(RegExp(r'\D'), '');
        return d.length < 3 ? d : d.substring(d.length - 3);
      }

      final byPhone = matches.where((v) => last3(v.phone) == last3(p.phone ?? '')).toList();
      if (byPhone.length != 1) continue;
      vehicle = byPhone.single;
    }
    out.add(CatchUpItem(payment: p, vehicle: vehicle, receivedAt: m.date));
  }
  out.sort((a, b) => a.paidAt.compareTo(b.paidAt));
  return out;
}
