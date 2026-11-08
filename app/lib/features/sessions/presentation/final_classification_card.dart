import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/compact_table.dart';
import '../domain/session_detail_display.dart';
import '../domain/session_display.dart';
import '../domain/session_models.dart';
import 'session_widgets.dart';
import 'tyre_stints_view.dart';

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

/// BEST(최고 랩)·TYRES(스틴트 원) 열을 보이는 표 폭 — 넓은 보드(B안)의 왼쪽 칸에서만 보인다.
const double _bestLapMinWidth = 680;
const double _tyresMinWidth = 760;
const double _bestLapWidth = 84;
const double _tyresWidth = 64;
const double _tyreCircleSize = 14;
const double _tyreCircleGap = 2;

/// TYRES 칸에 그리는 스틴트 원 최대 개수(칸 폭 안에 들어가게).
const int _maxTyreCircles = 4;

/// 순위 변동: 서버 `positionChange`(레이스만). 옛 서버의 레이스면 그리드 − 순위, 예선·연습은 없음(`-`).
int? _changeOf(SessionResult row, {required bool isRace}) =>
    row.positionChange ?? (isRace && row.gridPosition > 0 ? row.gridPosition - row.position : null);

/// Final Classification 카드(docs/15 §11.3): # · DRIVER(팀 점 + 이름, 나는 "You" + 강조 행) · POSITION · CHANGE · POINTS · GAP,
/// 표가 넓으면(B안 보드) BEST(최고 랩, 세션 최고는 보라)·TYRES(스틴트 컴파운드 원)도 보인다.
/// [onCompare]가 있으면 끝에 비교 버튼 열을 두고, 그 차와 내 최고 랩을 비교하게 한다([canCompare]인 행만).
class FinalClassificationCard extends StatelessWidget {
  const FinalClassificationCard({
    super.key,
    required this.results,
    required this.isRace,
    this.onCompare,
    this.canCompare,
    this.rowHeight = kCompactRowHeight,
  });

  final List<SessionResult> results;

  /// 레이스면 GAP이 총 시간 차, 아니면 최고 랩 차.
  final bool isRace;

  /// 비교 버튼을 누른 행. null이면 비교 열이 없다.
  final ValueChanged<SessionResult>? onCompare;

  /// 그 행에 비교 버튼을 보일지. null이면 모든 행.
  final bool Function(SessionResult row)? canCompare;

  /// 본문 행 높이(넓은 보드는 한 화면에 순위표 전체가 들어가게 낮춘다).
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return const SessionCard(title: 'Final Classification', child: SessionEmptyText(_emptyText));
    }
    final reference = referenceRow(results, isRace: isRace);
    final bestLaps = results.map((r) => r.bestLapTimeMs).nonNulls;
    final fastest = bestLaps.isEmpty ? null : bestLaps.reduce((a, b) => a < b ? a : b);
    return SessionCard(
      title: 'Final Classification',
      padded: false,
      child: CompactTable<SessionResult>(
        framed: false,
        compactWidth: _compactWidth,
        rowHeight: rowHeight,
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
          CompactColumn(
            label: 'Best',
            width: _bestLapWidth,
            hideBelowWidth: _bestLapMinWidth,
            alignment: Alignment.centerRight,
            cell: (row) => _BestLapText(ms: row.bestLapTimeMs, fastest: fastest != null && row.bestLapTimeMs == fastest),
          ),
          CompactColumn(
            label: 'Tyres',
            width: _tyresWidth,
            hideBelowWidth: _tyresMinWidth,
            cell: (row) => _TyreCircles(stints: row.tyreStints),
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

/// BEST 칸: 최고 랩(`1:12.384`), 세션 최고 랩이면 보라 굵게. 없으면 `-`.
class _BestLapText extends StatelessWidget {
  const _BestLapText({required this.ms, required this.fastest});

  final int? ms;
  final bool fastest;

  @override
  Widget build(BuildContext context) {
    final value = ms;
    return Text(
      value == null ? kNoValueText : formatRaceTime(value),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: kTabularStyle.copyWith(
        color: fastest ? AppColors.fastestLap : null,
        fontWeight: fastest ? FontWeight.bold : null,
      ),
    );
  }
}

/// TYRES 칸: 스틴트 순서대로 컴파운드 원(많아야 [_maxTyreCircles]개).
class _TyreCircles extends StatelessWidget {
  const _TyreCircles({required this.stints});

  final List<TyreStintView> stints;

  @override
  Widget build(BuildContext context) {
    if (stints.isEmpty) {
      return const Text(kNoValueText);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, stint) in stints.take(_maxTyreCircles).indexed) ...[
          if (i > 0) const SizedBox(width: _tyreCircleGap),
          TyreCompoundCircle(compound: stint.visualCompound, tooltip: stint.visualCompound, size: _tyreCircleSize),
        ],
      ],
    );
  }
}
