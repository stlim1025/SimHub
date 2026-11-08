import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../domain/race_highlights.dart';
import 'tyre_stints_view.dart';

/// 중계 그래픽 공통: 판 불투명도, 숫자는 폭이 고정된 숫자 글꼴(간격이 바뀌어도 칸이 흔들리지 않게).
const double _panelOpacity = 0.88;
const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

/// 왼쪽 순위표(방송 타워) 치수: 몸통(왼쪽 모서리는 크게 둥글게)·테두리, 위 빨간 띠, 랩 띠, 줄.
const double kBroadcastTowerWidth = 184;
const double kBroadcastCompactTowerWidth = 112;
const double _towerOpacity = 0.92;
const double _towerOuterRadius = 12;
const double _towerInnerRadius = 4;
const double _towerBorderWidth = 1.5;
const double _towerAccentHeight = 3;
const double _towerLapHeight = 28;
const double _towerLapLabelSize = 11;
const double _towerLapNumberSize = 17;
const double _towerRowHeight = 20;
const double _towerBottomPadding = 4;
const double _towerFontSize = 12;
const double _towerSmallFontSize = 9.5;
const double _towerPositionWidth = 24;
const double _towerCompactPositionWidth = 18;
const double _towerDividerWidth = 1;
const double _towerLogoSize = 17;
const double _towerLogoPadding = 2.5;
const double _towerBarWidth = 3;
const double _towerBarHeight = 13;
const double _towerGap = 5;
const double _towerSidePadding = 6;
const double _towerPitWidth = 24;
const double _towerPitHeight = 13;
const double _towerBadgeRadius = 3;
const double _towerTyreWidth = 12;
const double _towerTyreFocusSize = 14;

/// 순위표 깃발 배너(랩 띠 바로 아래): 높이, 옐로 플래그 섹터 띠 높이, 글자 크기, 사선 줄무늬 간격·굵기.
const double _flagBannerHeight = 36;
const double _flagSectorHeight = 15;
const double _flagTitleSize = 15;
const double _flagSubtitleSize = 10.5;
const double _flagSectorSize = 11;
const double _flagStripeGap = 7;
const double _flagStripeWidth = 2;

/// 순위표 깃발 배너 글자(중계 그래픽이라 영어).
const String _safetyLabel = 'SAFETY';
const String _carLabel = 'CAR';
const String _virtualLabel = 'VIRTUAL';
const String _safetyCarLabel = 'SAFETY CAR';
const String _yellowFlagLabel = 'YELLOW FLAG';
const String _redFlagLabel = 'RED FLAG';
const String _greenFlagLabel = 'GREEN FLAG';
const String _sectorLabel = 'SECTOR';
const String _sectorsLabel = 'SECTORS';
const String _sectorSeparator = ' · ';

/// 순위표 컴파운드 글자에 넘길 이름(`tyreColorOf`·`tyreLetterOf` 기준). 모르면 글자를 그리지 않는다.
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

/// 순위표 글자: 숫자는 기울인 고정폭 숫자(간격이 바뀌어도 칸이 흔들리지 않게), 이름은 바로 세운다.
TextStyle _towerText(
  BuildContext context, {
  double size = _towerFontSize,
  Color color = AppColors.replayHudText,
  FontWeight weight = FontWeight.w700,
  bool italic = true,
}) =>
    DefaultTextStyle.of(context).style.copyWith(
          color: color,
          fontSize: size,
          fontWeight: weight,
          fontStyle: italic ? FontStyle.italic : FontStyle.normal,
          letterSpacing: _letterSpacing,
          fontFeatures: _tabular,
          decoration: TextDecoration.none,
          height: 1,
        );

