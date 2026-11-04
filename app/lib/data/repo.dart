import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../format.dart';
import '../prefs.dart';
import '../push/push_service.dart';
import '../reader/reader_service.dart';
import 'history.dart';
import 'messages.dart';
import 'models.dart';

export 'history.dart' show DueRow, PaymentRow, PaymentSource;

class VehicleHistory {
  const VehicleHistory({required this.dues, required this.open, required this.payments});
  final Map<DateTime, DueRow> dues;
  final List<DueRow> open;
  final List<PaymentRow> payments;
}

/// Everything the screens read and write. Holds the team's data in memory and
/// reloads it whenever another phone changes something (Supabase Realtime).
class Repo extends ChangeNotifier {
  Repo(this.client);

  final SupabaseClient client;

  Member? me;
  List<Member> members = const [];
  List<Vehicle> vehicles = const [];
  Map<String, VehicleToday> today = const {};
  Map<String, List<DueDay>> recentDues = const {};
  List<Device> devices = const [];
  TeamSettings settings = TeamSettings.fallback;
  int openAlerts = 0;
  Map<MessageKind, MessageTemplate> messageTemplates = MessageTemplate.defaults;
  bool loaded = false;
  String? loadError;

  RealtimeChannel? _channel;
  Timer? _debounce;

  String? get deviceId => client.auth.currentUser?.id;

  /// Signs this phone in (invisibly) and finds out whether it joined the team.
  Future<Member?> start() async {
    if (client.auth.currentSession == null) {
      await client.auth.signInAnonymously();
    }
    final row = await client.from('devices').select('member_id, members(*)').eq('id', deviceId!).maybeSingle();
    me = row == null ? null : Member.fromRow(row['members'] as Map<String, dynamic>);
    return me;
  }

  /// Returns null on success, or an error code from join_team.
  Future<String?> join(String code, {String? name, String? memberId}) async {
    final res =
        await client.rpc('join_team', params: {'p_code': code, 'p_name': name, 'p_member_id': memberId})
            as Map<String, dynamic>;
    if (res['ok'] != true) return res['error'] as String? ?? 'unknown';
    me = Member.fromRow(res['member'] as Map<String, dynamic>);
    return null;
  }

  /// Names already on the team, for "I've joined before". Throws [JoinError].
  Future<List<Member>> teamMembers(String code) async {
    final res = await client.rpc('team_members', params: {'p_code': code}) as Map<String, dynamic>;
    if (res['ok'] != true) throw JoinError(res['error'] as String? ?? 'unknown');
    return (res['members'] as List).map((m) => Member.fromRow(m as Map<String, dynamic>)).toList();
  }

  Future<void> load() async {
    final day = kigaliToday();
    try {
      final results = await Future.wait<dynamic>([
        client.from('vehicles').select().isFilter('deleted_at', null),
        client.from('v_vehicle_today').select(),
        client
            .from('v_dues')
            .select('vehicle_id, due_date, status')
            .gte('due_date', isoDate(day.subtract(const Duration(days: 6))))
            .lte('due_date', isoDate(day)),
        client.from('members').select().order('name', ascending: true),
        client.from('devices').select('id, member_id, is_reader, last_checked_at, reader_sender, unreadable_count'),
        client.from('settings').select().maybeSingle(),
        client
            .from('alerts')
            .select('created_at')
            .isFilter('resolved_at', null)
            .gt('created_at', DateTime.now().toUtc().subtract(const Duration(days: 2)).toIso8601String()),
        // Before the alerts migration this table doesn't exist: use the built-in wording.
        client.from('message_templates').select().then<List<dynamic>>((r) => r, onError: (Object _) => const []),
      ]);
      // Active vehicles first, then by plate.
      vehicles = (results[0] as List).map((r) => Vehicle.fromRow(r)).toList()
        ..sort((a, b) => a.isActive != b.isActive ? (a.isActive ? -1 : 1) : a.plate.compareTo(b.plate));
      today = {for (final r in results[1] as List) r['vehicle_id'] as String: VehicleToday.fromRow(r)};
      final dues = (results[2] as List).map((r) => DueDay.fromRow(r));
      recentDues = {};
      for (final d in dues) {
        (recentDues[d.vehicleId] ??= []).add(d);
      }
      members = (results[3] as List).map((r) => Member.fromRow(r)).toList();
      devices = (results[4] as List).map((r) => Device.fromRow(r)).toList();
      final s = results[5] as Map<String, dynamic>?;
      settings = s == null ? TeamSettings.fallback : TeamSettings.fromRow(s);
      // Compared here, not in the query: the list may have been opened while this loaded.
      _recentOpenAlerts = [for (final r in results[6] as List) DateTime.parse(r['created_at'] as String)];
      openAlerts = _unseenCount;
      messageTemplates = {
        ...MessageTemplate.defaults,
        for (final r in results[7] as List)
          if (MessageTemplate.fromRow(r as Map<String, dynamic>) case final t?) t.kind: t,
      };
      loadError = null;
      // Keep this phone's Reader looking for the current usernames.
      if (ReaderService.supported && myDevice?.isReader == true) {
        unawaited(ReaderService.updateUsernames(allUsernames).catchError((Object _) {}));
      }
    } catch (e) {
      loadError = 'Couldn\'t load the latest data. Pull down to try again.';
      debugPrint('load failed: $e');
    }
    loaded = true;
    notifyListeners();
  }

