import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/util/hex_color.dart';
import '../../sessions/domain/session_display.dart' show kNoValueText;
import '../domain/season_models.dart';

const String _raceLabel = 'RACE';
const String _qualifyingLabel = 'QUALIFYING';
const String _pointsLabel = 'POINTS';
const String _podiumsLabel = 'PODIUMS';
const String _bestFinishLabel = 'BEST RACE FINISH';
const String _bestGridLabel = 'HIGHEST GRID POSITION';
const String _dnfLabel = 'DNF';

/// 순위 막대 길이를 정하는 그리드 크기(P1 = 가장 긴 막대, 이 순위보다 뒤면 0).
const int _gridSize = 22;

const double _cardPadding = 20;
const double _headerGap = 16;
const double _nameBarWidth = 4;
const double _nameBarHeight = 22;
const double _nameGap = 8;
const double _valueWidth = 64;
const double _valueFontSize = 26;
const double _labelLetterSpacing = 2;
const double _labelGap = 4;
const double _barHeight = 20;
const double _centerLineWidth = 2;
const double _centerLineHeight = 28;
const double _rowGap = 10;

/// 팀메이트 맞대결(F1 시즌 맞대결 그래픽 모양): 위에 나(왼쪽, 강조색) · 팀 이름 · 팀메이트(오른쪽, 팀 색),
/// 아래로 항목마다 가운데 선에서 양쪽으로 뻗는 막대와 양 끝의 큰 숫자. 막대 길이는 두 값 중 큰 쪽을 꽉 채운 비율이고,
/// 순위 항목(최고 완주·최고 출발)은 앞 순위일수록 길다.
class TeammateHeadToHeadCard extends StatelessWidget {
  const TeammateHeadToHeadCard({super.key, required this.headToHead});

  final TeammateHeadToHead headToHead;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final h2h = headToHead;
    final mateColor = parseHexColor(h2h.teamColor, fallback: palette.textMuted);
    final rows = [
      (key: 'race', label: _raceLabel, values: h2h.races, position: false),
      (key: 'qualifying', label: _qualifyingLabel, values: h2h.qualifying, position: false),
      (key: 'points', label: _pointsLabel, values: h2h.points, position: false),
      (key: 'podiums', label: _podiumsLabel, values: h2h.podiums, position: false),
      (key: 'best-finish', label: _bestFinishLabel, values: h2h.bestRaceFinish, position: true),
      (key: 'best-grid', label: _bestGridLabel, values: h2h.highestGrid, position: true),
      (key: 'dnf', label: _dnfLabel, values: h2h.dnfs, position: false),
    ];
    return Card(
      key: const ValueKey('season-h2h'),
      child: Padding(
        padding: const EdgeInsets.all(_cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(headToHead: h2h, mateColor: mateColor),
            const SizedBox(height: _headerGap),
            for (final row in rows)
              _StatRow(
                key: ValueKey('season-h2h-${row.key}'),
                label: row.label,
                values: row.values,
                position: row.position,
                mateColor: mateColor,
              ),
          ],
        ),
      ),
    );
  }
}

/// 이름 줄: [나 막대 · 이름] · 팀 이름 · [이름 · 팀메이트 막대].
class _Header extends StatelessWidget {
  const _Header({required this.headToHead, required this.mateColor});

  final TeammateHeadToHead headToHead;
  final Color mateColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800);
    Widget bar(Color color) => Container(
          width: _nameBarWidth,
          height: _nameBarHeight,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(_nameBarWidth / 2)),
        );
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              bar(AppColors.accent),
              const SizedBox(width: _nameGap),
              Flexible(child: Text(headToHead.myName, maxLines: 1, overflow: TextOverflow.ellipsis, style: name)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _nameGap),
          child: Text(
            headToHead.teamName,
            style: theme.textTheme.bodySmall?.copyWith(color: context.palette.textMuted, letterSpacing: _labelLetterSpacing),
          ),
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  headToHead.teammateName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: name,
                ),
              ),
              const SizedBox(width: _nameGap),
              bar(mateColor),
            ],
          ),
        ),
      ],
    );
  }
}

/// 항목 한 줄: 가운데 위 라벨, 아래 [내 값 | 왼쪽으로 뻗는 내 막대 | 가운데 선 | 오른쪽으로 뻗는 팀메이트 막대 | 팀메이트 값].
class _StatRow extends StatelessWidget {
  const _StatRow({
    super.key,
    required this.label,
    required this.values,
    required this.position,
    required this.mateColor,
  });

  final String label;
  final HeadToHeadValues values;

  /// 순위 항목이면 값을 `P2`로 쓰고 앞 순위일수록 막대가 길다.
  final bool position;
  final Color mateColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final (mine, theirs) = headToHeadFractions(values, position: position);
    final valueStyle = theme.textTheme.headlineSmall?.copyWith(
      fontSize: _valueFontSize,
      fontWeight: FontWeight.w900,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    Widget bar(double fraction, Color color, Alignment alignment) => Expanded(
          child: SizedBox(
            height: _barHeight,
            child: Align(
              alignment: alignment,
              child: FractionallySizedBox(
                widthFactor: fraction,
                heightFactor: 1,
                child: DecoratedBox(decoration: BoxDecoration(color: color)),
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: _rowGap),
      child: Column(
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: palette.textMuted, letterSpacing: _labelLetterSpacing),
          ),
          const SizedBox(height: _labelGap),
          Row(
            children: [
              SizedBox(
                width: _valueWidth,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(_text(values.me), style: valueStyle),
                ),
              ),
              bar(mine, AppColors.accent, Alignment.centerRight),
              Container(width: _centerLineWidth, height: _centerLineHeight, color: palette.textMuted),
              bar(theirs, mateColor, Alignment.centerLeft),
              SizedBox(
                width: _valueWidth,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(_text(values.teammate), style: valueStyle),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _text(int? value) => value == null ? kNoValueText : (position ? 'P$value' : '$value');
}

/// 막대 길이 비율(나, 팀메이트) — 0~1. 횟수 항목은 큰 값을 1로, 순위 항목은 `(그리드 + 1 − 순위)`를 점수로 삼아 큰 점수를 1로 둔다.
/// 둘 다 0이거나 기록이 없으면 0. 순수 함수.
(double, double) headToHeadFractions(HeadToHeadValues values, {required bool position}) {
  double score(int? value) {
    if (value == null) {
      return 0;
    }
    if (!position) {
      return value.toDouble();
    }
    return value > 0 ? (_gridSize + 1 - value).clamp(0, _gridSize).toDouble() : 0;
  }

  final mine = score(values.me);
  final theirs = score(values.teammate);
  final top = mine > theirs ? mine : theirs;
  return top <= 0 ? (0, 0) : (mine / top, theirs / top);
}