/// 중계 화면 왼쪽 순위표(방송 타워): 둥근 테두리 몸통, 위 빨간 띠 + 그러데이션 랩 띠(`LAP 16 /39`),
/// 줄마다 기울인 순위 · 세로 구분선 · 팀 색 원 안의 팀 로고(로고가 없으면 팀 색 띠) · 세 글자 이름 · 기울인 간격(리더는 작게 `Leader`) ·
/// 컴파운드 색 글자(S·M·H·I·W, 모르면 없음). 피트면 `PIT` 칸, 피니시면 체커기, 리타이어면 `OUT`.
/// 카메라가 따라가는 차의 줄은 흰 바탕에 검은 글자로 뒤집고, 넓으면 이름을 다 쓴다(길면 줄여 맞춘다).
/// [compact](좁은 화면)면 간격 칸을 빼고 로고 대신 팀 색 띠를 쓴다. 높이가 모자라면 들어가는 줄까지만.
/// 깃발이 걸리면([flag]) 실제 중계처럼 랩 띠 바로 아래에 배너를 띄우고 테두리를 깃발 색으로 바꾼다 — 세이프티카·버추얼은 노랑 사선 줄무늬,
/// 옐로 플래그는 노랑 줄무늬 + 섹터 띠, 적기는 빨강. 깃발이 걷힌 직후([trackClear])는 초록 그린 플래그.
class BroadcastStandingsTower extends StatelessWidget {
  const BroadcastStandingsTower({
    super.key,
    required this.standing,
    required this.totalLaps,
    required this.nameOf,
    required this.colorOf,
    required this.focusCar,
    this.logoUrlOf,
    this.flag,
    this.trackClear = false,
    this.compact = false,
  });

  /// 지금 걸린 깃발(없으면 null).
  final HighlightFlag? flag;

  /// 깃발이 걷힌 직후(그린 플래그).
  final bool trackClear;

  final HighlightStanding standing;
  final int totalLaps;
  final String Function(int carIndex) nameOf;
  final Color Function(int carIndex) colorOf;
  final int focusCar;

  /// 차의 팀 로고 URL. null이거나 null을 돌려주면 팀 색 띠를 그린다.
  final String? Function(int carIndex)? logoUrlOf;
  final bool compact;

