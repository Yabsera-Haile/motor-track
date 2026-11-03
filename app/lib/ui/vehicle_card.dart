import 'package:flutter/material.dart';

import '../data/card_state.dart';
import '../data/models.dart';
import '../theme.dart';

class VehicleCard extends StatelessWidget {
  const VehicleCard({
    super.key,
    required this.vehicle,
    required this.state,
    required this.days,
    required this.today,
    required this.onOpen,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final Vehicle vehicle;
  final CardState state;
  final List<DayCell> days;
  final DateTime today;
  final VoidCallback onOpen;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final v = vehicle;
    return Card(
      color: v.isActive ? Palette.surface : const Color(0xFFFAFBFC),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: InkWell(
                    onTap: onOpen,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              PlateChip(v.plate),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  v.driverName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(v.terms, style: const TextStyle(fontSize: 13, color: Palette.ink2)),
                        ],
                      ),
                    ),
                  ),
                ),
                Semantics(
                  label: 'Active',
                  child: Switch(value: v.isActive, onChanged: onToggle),
                ),
                PopupMenuButton<String>(
                  tooltip: 'More actions',
                  icon: const Icon(Icons.more_vert, color: Palette.ink),
                  onSelected: (a) => a == 'edit' ? onEdit() : onDelete(),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete', style: TextStyle(color: Palette.bad)),
                    ),
                  ],
                ),
              ],
            ),
            const Padding(padding: EdgeInsets.only(top: 10, right: 10), child: Divider()),
            Padding(
              padding: const EdgeInsets.only(top: 10, right: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        StatusPill(state: state),
                        const SizedBox(height: 6),
                        Text(
                          state.note,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: toneText(state.noteTone, muted: true),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  DayStrip(days: days, today: today),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color toneText(Tone t, {bool muted = false}) => switch (t) {
  Tone.ok => muted ? Palette.ink2 : Palette.ok,
  Tone.warn => Palette.warn,
  Tone.bad => Palette.bad,
  Tone.mute => Palette.ink2,
};

Color toneBg(Tone t) => switch (t) {
  Tone.ok => Palette.okBg,
  Tone.warn => Palette.warnBg,
  Tone.bad => Palette.badBg,
  Tone.mute => Palette.muteBg,
};

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.state});
  final CardState state;

  @override
  Widget build(BuildContext context) => Container(
    height: 26,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: ShapeDecoration(color: toneBg(state.tone), shape: const StadiumBorder()),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          state.label,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: toneText(state.tone)),
        ),
        if (state.detail.isNotEmpty)
          Flexible(
            child: Text(
              ' · ${state.detail}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: toneText(state.tone),
                fontFeatures: tabular,
              ),
            ),
          ),
      ],
    ),
  );
}

class DayStrip extends StatelessWidget {
  const DayStrip({super.key, required this.days, required this.today});
  final List<DayCell> days;
  final DateTime today;

  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Last 7 days: ${days.map((d) => d.name).join(', ')}',
    child: ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 7; i++)
            Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
              child: Column(
                children: [
                  DaySquare(cell: days[i]),
                  const SizedBox(height: 3),
                  Text(
                    _letters[today.subtract(Duration(days: 6 - i)).weekday - 1],
                    style: TextStyle(
                      fontSize: 11,
                      color: Palette.ink3,
                      fontWeight: i == 6 ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

/// One coloured square. Each status differs in shape or fill, not only hue.
class DaySquare extends StatelessWidget {
  const DaySquare({super.key, required this.cell, this.size = 14});
  final DayCell cell;
  final double size;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(size * 0.28);
    return switch (cell) {
      DayCell.ok => _box(Palette.ok, null, r),
      DayCell.late => _box(Palette.late, null, r),
      DayCell.miss => _box(Palette.missFill, Border.all(color: Palette.missLine, width: 1.5), r),
      DayCell.rest => _box(Palette.rest, null, r),
      DayCell.due => _box(Palette.surface, Border.all(color: Palette.ink, width: 1.5), r),
      DayCell.none => _box(Palette.surface, Border.all(color: Palette.control), r),
      DayCell.part => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: r,
          border: Border.all(color: Palette.lateLine, width: 1.5),
          gradient: const LinearGradient(
            colors: [Palette.late, Palette.late, Palette.surface, Palette.surface],
            stops: [0, 0.5, 0.5, 1],
          ),
        ),
      ),
    };
  }

  Widget _box(Color fill, Border? border, BorderRadius r) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: fill, border: border, borderRadius: r),
  );
}
