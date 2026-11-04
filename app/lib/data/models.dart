import '../format.dart';

enum Frequency { daily, weekly, monthly }

class Vehicle {
  const Vehicle({
    required this.id,
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

  final String id;
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

  factory Vehicle.fromRow(Map<String, dynamic> r) => Vehicle(
    id: r['id'] as String,
    driverName: r['driver_name'] as String,
    plate: r['plate'] as String,
    phone: (r['phone'] as String?) ?? '',
    momoUsernames: ((r['momo_usernames'] as List?) ?? const []).cast<String>(),
    amount: r['amount'] as int,
    frequency: Frequency.values.byName(r['frequency'] as String),
    firstDueDate: r['first_due_date'] == null ? null : parseDate(r['first_due_date'] as String),
    restWeekdays: ((r['rest_weekdays'] as List?) ?? const []).cast<int>(),
    startDate: parseDate(r['start_date'] as String),
    isActive: r['is_active'] as bool,
  );

  /// "6,000 RWF / day · Rest day Sun"
  String get terms {
    final per = switch (frequency) {
      Frequency.daily => 'day',
      Frequency.weekly => 'week',
      Frequency.monthly => 'month',
    };
    final base = '${rwf(amount)} RWF / $per';
    if (frequency != Frequency.daily) {
      final d = firstDueDate;
      if (d == null) return base;
      return frequency == Frequency.weekly
          ? '$base · due ${weekdayShort[d.weekday - 1]}'
          : '$base · due on the ${d.day}${ordinal(d.day)}';
    }
    return '$base · ${restWeekdays.isEmpty ? 'No rest days' : restDaysLabel(restWeekdays)}';
  }

  String get periodWord => switch (frequency) {
    Frequency.daily => 'today',
    Frequency.weekly => 'this week',
    Frequency.monthly => 'this month',
  };
}

String ordinal(int n) {
  if (n % 100 >= 11 && n % 100 <= 13) return 'th';
  return switch (n % 10) {
    1 => 'st',
    2 => 'nd',
    3 => 'rd',
    _ => 'th',
  };
}

/// One row of v_vehicle_today: where a vehicle stands right now.
class VehicleToday {
  const VehicleToday({
    required this.vehicleId,
    required this.currentKind,
    required this.currentDueDate,
    required this.currentDue,
    required this.currentPaid,
    required this.sentToday,
    required this.overdue,
    required this.oldestUnpaid,
    required this.credit,
    required this.lastPaidAt,
  });

  final String vehicleId;
  final String? currentKind;
  final DateTime? currentDueDate;
  final int currentDue;
  final int currentPaid;
  final int sentToday;
  final int overdue;
  final DateTime? oldestUnpaid;
  final int credit;
  final DateTime? lastPaidAt;

  factory VehicleToday.fromRow(Map<String, dynamic> r) => VehicleToday(
    vehicleId: r['vehicle_id'] as String,
    currentKind: r['current_kind'] as String?,
    currentDueDate: r['current_due_date'] == null ? null : parseDate(r['current_due_date'] as String),
    currentDue: r['current_due'] as int,
    currentPaid: r['current_paid'] as int,
    sentToday: r['sent_today'] as int,
    overdue: r['overdue'] as int,
    oldestUnpaid: r['oldest_unpaid'] == null ? null : parseDate(r['oldest_unpaid'] as String),
    credit: r['credit'] as int,
    lastPaidAt: r['last_paid_at'] == null ? null : DateTime.parse(r['last_paid_at'] as String),
  );
}

/// Status of one due, as computed by v_dues.
enum DueStatus { onTime, late, partialOpen, open, partial, unpaid, rest }

DueStatus dueStatusFromDb(String s) => switch (s) {
  'on_time' => DueStatus.onTime,
  'late' => DueStatus.late,
  'partial_open' => DueStatus.partialOpen,
  'open' => DueStatus.open,
  'partial' => DueStatus.partial,
  'unpaid' => DueStatus.unpaid,
  _ => DueStatus.rest,
};

class DueDay {
  const DueDay({required this.vehicleId, required this.dueDate, required this.status});
  final String vehicleId;
  final DateTime dueDate;
  final DueStatus status;

  factory DueDay.fromRow(Map<String, dynamic> r) => DueDay(
    vehicleId: r['vehicle_id'] as String,
    dueDate: parseDate(r['due_date'] as String),
    status: dueStatusFromDb(r['status'] as String),
  );
}

class Member {
  const Member({required this.id, required this.name, this.momoNumber});
  final String id;
  final String name;
  final String? momoNumber;

  factory Member.fromRow(Map<String, dynamic> r) =>
      Member(id: r['id'] as String, name: r['name'] as String, momoNumber: r['momo_number'] as String?);
}

/// What one member has collected and deposited (view v_member_balances).
class MemberBalance {
  const MemberBalance({
    required this.memberId,
    required this.name,
    required this.received,
    required this.deposited,
    required this.fees,
    required this.held,
  });

  final String memberId;
  final String name;
  final int received;
  final int deposited;
  final int fees;

  /// Collected minus deposited minus fees: money still with this member.
  final int held;

  factory MemberBalance.fromRow(Map<String, dynamic> r) => MemberBalance(
    memberId: r['member_id'] as String,
    name: r['name'] as String,
    received: (r['received'] as num).toInt(),
    deposited: (r['deposited'] as num).toInt(),
    fees: (r['fees'] as num).toInt(),
    held: (r['held'] as num).toInt(),
  );
}

/// One bank deposit.
class Deposit {
  const Deposit({
    required this.id,
    required this.memberId,
    required this.amount,
    required this.fee,
    required this.depositedOn,
    this.reference,
    this.note,
    this.recordedById,
  });

  final String id;
  final String memberId;
  final int amount;
  final int fee;
  final DateTime depositedOn;
  final String? reference;
  final String? note;
  final String? recordedById;

  static const columns = 'id, member_id, amount, fee, deposited_on, reference, note, recorded_by_member_id';

  factory Deposit.fromRow(Map<String, dynamic> r) => Deposit(
    id: r['id'] as String,
    memberId: r['member_id'] as String,
    amount: (r['amount'] as num).toInt(),
    fee: (r['fee'] as num).toInt(),
    depositedOn: parseDate(r['deposited_on'] as String),
    reference: r['reference'] as String?,
    note: r['note'] as String?,
    recordedById: r['recorded_by_member_id'] as String?,
  );
}

class Device {
  const Device({
    required this.id,
    required this.memberId,
    required this.isReader,
    this.lastCheckedAt,
    this.readerSender,
    this.unreadableCount = 0,
  });
  final String id;
  final String memberId;
  final bool isReader;
  final DateTime? lastCheckedAt;
  final String? readerSender;

  /// M-Money messages this Reader couldn't read (a sign the wording changed).
  final int unreadableCount;

  factory Device.fromRow(Map<String, dynamic> r) => Device(
    id: r['id'] as String,
    memberId: r['member_id'] as String,
    isReader: r['is_reader'] as bool,
    lastCheckedAt: r['last_checked_at'] == null ? null : DateTime.parse(r['last_checked_at'] as String),
    readerSender: r['reader_sender'] as String?,
    unreadableCount: (r['unreadable_count'] as int?) ?? 0,
  );
}

class TeamSettings {
  const TeamSettings({
    required this.deadline,
    required this.missedAlertOffset,
    this.overpayAlerts = true,
    this.readerSilenceHours = 6,
    this.paymentPush = true,
  });
  final String deadline; // "20:00"
  final String missedAlertOffset; // Postgres interval text, e.g. "07:00:00"
  final bool overpayAlerts;
  final int readerSilenceHours;
  final bool paymentPush;

  static const fallback = TeamSettings(deadline: '20:00', missedAlertOffset: '07:00:00');

  /// The choices offered for the "Day missed" alert, as Postgres intervals.
  static const missedChoices = {
    '-01:00:00': '23:00 same day',
    '00:00:00': 'Midnight',
    '07:00:00': '07:00 next day',
    '08:00:00': '08:00 next day',
  };

  static const silenceChoices = [3, 6, 12, 24];

  String get missedLabel => missedChoices[missedAlertOffset] ?? missedAlertOffset;

  factory TeamSettings.fromRow(Map<String, dynamic> r) => TeamSettings(
    deadline: (r['deadline_time'] as String).substring(0, 5),
    missedAlertOffset: r['missed_alert_offset'] as String,
    overpayAlerts: r['overpay_alerts'] as bool? ?? true,
    readerSilenceHours: (r['reader_silence_hours'] as num?)?.toInt() ?? 6,
    paymentPush: r['payment_push'] as bool? ?? true,
  );
}

/// One row of the Alerts list.
class AlertItem {
  const AlertItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.resolvedAt,
    required this.vehicleId,
    required this.data,
  });

  final String id;
  final String type;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final String? vehicleId;
  final Map<String, dynamic> data;

  static const columns = 'id, type, title, body, created_at, resolved_at, vehicle_id, data';

  /// About one driver, so "Message driver" makes sense.
  bool get aboutDriver =>
      vehicleId != null && const {'unpaid_deadline', 'short_deadline', 'missed_day', 'overpayment'}.contains(type);

  factory AlertItem.fromRow(Map<String, dynamic> r) => AlertItem(
    id: r['id'] as String,
    type: r['type'] as String,
    title: r['title'] as String,
    body: r['body'] as String,
    createdAt: DateTime.parse(r['created_at'] as String),
    resolvedAt: r['resolved_at'] == null ? null : DateTime.parse(r['resolved_at'] as String),
    vehicleId: r['vehicle_id'] as String?,
    data: (r['data'] as Map?)?.cast<String, dynamic>() ?? const {},
  );
}