  static const BorderRadius _outerRadius =
      BorderRadius.horizontal(left: Radius.circular(_towerOuterRadius), right: Radius.circular(_towerInnerRadius));
  static const BorderRadius _clipRadius = BorderRadius.horizontal(
    left: Radius.circular(_towerOuterRadius - _towerBorderWidth),
    right: Radius.circular(_towerInnerRadius - _towerBorderWidth),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) {
          final banner = _flagBanner(context);
          final chrome = _towerBorderWidth * 2 +
              _towerAccentHeight +
              _towerLapHeight +
              _towerBottomPadding +
              (banner == null ? 0 : _flagBannerHeight);
          final fit = ((box.maxHeight - chrome) / _towerRowHeight).floor();
          final rows = standing.rows.take(fit.clamp(0, standing.rows.length)).toList();
          return Align(
            alignment: Alignment.topLeft,
            child: Container(
              key: const ValueKey('highlights-standings'),
              decoration: BoxDecoration(
                color: AppColors.replayTowerBody.withValues(alpha: _towerOpacity),
                border: Border.all(color: _borderColor, width: _towerBorderWidth),
                borderRadius: _outerRadius,
              ),
              child: ClipRRect(
                borderRadius: _clipRadius,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(height: _towerAccentHeight, color: AppColors.replayBroadcastRed),
                    _lapBar(context),
                    ?banner,
                    for (var i = 0; i < rows.length; i++) _row(context, i, rows[i]),
                    const SizedBox(height: _towerBottomPadding),
                  ],
                ),
              ),
            ),
          );
        },
      );

  /// 테두리: 깃발이 걸리면 그 색(노랑·빨강), 걷힌 직후는 초록, 평소는 회색.
  Color get _borderColor => switch (flag?.kind) {
        RaceFlagKind.safetyCar || RaceFlagKind.virtualSafetyCar || RaceFlagKind.yellowFlag => AppColors.replayTowerFlagYellow,
        RaceFlagKind.redFlag => AppColors.replayFlagRed,
        _ => trackClear && flag == null ? AppColors.replayTowerFlagGreen : AppColors.replayTowerBorder,
      };

  /// 랩 띠 아래 깃발 배너. 띄울 것이 없으면 null.
  Widget? _flagBanner(BuildContext context) {
    final flag = this.flag;
    if (flag == null) {
      return trackClear
          ? _stripedBanner(
              AppColors.replayTowerFlagGreen,
              AppColors.replayTowerFlagGreenStripe,
              _flagBannerHeight,
              [_flagText(context, _greenFlagLabel, _flagTitleSize)],
            )
          : null;
    }
    return switch (flag.kind) {
      RaceFlagKind.safetyCar => _stripedBanner(
          AppColors.replayTowerFlagYellow,
          AppColors.replayTowerFlagYellowStripe,
          _flagBannerHeight,
          [_flagText(context, _safetyLabel, _flagTitleSize), _flagText(context, _carLabel, _flagSubtitleSize)],
        ),
      RaceFlagKind.virtualSafetyCar => _stripedBanner(
          AppColors.replayTowerFlagYellow,
          AppColors.replayTowerFlagYellowStripe,
          _flagBannerHeight,
          [_flagText(context, _virtualLabel, _flagTitleSize), _flagText(context, _safetyCarLabel, _flagSubtitleSize)],
        ),
      RaceFlagKind.yellowFlag => Column(
          key: const ValueKey('highlights-standings-flag'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _stripedBanner(
              AppColors.replayTowerFlagYellow,
              AppColors.replayTowerFlagYellowStripe,
              _flagBannerHeight - _flagSectorHeight,
              [_flagText(context, _yellowFlagLabel, _flagTitleSize)],
              keyed: false,
            ),
            Container(
              height: _flagSectorHeight,
              alignment: Alignment.center,
              color: AppColors.replayTowerBody,
              child: Text(
                _sectorText(flag.sectors),
                style: _towerText(context, size: _flagSectorSize, color: AppColors.replayTowerSectorText, weight: FontWeight.w800),
              ),
            ),
          ],
        ),
      RaceFlagKind.redFlag => Container(
          key: const ValueKey('highlights-standings-flag'),
          height: _flagBannerHeight,
          alignment: Alignment.center,
          color: AppColors.replayFlagRed,
          child: _flagText(context, _redFlagLabel, _flagTitleSize, color: AppColors.replayHudText),
        ),
      RaceFlagKind.unknown => null,
    };
  }

  /// 옐로 플래그 섹터 글자: `SECTOR 2`, 여럿이면 `SECTORS 1 · 3`, 모르면 빈 글자.
  static String _sectorText(List<int> sectors) => switch (sectors.length) {
        0 => '',
        1 => '$_sectorLabel ${sectors.single}',
        _ => '$_sectorsLabel ${sectors.join(_sectorSeparator)}',
      };

  Widget _flagText(BuildContext context, String text, double size, {Color color = AppColors.replayFlagYellowText}) =>
      Text(text, maxLines: 1, style: _towerText(context, size: size, color: color, weight: FontWeight.w900));

  /// 사선 줄무늬 바탕 위에 가운데 정렬한 글자 줄들.
  Widget _stripedBanner(Color base, Color stripe, double height, List<Widget> lines, {bool keyed = true}) => SizedBox(
        key: keyed ? const ValueKey('highlights-standings-flag') : null,
        height: height,
        child: CustomPaint(
          painter: _StripePainter(base, stripe),
          child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: lines)),
        ),
      );

  Widget _lapBar(BuildContext context) {
    final label = _towerText(context, size: _towerLapLabelSize, color: AppColors.replayHudMuted, weight: FontWeight.w600);
    return Container(
      height: _towerLapHeight,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.replayTowerLapTop, AppColors.replayTowerLapBottom],
        ),
        border: Border(bottom: BorderSide(color: AppColors.replayTowerDivider)),
      ),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: 'LAP ', style: label),
          TextSpan(text: '${standing.lap}', style: _towerText(context, size: _towerLapNumberSize, weight: FontWeight.w900)),
          if (totalLaps > 0) TextSpan(text: ' /$totalLaps', style: label),
        ]),
        key: const ValueKey('highlights-standings-lap'),
      ),
    );
  }

  Widget _row(BuildContext context, int index, HighlightStandingRow row) {
    final focused = row.carIndex == focusCar;
    final ink = focused ? AppColors.replayTowerBody : AppColors.replayHudText;
    final name = nameOf(row.carIndex);
    final out = row.state == StandingState.out;
    final leader = index == 0 && !out;
    final gap = out ? 'OUT' : (compact ? '' : standingGapText(row, leader: index == 0));
    final gapStyle = _towerText(
      context,
      size: leader ? _towerSmallFontSize : _towerFontSize - 1,
      color: focused ? ink : (leader || out ? AppColors.replayHudMuted : AppColors.replayHudText),
    );
    final mark = switch (row.state) {
      StandingState.pit => Container(
          width: _towerPitWidth,
          height: _towerPitHeight,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: focused ? AppColors.replayTowerBody : AppColors.replayTowerPitBadge,
            borderRadius: BorderRadius.circular(_towerBadgeRadius),
          ),
          child: Text(
            'PIT',
            style: _towerText(
              context,
              size: _towerSmallFontSize,
              color: focused ? AppColors.replayHudText : AppColors.replayTowerBody,
              weight: FontWeight.w900,
              italic: false,
            ),
          ),
        ),
      StandingState.finished => Icon(Icons.sports_score, size: _towerPitHeight + 2, color: ink),
      _ => null,
    };
    final tyre = kHighlightTyreNames[row.tyre];
    return Container(
      key: ValueKey('standing-row-${row.carIndex}'),
      height: _towerRowHeight,
      color: focused ? AppColors.replayHudText : null,
      padding: const EdgeInsets.only(right: _towerSidePadding),
      child: Row(
        children: [
          SizedBox(
            width: compact ? _towerCompactPositionWidth : _towerPositionWidth,
            child: Text(
              '${index + 1}',
              textAlign: TextAlign.center,
              style: _towerText(context, color: focused ? ink : AppColors.replayTowerPosition, weight: FontWeight.w600),
            ),
          ),
          Container(
            width: _towerDividerWidth,
            height: _towerRowHeight,
            color: focused ? AppColors.replayTowerPitBadge : AppColors.replayTowerDivider,
          ),
          const SizedBox(width: _towerGap),
          SizedBox(width: compact ? _towerBarWidth : _towerLogoSize, height: _towerLogoSize, child: _teamMark(row.carIndex)),
          const SizedBox(width: _towerGap),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      focused && !compact ? name.toUpperCase() : standingAbbreviation(name),
                      style: _towerText(context, color: ink, weight: FontWeight.w800, italic: false),
                    ),
                  ),
                ),
                if (gap.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(left: _towerGap), child: Text(gap, style: gapStyle)),
              ],
            ),
          ),
          if (mark != null) ...[const SizedBox(width: _towerGap), mark],
          if (tyre != null) ...[const SizedBox(width: _towerGap), _tyre(context, row.carIndex, tyre, focused)],
        ],
      ),
    );
  }

  /// 팀 표시: 로고가 있으면 팀 색 원 안의 로고(서버 로고는 팀 색 바탕에 맞춘 그림이라 프로필 사진처럼 원에 얹는다,
  /// 읽는 중·못 읽으면 빈 원), 로고가 없거나 좁은 화면이면 팀 색 세로 띠.
  Widget _teamMark(int carIndex) {
    final color = colorOf(carIndex);
    final url = compact ? null : logoUrlOf?.call(carIndex);
    if (url == null) {
      return Center(
        child: Container(
          width: _towerBarWidth,
          height: _towerBarHeight,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(_towerBarWidth / 2)),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      padding: const EdgeInsets.all(_towerLogoPadding),
      child: Image.network(
        url,
        key: ValueKey('standing-logo-$carIndex'),
        fit: BoxFit.contain,
        frameBuilder: (_, child, frame, wasSynchronouslyLoaded) =>
            frame == null && !wasSynchronouslyLoaded ? const SizedBox.shrink() : child,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }

  /// 컴파운드 색 글자. 흰 바탕(따라가는 차) 줄에서는 색이 묻히지 않게 어두운 칸 위에 쓴다.
  Widget _tyre(BuildContext context, int carIndex, String compound, bool focused) => Tooltip(
        message: compound,
        child: Container(
          key: ValueKey('standing-tyre-$carIndex'),
          width: focused ? _towerTyreFocusSize : _towerTyreWidth,
          height: focused ? _towerTyreFocusSize : null,
          alignment: Alignment.center,
          decoration: focused
              ? BoxDecoration(color: AppColors.replayTowerBody, borderRadius: BorderRadius.circular(_towerBadgeRadius))
              : null,
          child: Text(tyreLetterOf(compound), style: _towerText(context, color: tyreColorOf(compound), weight: FontWeight.w900)),
        ),
      );
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

/// 깃발 배너 바탕: [base] 색 위에 왼쪽 아래에서 오른쪽 위로 가는 [stripe] 색 사선 줄무늬.
class _StripePainter extends CustomPainter {
  const _StripePainter(this.base, this.stripe);

  final Color base;
  final Color stripe;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = base);
    final paint = Paint()
      ..color = stripe
      ..strokeWidth = _flagStripeWidth;
    for (var x = -size.height; x < size.width; x += _flagStripeGap) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), paint);
    }
  }

  @override
  bool shouldRepaint(_StripePainter oldDelegate) => oldDelegate.base != base || oldDelegate.stripe != stripe;
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
