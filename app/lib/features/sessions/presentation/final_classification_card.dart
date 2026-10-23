import 'package:flutter/material.dart';

import '../../../core/widgets/compact_table.dart';
import '../domain/session_detail_display.dart';
import '../domain/session_display.dart';
import '../domain/session_models.dart';
import 'session_widgets.dart';

const String _emptyText = '이 세션에는 최종 순위 데이터가 없어요.';

/// 표가 CHANGE·POINTS를 숨기는 폭(2열 카드 폭 ~520px에서는 다 보인다).
const double _compactWidth = 480;

const double _numberWidth = 32;
const double _positionWidth = 64;
const double _changeWidth = 56;
const double _pointsWidth = 52;
const double _gapWidth = 96;
const double _compareWidth = 40;
const double _compareIconSize = 18;
const String _compareTooltip = '내 최고 랩과 비교';

/// 순위 변동: 서버 `positionChange`(레이스만). 옛 서버의 레이스면 그리드 − 순위, 예선·연습은 없음(`-`).
int? _changeOf(SessionResult row, {required bool isRace}) =>
    row.positionChange ?? (isRace && row.gridPosition > 0 ? row.gridPosition - row.position : null);

/// Final Classification 카드(docs/15 §11.3): # · DRIVER(팀 점 + 이름, 나는 "You" + 강조 행) · POSITION · CHANGE · POINTS · GAP.
/// [onCompare]가 있으면 끝에 비교 버튼 열을 두고, 그 차와 내 최고 랩을 비교하게 한다([canCompare]인 행만).
class FinalClassificationCard extends StatelessWidget {
  const FinalClassificationCard({
    super.key,
    required this.results,
    required this.isRace,
    this.onCompare,
    this.canCompare,
  });

  final List<SessionResult> results;

  /// 레이스면 GAP이 총 시간 차, 아니면 최고 랩 차.
  final bool isRace;

  /// 비교 버튼을 누른 행. null이면 비교 열이 없다.
  final ValueChanged<SessionResult>? onCompare;

  /// 그 행에 비교 버튼을 보일지. null이면 모든 행.
  final bool Function(SessionResult row)? canCompare;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return const SessionCard(title: 'Final Classification', child: SessionEmptyText(_emptyText));
    }
    final reference = referenceRow(results, isRace: isRace);
    return SessionCard(
      title: 'Final Classification',
      padded: false,
      child: CompactTable<SessionResult>(
        framed: false,
        compactWidth: _compactWidth,
        rows: results,
        isHighlighted: (row) => row.isPlayer,
        rowKey: (row) => ValueKey('classification-row-${row.carIndex}'),
        columns: [
          CompactColumn(
            label: '#',
            width: _numberWidth,
            cell: (row) => Text(row.raceNumber?.toString() ?? kNoValueText, style: kTabularStyle),
          ),
          CompactColumn(
            label: 'Driver',
            flex: 4,
            cell: (row) => DriverNameCell(name: row.name, teamColor: row.teamColor, isPlayer: row.isPlayer),
          ),
          CompactColumn(
            label: 'Position',
            width: _positionWidth,
            // 좁은 화면은 순서가 곧 순위라 숨겨 드라이버 이름 폭을 확보한다.
            compactHidden: true,
            cell: (row) => Text(positionText(row.position), style: kTabularStyle.copyWith(fontWeight: FontWeight.bold)),
          ),
          CompactColumn(
            label: 'Change',
            width: _changeWidth,
            compactHidden: true,
            cell: (row) => PositionChangeText(change: _changeOf(row, isRace: isRace)),
          ),
          CompactColumn(
            label: 'Points',
            width: _pointsWidth,
            compactHidden: true,
            cell: (row) => Text('${row.points}', style: kTabularStyle),
          ),
          CompactColumn(
            label: 'Gap',
            width: _gapWidth,
            alignment: Alignment.centerRight,
            cell: (row) => Text(
              classificationGapText(row, reference, isRace: isRace),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: kTabularStyle,
            ),
          ),
          if (onCompare case final compare?)
            CompactColumn(
              label: '',
              width: _compareWidth,
              alignment: Alignment.center,
              cell: (row) => canCompare?.call(row) ?? true
                  ? IconButton(
                      key: ValueKey('classification-compare-${row.carIndex}'),
                      tooltip: _compareTooltip,
                      iconSize: _compareIconSize,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.compare_arrows),
                      onPressed: () => compare(row),
                    )
                  : const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }
}
