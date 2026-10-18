import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/team_color_bar.dart';
import '../domain/season_display.dart';
import '../domain/season_models.dart';

/// 라운드 칸 하나의 최소 폭(`R12` 머리글과 순위·`DNF` 글자가 들어가는 폭).
const double _minRoundCellWidth = 56;

/// 점수(마지막) 열의 폭.
const double _pointsCellWidth = 64;

/// 이름 열 안에서 순위 숫자가 차지하는 폭.
const double _positionWidth = 28;

const double _cellPadding = 12;

/// 행 하나의 배경: 내 행은 강조색, 아래에는 가는 구분선.
BoxDecoration _rowDecoration(BuildContext context, {required bool highlighted}) => BoxDecoration(
      color: highlighted ? AppColors.playerRow : null,
      border: Border(bottom: BorderSide(color: context.palette.border)),
    );

/// Results 탭(docs/12 §8.3): 드라이버 × 라운드 표. 이름 열은 고정하고 라운드·점수 열만 가로로 스크롤한다.
/// 이름 `Column`과 스크롤되는 본문 `Column`이 같은 행 높이([kResultsRowHeight])를 써서 행이 맞는다.
class SeasonResultsTab extends StatelessWidget {
  const SeasonResultsTab({super.key, required this.rounds, required this.drivers});

  final List<SeasonRound> rounds;
  final List<DriverStanding> drivers;

  @override
  Widget build(BuildContext context) {
    final headingStyle = Theme.of(context).textTheme.labelLarge?.copyWith(color: context.palette.textMuted);

    return Card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: kResultsNameColumnWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _NameHeader(style: headingStyle),
                for (final driver in drivers) _NameCell(driver: driver),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cellWidth = _roundCellWidthFor(constraints.maxWidth, rounds.length);
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _HeaderRow(rounds: rounds, cellWidth: cellWidth, style: headingStyle),
                      for (final driver in drivers)
                        _BodyRow(driver: driver, rounds: rounds, cellWidth: cellWidth),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 라운드가 적어 남는 폭은 칸이 나눠 가져 표가 카드 폭을 채운다. 라운드가 많으면 최소 폭을 지키고 가로로 스크롤한다.
  static double _roundCellWidthFor(double availableWidth, int roundCount) {
    if (roundCount == 0) {
      return _minRoundCellWidth;
    }
    return math.max(_minRoundCellWidth, (availableWidth - _pointsCellWidth) / roundCount);
  }
}

class _NameHeader extends StatelessWidget {
  const _NameHeader({required this.style});

  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('results-name-header'),
      height: kResultsRowHeight,
      padding: const EdgeInsets.symmetric(horizontal: _cellPadding),
      alignment: Alignment.centerLeft,
      decoration: _rowDecoration(context, highlighted: false),
      child: Text('Driver', style: style),
    );
  }
}

/// 순위 · 팀 색 막대 · 이름. 내 행은 강조하고 이름을 굵게 한다.
class _NameCell extends StatelessWidget {
  const _NameCell({required this.driver});

  final DriverStanding driver;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('results-name-${driver.driverKey}'),
      height: kResultsRowHeight,
      padding: const EdgeInsets.symmetric(horizontal: _cellPadding),
      decoration: _rowDecoration(context, highlighted: driver.isPlayer),
      child: Row(
        children: [
          SizedBox(
            width: _positionWidth,
            child: Text('${driver.position}', style: TextStyle(color: context.palette.textMuted)),
          ),
          TeamColorBar(key: ValueKey('results-team-bar-${driver.driverKey}'), colorHex: driver.teamColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              driver.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: driver.isPlayer ? const TextStyle(fontWeight: FontWeight.bold) : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.rounds, required this.cellWidth, required this.style});

  final List<SeasonRound> rounds;
  final double cellWidth;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('results-header-row'),
      height: kResultsRowHeight,
      decoration: _rowDecoration(context, highlighted: false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final round in rounds)
            SizedBox(
              width: cellWidth,
              child: Center(child: Text('R${round.round}', style: style)),
            ),
          SizedBox(width: _pointsCellWidth, child: Center(child: Text('Pts', style: style))),
        ],
      ),
    );
  }
}

/// 한 드라이버의 라운드별 칸 + 점수. 칸이 없는 라운드(그 드라이버의 결과가 없음)는 `-`.
class _BodyRow extends StatelessWidget {
  const _BodyRow({required this.driver, required this.rounds, required this.cellWidth});

  final DriverStanding driver;
  final List<SeasonRound> rounds;
  final double cellWidth;

  @override
  Widget build(BuildContext context) {
    final cellsByRound = {for (final cell in driver.cells) cell.round: cell};

    return Container(
      key: ValueKey('results-row-${driver.driverKey}'),
      height: kResultsRowHeight,
      decoration: _rowDecoration(context, highlighted: driver.isPlayer),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final round in rounds)
            _ResultCell(
              key: ValueKey('results-cell-${driver.driverKey}-${round.round}'),
              cell: cellsByRound[round.round],
              width: cellWidth,
            ),
          SizedBox(
            width: _pointsCellWidth,
            child: Center(child: Text('${driver.points}', style: const TextStyle(fontWeight: FontWeight.bold))),
          ),
        ],
      ),
    );
  }
}

/// 라운드 칸: 순위(1·2·3위는 금·은·동), DNF·DSQ·NC·RET·기록 없음(`-`)은 `textMuted` 글자.
class _ResultCell extends StatelessWidget {
  const _ResultCell({super.key, required this.cell, required this.width});

  final StandingCell? cell;
  final double width;

  @override
  Widget build(BuildContext context) {
    final podium = standingCellPodiumPlace(cell);
    // 순위 칸은 기본 글자색, 상태 칸·기록 없음은 textMuted.
    final color = podium != null
        ? context.palette.podiumFor(podium) // 시상대 금·은·동 글자(테마별, 밝은 테마는 대비를 높인 색).
        : (standingCellShowsPosition(cell) ? null : context.palette.textMuted);

    return SizedBox(
      width: width,
      child: Center(
        child: Text(
          standingCellText(cell),
          style: TextStyle(color: color, fontWeight: podium != null ? FontWeight.bold : null),
        ),
      ),
    );
  }
}
