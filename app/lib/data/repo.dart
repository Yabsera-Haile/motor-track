import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../format.dart';
import 'history.dart';
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
      final results = await Future.wait([
        client.from('vehicles').select().isFilter('deleted_at', null),
        client.from('v_vehicle_today').select(),
        client
            .from('v_dues')
            .select('vehicle_id, due_date, status')
            .gte('due_date', isoDate(day.subtract(const Duration(days: 6))))
            .lte('due_date', isoDate(day)),
        client.from('members').select().order('name', ascending: true),
        client.from('devices').select('id, member_id, is_reader, last_checked_at'),
        client.from('settings').select().maybeSingle(),
        client
            .from('alerts')
            .select('id')
            .isFilter('resolved_at', null)
            .gte('created_at', DateTime.now().toUtc().subtract(const Duration(days: 2)).toIso8601String()),
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
      openAlerts = (results[6] as List).length;
      loadError = null;
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
    for (final table in ['vehicles', 'payments', 'dues', 'alerts', 'deposits', 'members', 'devices', 'settings']) {
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