  void subscribe() {
    if (_channel != null) return;
    var channel = client.channel('team-changes');
    for (final table in [
      'vehicles',
      'payments',
      'dues',
      'alerts',
      'deposits',
      'members',
      'devices',
      'settings',
      'message_templates',
    ]) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (_) => _scheduleReload(),
      );
    }
    _channel = channel..subscribe();
  }

  void _scheduleReload() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), load);
  }

  /// Minutes since the most recent Reader check, or null if there is no Reader.
  int? get readerMinutesAgo {
    final checks = devices.where((d) => d.isReader && d.lastCheckedAt != null).map((d) => d.lastCheckedAt!);
    if (checks.isEmpty) return null;
    final latest = checks.reduce((a, b) => a.isAfter(b) ? a : b);
    return DateTime.now().difference(latest).inMinutes;
  }

  Future<void> saveVehicle(VehicleDraft d, {String? id}) async {
    final row = d.toRow();
    try {
      if (id == null) {
        await client.from('vehicles').insert(row);
      } else {
        await client.from('vehicles').update(row).eq('id', id);
      }
    } on PostgrestException catch (e) {
      if (e.code == '23505') throw SaveError('Another vehicle already has the plate ${d.plate.toUpperCase()}.');
      rethrow;
    }
    await load();
  }

  Future<void> setActive(Vehicle v, bool active) async {
    // Show the change straight away; the reload confirms it.
    vehicles = [
      for (final x in vehicles) x.id == v.id ? Vehicle.fromRow({..._rowOf(x), 'is_active': active}) : x,
    ];
    notifyListeners();
    await client.from('vehicles').update({'is_active': active}).eq('id', v.id);
    await load();
  }

  /// Hides the vehicle. Its payments stay in reports.
  Future<void> deleteVehicle(Vehicle v) async {
    await client
        .from('vehicles')
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String(), 'is_active': false})
        .eq('id', v.id);
    await load();
  }

  /// Calendar dues between [from] and [to], unpaid dues, and recent payments.
  Future<VehicleHistory> history(String vehicleId, {required DateTime from, required DateTime to}) async {
    final results = await Future.wait([
      client
          .from('v_dues')
          .select()
          .eq('vehicle_id', vehicleId)
          .gte('due_date', isoDate(from))
          .lte('due_date', isoDate(to)),
      client
          .from('v_dues')
          .select()
          .eq('vehicle_id', vehicleId)
          .inFilter('status', ['open', 'partial_open', 'partial', 'unpaid'])
          .order('due_date', ascending: true),
      client
          .from('payments')
          .select(
            'id, amount, paid_at, source, tx_id, held_by_member_id, recorded_by_member_id, note, '
            'allocations(amount, dues(due_date))',
          )
          .eq('vehicle_id', vehicleId)
          .isFilter('deleted_at', null)
          .order('paid_at', ascending: false)
          .limit(60),
    ]);
    return VehicleHistory(
      dues: {for (final r in results[0] as List) parseDate(r['due_date'] as String): DueRow.fromRow(r)},
      open: (results[1] as List).map((r) => DueRow.fromRow(r)).toList(),
      payments: (results[2] as List).map((r) => PaymentRow.fromRow(r)).toList(),
    );
  }

  /// Unpaid dues for one vehicle, oldest first (for the payment preview).
  Future<List<DueRow>> openDues(String vehicleId) async {
    final rows = await client
        .from('v_dues')
        .select()
        .eq('vehicle_id', vehicleId)
        .inFilter('status', ['open', 'partial_open', 'partial', 'unpaid'])
        .order('due_date', ascending: true);
    return rows.map(DueRow.fromRow).toList();
  }

  /// A cash (or other non-MoMo) payment. MoMo payments only come from Readers.
  Future<void> recordPayment({
    required String vehicleId,
    required int amount,
    required DateTime paidAt,
    required PaymentSource source,
    String? heldById,
    String? note,
  }) async {
    assert(source != PaymentSource.momo);
    await client.from('payments').insert({
      'vehicle_id': vehicleId,
      'amount': amount,
      'paid_at': paidAt.toUtc().toIso8601String(),
      'source': source.name,
      'held_by_member_id': heldById,
      'note': (note ?? '').trim().isEmpty ? null : note!.trim(),
    });
    await load();
  }

  /// Removes a payment recorded by mistake. The days it paid become open again.
  Future<void> removePayment(String paymentId) async {
    await client.from('payments').update({'deleted_at': DateTime.now().toUtc().toIso8601String()}).eq('id', paymentId);
    await load();
  }

  String memberName(String? id) => members.where((m) => m.id == id).map((m) => m.name).firstOrNull ?? 'someone';

  // ---- Reader ----

  Device? get myDevice => devices.where((d) => d.id == deviceId).firstOrNull;

  /// Every MoMo username of the team's vehicles: the only senders a Reader uploads.
  List<String> get allUsernames => {for (final v in vehicles) ...v.momoUsernames}.toList();

  /// Saves the message format (reusing an identical one) and returns its id.
  Future<String> saveTemplate({required String sender, required String pattern, required String sample}) async {
    final existing = await client
        .from('sms_templates')
        .select('id')
        .eq('sender', sender)
        .eq('pattern', pattern)
        .limit(1);
    if (existing.isNotEmpty) return existing.first['id'] as String;
    final row = await client
        .from('sms_templates')
        .insert({'sender': sender, 'pattern': pattern, 'sample': sample, 'created_by_member_id': me?.id})
        .select('id')
        .single();
    return row['id'] as String;
  }

  /// Makes this phone a Reader and returns its key (shown only once).
  Future<String> enableReader({required String sender, required String templateId}) async =>
      await client.rpc('enable_reader', params: {'p_sender': sender, 'p_template_id': templateId}) as String;

  Future<void> disableReader() async {
    await client.rpc('disable_reader');
    await load();
  }

  Future<void> setMyMomoNumber(String number) async {
    final id = me?.id;
    if (id == null) return;
    await client.from('members').update({'momo_number': number.trim().isEmpty ? null : number.trim()}).eq('id', id);
    me = Member(id: id, name: me!.name, momoNumber: number.trim().isEmpty ? null : number.trim());
  }

  /// Uploads one payment found during setup. Returns the server's status (inserted, duplicate, ...).
  Future<String> importPayment(CatchUpItem item) async {
    final res =
        await client.rpc(
              'ingest_momo_payment',
              params: {
                'p_amount': item.payment.amount,
                'p_paid_at': item.paidAt.toUtc().toIso8601String(),
                'p_sender_name': item.payment.name,
                'p_sender_phone': item.payment.phone,
                'p_tx_id': item.payment.txId,
              },
            )
            as Map<String, dynamic>;
    return res['status'] as String? ?? 'unknown';
  }

  // ---- Alerts ----

  /// When the open alerts of the last two days were created.
  List<DateTime> _recentOpenAlerts = const [];

  /// The bell counts open alerts this phone hasn't seen in the list yet.
  int get _unseenCount {
    final seen = AppPrefs.alertsSeenAt;
    return seen == null ? _recentOpenAlerts.length : _recentOpenAlerts.where((t) => t.isAfter(seen)).length;
  }

  /// The Alerts list was opened and showed alerts up to [newest].
  void markAlertsSeen(DateTime newest) {
    final seen = AppPrefs.alertsSeenAt;
    if (seen != null && !newest.isAfter(seen)) return;
    AppPrefs.alertsSeenAt = newest;
    final unseen = _unseenCount;
    if (openAlerts != unseen) {
      openAlerts = unseen;
      notifyListeners();
    }
  }

  Vehicle? vehicleById(String? id) => vehicles.where((v) => v.id == id).firstOrNull;

  Future<List<AlertItem>> alerts({int limit = 100}) async {
    final rows = await client
        .from('alerts')
        .select(AlertItem.columns)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(AlertItem.fromRow).toList();
  }

  Future<AlertItem?> alert(String id) async {
    final row = await client.from('alerts').select(AlertItem.columns).eq('id', id).maybeSingle();
    return row == null ? null : AlertItem.fromRow(row);
  }

  /// Tells the database where to send this phone's notifications. Cheap to
  /// repeat: the server only writes when the token changed.
  Future<void> registerPush() async {
    if (me == null) return;
    final token = await PushService.token();
    if (token == null) return;
    try {
      await client.rpc('register_push', params: {'p_token': token, 'p_platform': 'android'});
    } catch (e) {
      debugPrint('register_push failed: $e');
    }
  }

  /// One notification to every phone. Returns (set up on the server, phones that can receive).
  Future<(bool, int)> sendTestPush() async {
    final res = await client.rpc('send_test_push') as Map<String, dynamic>;
    return (res['ready'] == true, (res['phones'] as num?)?.toInt() ?? 0);
  }

  Future<void> updateSettings(Map<String, dynamic> values) async {
    await client.from('settings').update(values).eq('id', true);
    await load();
  }

  Future<void> saveMessageTemplate(MessageTemplate t) async {
    await client
        .from('message_templates')
        .update({'english': t.english.trim(), 'kinyarwanda': t.kinyarwanda.trim()})
        .eq('kind', t.kind.name);
    await load();
  }

  Map<String, dynamic> _rowOf(Vehicle v) => {
    'id': v.id,
    'driver_name': v.driverName,
    'plate': v.plate,
    'phone': v.phone,
    'momo_usernames': v.momoUsernames,
    'amount': v.amount,
    'frequency': v.frequency.name,
    'first_due_date': v.firstDueDate == null ? null : isoDate(v.firstDueDate!),
    'rest_weekdays': v.restWeekdays,
    'start_date': isoDate(v.startDate),
    'is_active': v.isActive,
  };

  @override
  void dispose() {
    _debounce?.cancel();
    _channel?.unsubscribe();
    super.dispose();
  }
}

