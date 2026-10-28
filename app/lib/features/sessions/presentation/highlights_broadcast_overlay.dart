import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../domain/race_highlights.dart';
import 'tyre_stints_view.dart';

/// 중계 그래픽 공통: 판 불투명도, 숫자는 폭이 고정된 숫자 글꼴(간격이 바뀌어도 칸이 흔들리지 않게).
const double _panelOpacity = 0.88;
const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

/// 왼쪽 순위표 치수.
const double kBroadcastTowerWidth = 172;
const double kBroadcastCompactTowerWidth = 104;
const double _towerAccentHeight = 3;
const double _towerHeaderHeight = 24;
const double _towerRowHeight = 19;
const double _towerFontSize = 11.5;
const double _towerPositionWidth = 22;
const double _towerNameWidth = 36;
const double _towerBarWidth = 4;
const double _towerBarHeight = 13;
const double _towerGap = 5;
const double _towerMarkWidth = 26;
const double _towerMarkHeight = 13;
const double _towerSidePadding = 6;
const double _towerTyreSize = 13;

/// 순위표 컴파운드 원에 넘길 이름(`tyreColorOf`·`TyreCompoundCircle` 기준). 모르면 원을 그리지 않는다.
const Map<HighlightTyre, String> kHighlightTyreNames = {
  HighlightTyre.soft: 'Soft',
  HighlightTyre.medium: 'Medium',
  HighlightTyre.hard: 'Hard',
  HighlightTyre.intermediate: 'Intermediate',
  HighlightTyre.wet: 'Wet',
};
const double _letterSpacing = 0.4;

/// 하단 자막·위 띠 치수.
const EdgeInsets _tagPadding = EdgeInsets.symmetric(horizontal: 10, vertical: 5);
const EdgeInsets _titlePadding = EdgeInsets.symmetric(horizontal: 12, vertical: 6);
const double _titleFontSize = 15;
const double _tagFontSize = 11;
const double _captionBarWidth = 4;
const EdgeInsets _stripPadding = EdgeInsets.symmetric(horizontal: 22, vertical: 6);
const double _stripFontSize = 15;
const double _stripIconSize = 18;
const double _checkerCell = 6;
const int _checkerColumns = 4;
const double _stripGap = 8;

TextStyle _broadcastText(BuildContext context, {double size = _towerFontSize, Color color = AppColors.replayHudText}) =>
    DefaultTextStyle.of(context).style.copyWith(
          color: color,
          fontSize: size,
          fontWeight: FontWeight.w800,
          letterSpacing: _letterSpacing,
          fontFeatures: _tabular,
          decoration: TextDecoration.none,
        );

/// 중계 화면 왼쪽 순위표: 빨간 띠 + `LAP 16 / 39` 머리, 줄마다 순위·팀 색 띠·세 글자 이름·간격,
/// 피트면 `PIT` 칸, 피니시면 체커기, 리타이어면 `OUT`, 줄 끝에 끼고 있는 컴파운드 원(모르면 없음). 카메라가 따라가는 차의 줄은 흰 바탕에 검은 글자로 뒤집는다.
/// [compact](좁은 화면)면 간격 칸을 뺀다. 높이가 모자라면 들어가는 줄까지만.
class BroadcastStandingsTower extends StatelessWidget {
  const BroadcastStandingsTower({
    super.key,
    required this.standing,
    required this.totalLaps,
    required this.nameOf,
    required this.colorOf,
    required this.focusCar,
    this.compact = false,
  });

