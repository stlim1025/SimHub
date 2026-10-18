import 'package:flutter/material.dart';

import '../../../core/widgets/compact_table.dart';
import '../domain/session_detail_display.dart';
import '../domain/session_display.dart';
import '../domain/session_models.dart';
import 'session_widgets.dart';

const String _emptyText = '이 세션에는 패널티 기록이 없어요.';
const double _lapWidth = 44;

/// 이름이 없을 때의 드라이버 표시(차 번호).
String _driverOf(SessionPenalty penalty) =>
    penalty.driverName ?? (penalty.carIndex == null ? kNoValueText : 'Car ${penalty.carIndex! + 1}');

/// 한 줄 말줄임 글자.
Widget _text(String? value) => Text(value ?? kNoValueText, maxLines: 1, overflow: TextOverflow.ellipsis);

/// Penalties 카드(docs/15 §11.3): LAP · DRIVER(팀 점, 나는 "You") · INCIDENT(침해) · PENALTY(벌칙). 내 행은 강조.
class PenaltiesCard extends StatelessWidget {
  const PenaltiesCard({super.key, required this.penalties});

  final List<SessionPenalty> penalties;

  @override
  Widget build(BuildContext context) {
    if (penalties.isEmpty) {
      return const SessionCard(title: 'Penalties', child: SessionEmptyText(_emptyText));
    }
    return SessionCard(
      title: 'Penalties',
      padded: false,
      child: CompactTable<SessionPenalty>(
        framed: false,
        rows: penalties,
        isHighlighted: (p) => p.isPlayer,
        columns: [
          CompactColumn(
            label: 'Lap',
            width: _lapWidth,
            cell: (p) => Text(p.lap?.toString() ?? kNoValueText, style: kTabularStyle),
          ),
          CompactColumn(
            label: 'Driver',
            flex: 3,
            cell: (p) => DriverNameCell(name: _driverOf(p), teamColor: p.teamColor, isPlayer: p.isPlayer),
          ),
          CompactColumn(label: 'Incident', flex: 3, cell: (p) => _text(p.infringement)),
          CompactColumn(label: 'Penalty', flex: 3, cell: (p) => _text(penaltyText(p))),
        ],
      ),
    );
  }
}