class VehicleDraft {
  VehicleDraft({
    required this.driverName,
    required this.plate,
    required this.phone,
    required this.momoUsernames,
    required this.amount,
    required this.frequency,
    required this.firstDueDate,
    required this.restWeekdays,
    required this.startDate,
    required this.isActive,
  });

  final String driverName;
  final String plate;
  final String phone;
  final List<String> momoUsernames;
  final int amount;
  final Frequency frequency;
  final DateTime? firstDueDate;
  final List<int> restWeekdays;
  final DateTime startDate;
  final bool isActive;

  Map<String, dynamic> toRow() => {
    'driver_name': driverName,
    'plate': plate,
    'phone': phone,
    'momo_usernames': momoUsernames,
    'amount': amount,
    'frequency': frequency.name,
    'first_due_date': frequency == Frequency.daily || firstDueDate == null ? null : isoDate(firstDueDate!),
    'rest_weekdays': frequency == Frequency.daily ? restWeekdays : <int>[],
    'start_date': isoDate(startDate),
    'is_active': isActive,
  };
}

class JoinError implements Exception {
  JoinError(this.code);
  final String code;
}

class SaveError implements Exception {
  SaveError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Plain-language messages for join_team / team_members error codes.
String joinErrorMessage(String code) => switch (code) {
  'wrong_team_code' => 'That team code isn\'t right. Check it with a team member.',
  'name_taken' => 'Someone on the team already uses that name. If it\'s you, choose "I\'ve joined before".',
  'name_required' => 'Enter your name.',
  'too_many_attempts' => 'Too many wrong codes. Wait an hour, then try again.',
  'team_code_not_set' => 'The team code hasn\'t been set up yet.',
  'member_not_found' => 'That name is no longer on the team.',
  _ => 'Something went wrong. Check your connection and try again.',
};