  final HighlightStanding standing;
  final int totalLaps;
  final String Function(int carIndex) nameOf;
  final Color Function(int carIndex) colorOf;
  final int focusCar;
  final bool compact;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) {
          final fit = ((box.maxHeight - _towerAccentHeight - _towerHeaderHeight) / _towerRowHeight).floor();
          final rows = standing.rows.take(fit.clamp(0, standing.rows.length)).toList();
          final text = _broadcastText(context);
          return Align(
            alignment: Alignment.topLeft,
            child: Column(
              key: const ValueKey('highlights-standings'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(height: _towerAccentHeight, color: AppColors.replayBroadcastRed),
                Container(
                  height: _towerHeaderHeight,
                  color: AppColors.replayBroadcastPanel.withValues(alpha: _panelOpacity),
                  padding: const EdgeInsets.symmetric(horizontal: _towerSidePadding),
                  alignment: Alignment.centerLeft,
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: 'LAP  ', style: text.copyWith(color: AppColors.replayHudMuted)),
                      TextSpan(text: '${standing.lap}'),
                      if (totalLaps > 0) TextSpan(text: ' / $totalLaps', style: text.copyWith(color: AppColors.replayHudMuted)),
                    ]),
                    key: const ValueKey('highlights-standings-lap'),
                    style: text,
                  ),
                ),
                for (var i = 0; i < rows.length; i++) _row(context, i, rows[i]),
              ],
            ),
          );
        },
      );

  Widget _row(BuildContext context, int index, HighlightStandingRow row) {
    final focused = row.carIndex == focusCar;
    final ink = focused ? AppColors.replayBroadcastPanel : AppColors.replayHudText;
    final text = _broadcastText(context, color: ink);
    final muted = _broadcastText(context, color: focused ? AppColors.replayBroadcastPanel : AppColors.replayHudMuted)
        .copyWith(fontWeight: FontWeight.w600);
    final background = focused
        ? AppColors.replayHudText
        : (index.isEven ? AppColors.replayBroadcastPanel : AppColors.replayBroadcastRow).withValues(alpha: _panelOpacity);
    final gap = row.state == StandingState.out
        ? Text('OUT', style: muted)
        : (compact ? const SizedBox.shrink() : Text(standingGapText(row, leader: index == 0), style: muted));
    final mark = switch (row.state) {
      StandingState.pit => Container(
          width: _towerMarkWidth,
          height: _towerMarkHeight,
          alignment: Alignment.center,
          color: focused ? AppColors.replayBroadcastPanel : AppColors.replayHudText,
          child: Text(
            'PIT',
            style: _broadcastText(
              context,
              size: _towerFontSize - 2,
              color: focused ? AppColors.replayHudText : AppColors.replayBroadcastPanel,
            ),
          ),
        ),
      StandingState.finished => Icon(Icons.sports_score, size: _towerMarkHeight + 2, color: ink),
      _ => null,
    };
    final tyre = kHighlightTyreNames[row.tyre];
    return Container(
      key: ValueKey('standing-row-${row.carIndex}'),
      height: _towerRowHeight,
      color: background,
      padding: const EdgeInsets.only(right: _towerSidePadding),
      child: Row(
        children: [
          SizedBox(width: _towerPositionWidth, child: Text('${index + 1}', style: text, textAlign: TextAlign.center)),
          Container(width: _towerBarWidth, height: _towerBarHeight, color: colorOf(row.carIndex)),
          const SizedBox(width: _towerGap),
          SizedBox(width: _towerNameWidth, child: Text(standingAbbreviation(nameOf(row.carIndex)), style: text)),
          Expanded(child: Align(alignment: Alignment.centerRight, child: gap)),
          if (mark != null) ...[const SizedBox(width: _towerGap), mark],
          if (tyre != null) ...[
            const SizedBox(width: _towerGap),
            TyreCompoundCircle(key: ValueKey('standing-tyre-${row.carIndex}'), compound: tyre, tooltip: tyre, size: _towerTyreSize),
          ],
        ],
      ),
    );
  }
}

/// 하단 자막: 빨간 머리 칸(`LAP 16 · 추월`) 아래 중심 차 팀 색 띠 + 본문(`RUSSELL → NORRIS`). 본문이 없으면 머리 칸만.
class BroadcastCaption extends StatelessWidget {
  const BroadcastCaption({super.key, required this.tag, required this.title, required this.accent});

  final String tag;
  final String title;
  final Color accent;

  @override
  Widget build(BuildContext context) => Column(
        key: const ValueKey('highlights-caption'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            color: AppColors.replayBroadcastRed,
            padding: _tagPadding,
            child: Text(tag, key: const ValueKey('highlights-caption-tag'), style: _broadcastText(context, size: _tagFontSize)),
          ),
          if (title.isNotEmpty)
            Container(
              color: AppColors.replayBroadcastPanel.withValues(alpha: _panelOpacity),
              child: IntrinsicHeight(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(width: _captionBarWidth, color: accent),
                    Flexible(
                      child: Padding(
                        padding: _titlePadding,
                        child: Text(
                          title,
                          key: const ValueKey('highlights-caption-title'),
                          style: _broadcastText(context, size: _titleFontSize),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
}

/// 위 깃발 띠: 세이프티카·버추얼은 노랑(검은 글자), 적기는 빨강.
class BroadcastFlagStrip extends StatelessWidget {
  const BroadcastFlagStrip(this.kind, {super.key});

  final RaceFlagKind kind;

  @override
  Widget build(BuildContext context) {
    final red = kind == RaceFlagKind.redFlag;
    final ink = red ? AppColors.replayHudText : AppColors.replayFlagYellowText;
    return Container(
      key: const ValueKey('highlights-flag'),
      color: red ? AppColors.replayFlagRed : AppColors.replayFlagYellow,
      padding: _stripPadding,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.flag, size: _stripIconSize, color: ink),
          const SizedBox(width: _stripGap),
          Text(kRaceFlagLabels[kind]!, style: _broadcastText(context, size: _stripFontSize, color: ink)),
        ],
      ),
    );
  }
}

/// 위 피니시 띠: 양쪽 체커 무늬 사이에 `피니시`.
class BroadcastFinishStrip extends StatelessWidget {
  const BroadcastFinishStrip({super.key});

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('highlights-finish'),
        color: AppColors.replayBroadcastPanel.withValues(alpha: _panelOpacity),
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Checker(),
              Padding(
                padding: _stripPadding,
                child: Text(kHighlightFinishLabel, style: _broadcastText(context, size: _stripFontSize)),
              ),
              const _Checker(),
            ],
          ),
        ),
      );
}

/// 체커 무늬 칸(세로는 부모 높이를 채운다).
class _Checker extends StatelessWidget {
  const _Checker();

  @override
  Widget build(BuildContext context) =>
      const CustomPaint(size: Size(_checkerCell * _checkerColumns, 0), painter: _CheckerPainter());
}

class _CheckerPainter extends CustomPainter {
  const _CheckerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final white = Paint()..color = AppColors.replayHudText;
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.replayBroadcastPanel);
    final rows = (size.height / _checkerCell).ceil();
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < _checkerColumns; c++) {
        if ((r + c).isEven) {
          canvas.drawRect(Rect.fromLTWH(c * _checkerCell, r * _checkerCell, _checkerCell, _checkerCell), white);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerPainter oldDelegate) => false;
}
