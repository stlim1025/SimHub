import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/domain/user_preferences.dart';
import '../../lap_detail/domain/ghost_replay.dart';
import '../../lap_detail/presentation/ghost_replay_hud.dart';
import '../domain/race_highlights.dart';
import 'tyre_stints_view.dart';

/// 중계 그래픽 공통: 판 불투명도, 숫자는 폭이 고정된 숫자 글꼴(간격이 바뀌어도 칸이 흔들리지 않게).
const double _panelOpacity = 0.88;
const List<FontFeature> _tabular = [FontFeature.tabularFigures()];
const double _letterSpacing = 0.4;

// -- 순위표(방송 타워) 설계 치수 ------------------------------------------------------------
// 참고한 중계 그래픽(F1TV-HUD-Reworked 리더보드)의 픽셀 단위 그대로 그리고, 화면에서는 재생 화면 높이에 맞춰
// 통째로 키우거나 줄인다([broadcastTowerWidth]). 아래 값은 모두 그 설계 단위다.

/// 몸통(둥근 틀 포함) 폭: 넓은 순위표·좁은 순위표(간격 칸 없음).
const double _dBodyWidth = 333;
const double _dCompactBodyWidth = 227;

/// 몸통 오른쪽 밖 표시 칸(피트 P·체커) 폭.
const double _dBadgeLaneWidth = 40;

/// 넓은 순위표·좁은 순위표 설계 폭(몸통 + 오른쪽 밖 표시 칸).
const double kBroadcastTowerDesignWidth = _dBodyWidth + _dBadgeLaneWidth;
const double kBroadcastCompactTowerDesignWidth = _dCompactBodyWidth + _dBadgeLaneWidth;

/// 화면 배율 상한(차가 적어도 지나치게 커지지 않게)과 깃발 배너가 뜰 때 줄어드는 시간.
const double _maxTowerScale = 0.75;
const Duration _towerScaleDuration = Duration(milliseconds: 300);

/// 둥근 틀: 바깥 모서리, 안쪽 판 위치·모서리, 판 아래 여백.
const double _dBezelRadius = 36;
const double _dPanelLeft = 19;
const double _dPanelTop = 22;
const double _dPanelRadius = 25;
const double _dBezelBelowPanel = 16;
const double _bezelOpacity = 0.9;
const double _towerPanelOpacity = 0.85;

/// 판 안쪽 회색 선(오른쪽은 열린 둥근 테두리): 판에서 들어간 거리, 굵기, 모서리, 마지막 줄 아래 거리.
const double _dEdgeLeft = 4;
const double _dEdgeTop = 3;
const double _dEdgeWidth = 4;
const double _dEdgeRadius = 20;
const double _dEdgeBelowRows = 3;

/// 깃발 테두리: 옐로·그린은 왼쪽 위 모서리에서 이 거리까지만 색이 번진다. 세이프티카·적기는 오른쪽 끝으로 갈수록 옅어진다.
const double _dEdgeFlagReach = 430;
const double _edgeFlagSolidStop = 0.55;

/// 머리(로고·세션 이름), 랩 띠, 랩 띠와 첫 줄 사이, 줄, 마지막 줄 아래 판 여백, 깃발 배너(위 줄무늬 칸).
const double _dContentLeft = 27;
const double _dHeaderHeight = 75;
const double _dLapHeight = 50;
const double _dRowsGap = 13;
const double _dRowHeight = 50;
const double _dPanelBelowRows = 11;
const double _dBannerHeight = 105;
const double _dBannerTopHeight = 50;

/// 머리: 왼쪽 로고 글자(상표 대신 앱 이름), 오른쪽 세션 이름(회색, 칸에 맞춰 줄인다).
const String _brandWordmark = 'SIMHUB';
const String _sessionLabel = 'RACE';
const double _dBrandLeft = 35;
const double _dBrandTop = 44;
const double _dBrandHeight = 40;
const double _dBrandSize = 38;
const double _dSessionLeft = 189;
const double _dSessionWidth = 135;
const double _dSessionTop = 46;
const double _dSessionHeight = 40;
const double _dSessionSize = 40;

/// 랩 띠 글자: `LAP`(회색), 지금 랩(굵게), `/39`(회색).
const double _dLapLabelSize = 28;
const double _dLapNumberSize = 36;
const double _dLapTotalSize = 26;

/// 줄 칸(줄 왼쪽 기준): 순위, 팀 로고, 이름, 간격(오른쪽 끝 맞춤), 컴파운드 글자. 순위 칸 오른쪽 세로선.
const double _dPositionWidth = 45;
const double _dLogoLeft = 45;
const double _dLogoWidth = 55;
const double _dLogoPadding = 5;
const double _dNameLeft = 100;
const double _dNameWidth = 100;
const double _dCompactNameWidth = 65;
const double _dTimingLeft = 140;
const double _dTimingWidth = 125;
const double _dTimingPadding = 5;
const double _dTyreLeft = 265;
const double _dCompactTyreLeft = 165;
const double _dTyreWidth = 35;
const double _dDividerWidth = 1;
const double _dTeamBarWidth = 5;
const double _dTeamBarHeight = 30;

/// 줄 글자 크기: 순위, 이름, 간격, `Leader`, `OUT`, `IN PIT`, 컴파운드. `OUT` 줄은 흐리게.
const double _dPositionSize = 23;
const double _dPositionFocusSize = 26;
const double _dNameSize = 28;
const double _dTimingSize = 24;
const double _dLeaderSize = 22;
const double _dOutSize = 23;
const double _dPitSize = 23;
const double _dTyreSize = 27;
const double _outOpacity = 0.65;

/// 따라가는 차 줄: 밝은 사선 줄무늬 바탕(줄 왼쪽 1부터), 팀 색 로고 칸, 성 칸(칸에 맞춰 줄인다).
const double _dFocusLeft = 1;
const double _dFocusLogoWidth = 65;
const double _dFocusLogoPadding = 4;
const double _dFocusNameLeft = 115;
const double _dFocusNameSize = 27;
const double _dFocusStripeGap = 6;
const double _dFocusStripeWidth = 1.2;

/// 몸통 오른쪽 밖 칸(피트 P·체커): 위치, 크기, 모서리, P 글자, 체커 칸 수.
const double _dBadgeOverlap = 3;
const double _dBadgeTop = 5;
const double _dBadgeWidth = 35;
const double _dBadgeHeight = 40;
const double _dBadgeRadius = 5;
const double _dBadgeTextSize = 26;
const double _dCheckerInset = 3;
const int _checkerCells = 5;
const String _pitBadgeLabel = 'P';

/// 깃발 배너 글자 크기(설계 단위)와 사선 줄무늬 간격·굵기, 아래 칸 + 무늬 간격·팔 길이·굵기, 적기 위 빨강 덧칠.
const double _dSafetySize = 40;
const double _dVirtualSize = 40;
const double _dVirtualSubSize = 28;
const double _dFlagTitleSize = 32;
const double _dSectorLabelSize = 28;
const double _dSectorNumberSize = 42;
const double _dTrackClearSize = 30;
const double _dRedFlagSize = 50;
const double _dBannerStripeGap = 4.2;
const double _dBannerStripeWidth = 1.6;
const double _dBandGridStep = 9;
const double _dBandGridArm = 2;
const double _dBandGridStroke = 1;
const double _redOverlayOpacity = 0.15;

/// 순위표 깃발 배너 글자(중계 그래픽이라 영어).
const String _safetyLabel = 'SAFETY';
const String _carLabel = 'CAR';
const String _virtualLabel = 'VIRTUAL';
const String _safetyCarLabel = 'SAFETY CAR';
const String _yellowFlagLabel = 'YELLOW FLAG';
const String _redFlagLabel = 'RED FLAG';
const String _greenFlagLabel = 'GREEN FLAG';
const String _trackClearLabel = 'TRACK CLEAR';
const String _sectorLabel = 'SECTOR';
const String _sectorsLabel = 'SECTORS';
const String _sectorSeparator = ' · ';
const String _outLabel = 'OUT';
const String _inPitLabel = 'IN PIT';

/// 어두운 단색 로고(검정·남색 글자, 흰 바탕 포함) 판별: 흰 바탕으로 볼 밝기, 흰 바탕을 뺀 화소의 평균 밝기 상한,
/// 무채색으로 볼 채도 폭(0~255)과 그 비율. 팀 색이 [_darkTintLuminance]보다 어두우면 흰색으로 칠한다.
/// 밝기를 잴 때 건너뛰는 화소 간격·불투명 기준.
const double _logoWhiteLuminance = 0.85;
const double _darkLogoLuminance = 0.3;
const int _monoChroma = 80;
const double _monoShare = 0.85;
const double _darkTintLuminance = 0.15;
const int _logoSampleStride = 4;
const int _opaqueAlpha = 128;
const double _channelMax = 255;

/// 밝기 가중치(Rec. 709): 어두운 단색 로고의 흰 바탕을 투명하게 빼는 색 행렬에 쓴다.
const double _lumaRed = 0.2126;
const double _lumaGreen = 0.7152;
const double _lumaBlue = 0.0722;

/// 순위표 컴파운드 글자에 넘길 이름(`tyreColorOf`·`tyreLetterOf` 기준). 모르면 글자를 그리지 않는다.
const Map<HighlightTyre, String> kHighlightTyreNames = {
  HighlightTyre.soft: 'Soft',
  HighlightTyre.medium: 'Medium',
  HighlightTyre.hard: 'Hard',
  HighlightTyre.intermediate: 'Intermediate',
  HighlightTyre.wet: 'Wet',
};

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

TextStyle _broadcastText(BuildContext context, {double size = _stripFontSize, Color color = AppColors.replayHudText}) =>
    DefaultTextStyle.of(context).style.copyWith(
          color: color,
          fontSize: size,
          fontWeight: FontWeight.w800,
          letterSpacing: _letterSpacing,
          fontFeatures: _tabular,
          decoration: TextDecoration.none,
        );

/// 순위표 글자(설계 단위 크기): 숫자는 고정폭 숫자, 기울임은 [italic].
TextStyle _towerText(
  BuildContext context, {
  required double size,
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

/// 순위표 [rows]줄과 깃발 배너([banner])를 그릴 때의 설계 높이(순수 함수).
double broadcastTowerDesignHeight(int rows, {required bool banner}) =>
    _dPanelTop +
    _dHeaderHeight +
    _dLapHeight +
    (banner ? _dBannerHeight : 0) +
    _dRowsGap +
    rows * _dRowHeight +
    _dPanelBelowRows +
    _dBezelBelowPanel;

/// 순위표 [rows]줄이 재생 화면 높이 [height] 안에 다 들어가는 화면 폭(설계 폭 × 배율). 배율은 [_maxTowerScale]까지,
/// 폭은 [maxWidth]까지다. 깃발 배너가 뜨면 순위표가 이 폭 안에서 잠시 줄어 줄이 잘리지 않는다(순수 함수).
double broadcastTowerWidth({required double height, required double maxWidth, required int rows, required bool compact}) {
  final designWidth = compact ? kBroadcastCompactTowerDesignWidth : kBroadcastTowerDesignWidth;
  final scale = [_maxTowerScale, height / broadcastTowerDesignHeight(rows, banner: false), maxWidth / designWidth].reduce(math.min);
  return designWidth * math.max(0, scale);
}

/// 깃발 테두리 색이 번지는 방식: 없음, 테두리 전체(세이프티카·버추얼·적기), 왼쪽 위 모서리만(옐로·그린).
enum _EdgeFlag { none, full, corner }

/// 중계 화면 왼쪽 순위표(방송 타워, F1TV-HUD-Reworked 리더보드와 같은 모양).
/// 둥근 회색 틀 안 어두운 판: 머리(앱 이름 + 회색 `RACE`), 그러데이션 랩 띠(`LAP 16 /39`), 줄마다 기울인 순위 · 세로선 ·
/// 팀 로고 · 세 글자 이름 · 간격(리더는 `Leader`) · 컴파운드 색 글자. 피트면 간격 자리에 팀 색 `IN PIT`와 몸통 밖 `P` 칸,
/// 피니시면 몸통 밖 체커 칸, 리타이어면 흐린 `OUT`.
/// 카메라가 따라가는 차의 줄은 밝은 줄무늬 바탕에 팀 색 로고 칸 + 검은 성(간격·컴파운드는 숨긴다).
/// 깃발이 걸리면([flag]) 랩 띠 바로 아래에 배너(세이프티카·버추얼은 노랑 줄무늬, 옐로 플래그는 노랑 줄무늬 + 섹터 칸,
/// 적기는 빨강), 걷힌 직후([trackClear])는 초록 GREEN FLAG + TRACK CLEAR, 테두리도 그 색으로 바꾼다.
/// 설계 크기로 그려 받은 폭에 맞춰 키우거나 줄이고, 배너가 뜨면 [rowCapacity]줄이 높이 안에 들어가게 잠시 더 줄인다.
/// [compact](좁은 화면)면 간격 칸을 뺀다.
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
    this.rowCapacity,
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

  /// 높이에 맞출 줄 수(클립에서 가장 많은 줄). null이면 지금 줄 수.
  final int? rowCapacity;

  double get _bodyWidth => compact ? _dCompactBodyWidth : _dBodyWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) {
          final banner = _flagBanner(context);
          final designWidth = _bodyWidth + _dBadgeLaneWidth;
          final capacity = math.max(rowCapacity ?? standing.rows.length, standing.rows.length);
          final widthScale = box.maxWidth / designWidth;
          final heightScale = box.maxHeight.isFinite
              ? box.maxHeight / broadcastTowerDesignHeight(capacity, banner: banner != null)
              : widthScale;
          return TweenAnimationBuilder<double>(
            tween: Tween(end: math.max(0, math.min(widthScale, heightScale))),
            duration: _towerScaleDuration,
            curve: Curves.easeOut,
            builder: (context, scale, _) {
              final emptyHeight = broadcastTowerDesignHeight(0, banner: banner != null);
              final fit = scale <= 0 || !box.maxHeight.isFinite
                  ? standing.rows.length
                  : ((box.maxHeight / scale - emptyHeight) / _dRowHeight).floor();
              final rows = standing.rows.take(fit.clamp(0, standing.rows.length)).toList();
              final height = broadcastTowerDesignHeight(rows.length, banner: banner != null);
              return Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  key: const ValueKey('highlights-standings'),
                  width: designWidth * scale,
                  height: height * scale,
                  child: FittedBox(
                    fit: BoxFit.fill,
                    alignment: Alignment.topLeft,
                    child: _design(context, rows, banner, height),
                  ),
                ),
              );
            },
          );
        },
      );

  /// 설계 크기 그대로의 순위표.
  Widget _design(BuildContext context, List<HighlightStandingRow> rows, Widget? banner, double height) {
    final bodyWidth = _bodyWidth;
    final contentWidth = bodyWidth - _dContentLeft;
    const lapTop = _dPanelTop + _dHeaderHeight;
    const lapBottom = lapTop + _dLapHeight;
    final rowsTop = lapBottom + (banner == null ? 0 : _dBannerHeight) + _dRowsGap;
    final rowsBottom = rowsTop + rows.length * _dRowHeight;
    final panelBottom = rowsBottom + _dPanelBelowRows;
    return SizedBox(
      width: bodyWidth + _dBadgeLaneWidth,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            width: bodyWidth,
            height: height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(_dBezelRadius)),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.replayTowerBezelTop.withValues(alpha: _bezelOpacity),
                    AppColors.replayTowerBezelBottom.withValues(alpha: _bezelOpacity),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: _dPanelLeft,
            top: _dPanelTop,
            width: bodyWidth - _dPanelLeft,
            height: panelBottom - _dPanelTop,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.replayTowerBody.withValues(alpha: _towerPanelOpacity),
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(_dPanelRadius)),
              ),
            ),
          ),
          Positioned(
            left: _dContentLeft + _dPositionWidth,
            top: lapBottom,
            width: _dDividerWidth,
            height: rowsBottom - lapBottom,
            child: const ColoredBox(color: AppColors.replayTowerDivider),
          ),
          Positioned(
            left: _dBrandLeft,
            top: _dBrandTop,
            height: _dBrandHeight,
            child: Center(
              child: Text(
                _brandWordmark,
                style: _towerText(context, size: _dBrandSize, weight: FontWeight.w900),
              ),
            ),
          ),
          if (!compact)
            Positioned(
              left: _dSessionLeft,
              top: _dSessionTop,
              width: _dSessionWidth,
              height: _dSessionHeight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _sessionLabel,
                  style: _towerText(context, size: _dSessionSize, color: AppColors.replayTowerSession, weight: FontWeight.w900, italic: false),
                ),
              ),
            ),
          Positioned(left: _dContentLeft, top: lapTop, width: contentWidth, height: _dLapHeight, child: _lapBar(context)),
          if (banner != null)
            Positioned(left: _dContentLeft, top: lapBottom, width: contentWidth, height: _dBannerHeight, child: banner),
          for (var i = 0; i < rows.length; i++)
            Positioned(
              left: _dContentLeft,
              top: rowsTop + i * _dRowHeight,
              width: contentWidth + _dBadgeLaneWidth,
              height: _dRowHeight,
              child: _row(context, i, rows[i], contentWidth),
            ),
          Positioned(
            left: _dPanelLeft + _dEdgeLeft,
            top: _dPanelTop + _dEdgeTop,
            width: bodyWidth - _dPanelLeft - _dEdgeLeft,
            height: rowsBottom + _dEdgeBelowRows - _dPanelTop - _dEdgeTop,
            child: CustomPaint(painter: _TowerEdgePainter(_edgeFlag, _edgeFlagColor)),
          ),
        ],
      ),
    );
  }

  /// 깃발 테두리: 세이프티카·버추얼·적기는 테두리 전체, 옐로·그린은 왼쪽 위 모서리.
  _EdgeFlag get _edgeFlag => switch (flag?.kind) {
        RaceFlagKind.safetyCar || RaceFlagKind.virtualSafetyCar || RaceFlagKind.redFlag => _EdgeFlag.full,
        RaceFlagKind.yellowFlag => _EdgeFlag.corner,
        _ => trackClear && flag == null ? _EdgeFlag.corner : _EdgeFlag.none,
      };

  Color get _edgeFlagColor => switch (flag?.kind) {
        RaceFlagKind.redFlag => AppColors.replayFlagRed,
        null => AppColors.replayTowerFlagGreen,
        _ => AppColors.replayTowerFlagYellow,
      };

  /// 랩 띠 아래 깃발 배너. 띄울 것이 없으면 null.
  Widget? _flagBanner(BuildContext context) {
    final flag = this.flag;
    if (flag == null) {
      return trackClear
          ? _splitBanner(
              context,
              AppColors.replayTowerFlagGreen,
              AppColors.replayTowerFlagGreenStripe,
              _greenFlagLabel,
              Text(
                _trackClearLabel,
                maxLines: 1,
                style: _towerText(context, size: _dTrackClearSize, color: AppColors.replayTowerTrackClear, weight: FontWeight.w400, italic: false),
              ),
            )
          : null;
    }
    return switch (flag.kind) {
      RaceFlagKind.safetyCar => _stripedBanner(
          AppColors.replayTowerFlagYellow,
          AppColors.replayTowerFlagYellowStripe,
          [_flagText(context, _safetyLabel, _dSafetySize), _flagText(context, _carLabel, _dSafetySize)],
        ),
      RaceFlagKind.virtualSafetyCar => _stripedBanner(
          AppColors.replayTowerFlagYellow,
          AppColors.replayTowerFlagYellowStripe,
          [_flagText(context, _virtualLabel, _dVirtualSize), _flagText(context, _safetyCarLabel, _dVirtualSubSize)],
        ),
      RaceFlagKind.yellowFlag => _splitBanner(
          context,
          AppColors.replayTowerFlagYellow,
          AppColors.replayTowerFlagYellowStripe,
          _yellowFlagLabel,
          _sectorText(context, flag.sectors),
        ),
      RaceFlagKind.redFlag => SizedBox(
          key: const ValueKey('highlights-standings-flag'),
          height: _dBannerHeight,
          child: CustomPaint(
            painter: const _TowerStripePainter(AppColors.replayTowerFlagRed, AppColors.replayTowerFlagRedStripe),
            child: ColoredBox(
              color: AppColors.replayFlagRed.withValues(alpha: _redOverlayOpacity),
              child: Center(child: _flagText(context, _redFlagLabel, _dRedFlagSize, color: AppColors.replayHudText)),
            ),
          ),
        ),
      RaceFlagKind.unknown => null,
    };
  }

  /// 옐로 플래그 섹터 칸: `SECTOR 2`, 여럿이면 `SECTORS 1 · 3`(숫자는 크게), 모르면 빈 글자.
  Widget _sectorText(BuildContext context, List<int> sectors) {
    final (label, numbers) = switch (sectors.length) {
      0 => ('', ''),
      1 => (_sectorLabel, '${sectors.single}'),
      _ => (_sectorsLabel, sectors.join(_sectorSeparator)),
    };
    return Text.rich(
      TextSpan(children: [
        if (label.isNotEmpty)
          TextSpan(
            text: '$label ',
            style: _towerText(context, size: _dSectorLabelSize, color: AppColors.replayTowerSectorText, weight: FontWeight.w500, italic: false),
          ),
        TextSpan(
          text: numbers,
          style: _towerText(context, size: _dSectorNumberSize, color: AppColors.replayTowerSectorText, weight: FontWeight.w400, italic: false),
        ),
      ]),
      maxLines: 1,
    );
  }

  Widget _flagText(BuildContext context, String text, double size, {Color color = AppColors.replayTowerFocusInk}) =>
      Text(text, maxLines: 1, style: _towerText(context, size: size, color: color, weight: FontWeight.w800));

  /// 배너 전체가 사선 줄무늬이고 글자 줄들을 가운데에 쌓는다(세이프티카·버추얼).
  Widget _stripedBanner(Color base, Color stripe, List<Widget> lines) => SizedBox(
        key: const ValueKey('highlights-standings-flag'),
        height: _dBannerHeight,
        child: CustomPaint(
          painter: _TowerStripePainter(base, stripe),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(mainAxisSize: MainAxisSize.min, children: lines),
            ),
          ),
        ),
      );

  /// 위는 사선 줄무늬 + [title], 아래는 + 무늬 어두운 칸 + [detail](옐로 플래그 섹터, 그린 플래그 TRACK CLEAR).
  Widget _splitBanner(BuildContext context, Color base, Color stripe, String title, Widget detail) => SizedBox(
        key: const ValueKey('highlights-standings-flag'),
        height: _dBannerHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: _dBannerTopHeight,
              child: CustomPaint(
                painter: _TowerStripePainter(base, stripe),
                child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: _flagText(context, title, _dFlagTitleSize))),
              ),
            ),
            Expanded(
              child: CustomPaint(
                painter: const _BandPainter(),
                child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: detail)),
              ),
            ),
          ],
        ),
      );

  Widget _lapBar(BuildContext context) {
    final label = _towerText(context, size: _dLapLabelSize, color: AppColors.replayTowerPosition, weight: FontWeight.w400);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.replayTowerLapTop, AppColors.replayTowerLapBottom],
        ),
      ),
      child: Center(
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: 'LAP ', style: label),
            TextSpan(text: '${standing.lap}', style: _towerText(context, size: _dLapNumberSize, weight: FontWeight.w800)),
            if (totalLaps > 0)
              TextSpan(
                text: ' /$totalLaps',
                style: _towerText(context, size: _dLapTotalSize, color: AppColors.replayTowerPosition, weight: FontWeight.w400),
              ),
          ]),
          key: const ValueKey('highlights-standings-lap'),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, int index, HighlightStandingRow row, double contentWidth) {
    final focused = row.carIndex == focusCar;
    final name = nameOf(row.carIndex);
    final out = row.state == StandingState.out;
    final pit = row.state == StandingState.pit;
    final color = colorOf(row.carIndex);
    final tyre = kHighlightTyreNames[row.tyre];
    final timing = _timing(context, index, row);
    final badge = switch (row.state) {
      StandingState.pit => _badge(
          Text(_pitBadgeLabel, style: _towerText(context, size: _dBadgeTextSize, weight: FontWeight.w800)),
        ),
      StandingState.finished => _badge(
          const Padding(padding: EdgeInsets.all(_dCheckerInset), child: CustomPaint(painter: _BadgeCheckerPainter(), size: Size.infinite)),
        ),
      _ => null,
    };
    final nameLeft = focused ? _dFocusNameLeft : _dNameLeft;
    final nameRight = compact ? _dCompactTyreLeft : (focused ? contentWidth : _dNameLeft + _dNameWidth);
    return Stack(
      key: ValueKey('standing-row-${row.carIndex}'),
      clipBehavior: Clip.none,
      children: [
        if (focused) ...[
          Positioned(
            left: _dFocusLeft,
            top: 0,
            width: contentWidth - _dFocusLeft,
            height: _dRowHeight,
            child: const CustomPaint(
              painter: _TowerStripePainter(
                AppColors.replayTowerFocus,
                AppColors.replayTowerFocusStripe,
                gap: _dFocusStripeGap,
                width: _dFocusStripeWidth,
              ),
            ),
          ),
          Positioned(left: _dLogoLeft, top: 0, width: _dFocusLogoWidth, height: _dRowHeight, child: ColoredBox(color: color)),
        ],
        Positioned(
          left: 0,
          top: 0,
          width: _dPositionWidth,
          height: _dRowHeight,
          child: Center(
            child: Text(
              '${index + 1}',
              style: _towerText(
                context,
                size: focused ? _dPositionFocusSize : _dPositionSize,
                color: focused ? AppColors.replayTowerFocusInk : AppColors.replayTowerPosition,
                weight: focused ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
        ),
        Positioned(
          left: _dLogoLeft,
          top: 0,
          width: focused ? _dFocusLogoWidth : _dLogoWidth,
          height: _dRowHeight,
          child: Padding(
            padding: EdgeInsets.all(focused ? _dFocusLogoPadding : _dLogoPadding),
            child: _teamMark(row.carIndex, color, onTeamColor: focused),
          ),
        ),
        Positioned(
          left: nameLeft,
          top: 0,
          width: math.max(0, (compact && !focused ? _dNameLeft + _dCompactNameWidth : nameRight) - nameLeft),
          height: _dRowHeight,
          child: Opacity(
            opacity: out && !focused ? _outOpacity : 1,
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  focused ? name.toUpperCase() : standingAbbreviation(name),
                  style: focused
                      ? _towerText(context, size: _dFocusNameSize, color: AppColors.replayTowerFocusInk, weight: FontWeight.w800)
                      : _towerText(context, size: _dNameSize, weight: FontWeight.w700, italic: false),
                ),
              ),
            ),
          ),
        ),
        if (!focused && !compact && timing != null)
          Positioned(
            left: _dTimingLeft,
            top: 0,
            width: _dTimingWidth,
            height: _dRowHeight,
            child: Padding(
              padding: const EdgeInsets.only(right: _dTimingPadding),
              child: Align(
                alignment: pit || out ? Alignment.center : Alignment.centerRight,
                child: FittedBox(fit: BoxFit.scaleDown, child: timing),
              ),
            ),
          ),
        if (!focused && !out && tyre != null)
          Positioned(
            left: compact ? _dCompactTyreLeft : _dTyreLeft,
            top: 0,
            width: _dTyreWidth,
            height: _dRowHeight,
            child: Tooltip(
              message: tyre,
              child: Center(
                key: ValueKey('standing-tyre-${row.carIndex}'),
                child: Text(tyreLetterOf(tyre), style: _towerText(context, size: _dTyreSize, color: tyreColorOf(tyre), weight: FontWeight.w800)),
              ),
            ),
          ),
        if (badge != null)
          Positioned(
            left: contentWidth - _dBadgeOverlap,
            top: _dBadgeTop,
            width: _dBadgeWidth,
            height: _dBadgeHeight,
            child: badge,
          ),
      ],
    );
  }

  /// 간격 칸 글자: 피트면 팀 색 `IN PIT`(간격 대신), 리타이어면 흐린 `OUT`, 리더는 `Leader`, 나머지는 `+1.2`·`+1 LAP`. 없으면 null.
  Widget? _timing(BuildContext context, int index, HighlightStandingRow row) {
    if (row.state == StandingState.pit) {
      return Text(_inPitLabel, style: _towerText(context, size: _dPitSize, color: _tintOf(colorOf(row.carIndex)), weight: FontWeight.w800));
    }
    if (row.state == StandingState.out) {
      return Opacity(
        opacity: _outOpacity,
        child: Text(_outLabel, style: _towerText(context, size: _dOutSize, weight: FontWeight.w400)),
      );
    }
    final leader = index == 0;
    final text = standingGapText(row, leader: leader);
    return text.isEmpty
        ? null
        : Text(text, style: _towerText(context, size: leader ? _dLeaderSize : _dTimingSize, weight: FontWeight.w500));
  }

  /// 몸통 오른쪽 밖 칸(피트 P·체커): 흰 그러데이션 바탕, 오른쪽 모서리만 둥글게.
  Widget _badge(Widget child) => DecoratedBox(
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(_dBadgeRadius)),
          gradient: LinearGradient(colors: [AppColors.replayTowerBadgeTop, AppColors.replayTowerBadgeBottom]),
        ),
        child: Center(child: child),
      );

  /// 팀 표시: 로고가 있으면 로고(따라가는 차 줄은 팀 색 칸 위, 나머지는 어두운 판 위 — 어두운 단색 로고는 팀 색으로 칠한다),
  /// 로고가 없으면 팀 색 세로 띠.
  Widget _teamMark(int carIndex, Color color, {required bool onTeamColor}) {
    final bar = Center(
      child: Container(
        width: _dTeamBarWidth,
        height: _dTeamBarHeight,
        decoration: BoxDecoration(
          color: onTeamColor ? AppColors.replayTowerFocusInk : color,
          borderRadius: BorderRadius.circular(_dTeamBarWidth / 2),
        ),
      ),
    );
    final url = logoUrlOf?.call(carIndex);
    return url == null
        ? bar
        : _TowerLogo(key: ValueKey('standing-logo-$carIndex'), url: url, tint: onTeamColor ? null : _tintOf(color), fallback: bar);
  }

  /// 어두운 단색 로고를 칠할 색: 팀 색, 팀 색도 어두우면 흰색.
  static Color _tintOf(Color team) => team.computeLuminance() < _darkTintLuminance ? AppColors.replayHudText : team;
}

/// 순위표 팀 로고. [tint]가 있으면 로고 화소를 한 번 재서(주소별로 기억) 어두운 단색 로고(검정·남색 글자, 흰 바탕 포함)면
/// 흰 바탕은 투명하게 빼고 글자를 그 색으로 칠한다 — 어두운 판 위에서 로고가 묻히거나 흰 네모로 보이지 않게.
/// 읽는 중이면 빈 칸, 못 읽으면 [fallback].
class _TowerLogo extends StatefulWidget {
  const _TowerLogo({super.key, required this.url, required this.tint, required this.fallback});

  final String url;
  final Color? tint;
  final Widget fallback;

  @override
  State<_TowerLogo> createState() => _TowerLogoState();
}

class _TowerLogoState extends State<_TowerLogo> {
  /// 로고 주소 → 어두운 단색인지(잰 결과).
  static final Map<String, bool> _darkLogos = {};

  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
    _probe();
  }

  @override
  void didUpdateWidget(_TowerLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || (oldWidget.tint == null) != (widget.tint == null)) {
      _stop();
      _probe();
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _probe() {
    if (widget.tint == null || _darkLogos.containsKey(widget.url)) {
      return;
    }
    final url = widget.url;
    final listener = ImageStreamListener(
      (info, _) {
        final image = info.image.clone();
        info.dispose();
        _stop();
        _measure(url, image);
      },
      onError: (_, _) => _stop(),
    );
    _listener = listener;
    _stream = NetworkImage(url).resolve(ImageConfiguration.empty)..addListener(listener);
  }

  void _stop() {
    final listener = _listener;
    if (listener != null) {
      _stream?.removeListener(listener);
    }
    _stream = null;
    _listener = null;
  }

  Future<void> _measure(String url, ui.Image image) async {
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bytes == null) {
        return;
      }
      // 흰 바탕을 뺀 불투명 화소의 평균 밝기와 무채색 비율.
      var sum = 0.0;
      var count = 0;
      var mono = 0;
      for (var i = 0; i + 3 < bytes.lengthInBytes; i += 4 * _logoSampleStride) {
        if (bytes.getUint8(i + 3) < _opaqueAlpha) {
          continue;
        }
        final r = bytes.getUint8(i);
        final g = bytes.getUint8(i + 1);
        final b = bytes.getUint8(i + 2);
        final luminance = Color.fromARGB(0xFF, r, g, b).computeLuminance();
        if (luminance >= _logoWhiteLuminance) {
          continue;
        }
        sum += luminance;
        count++;
        if ([r, g, b].reduce(math.max) - [r, g, b].reduce(math.min) < _monoChroma) {
          mono++;
        }
      }
      _darkLogos[url] = count > 0 && sum / count < _darkLogoLuminance && mono / count >= _monoShare;
      if (mounted && widget.url == url) {
        setState(() {});
      }
    } on Object {
      // 밝기를 못 재면 칠하지 않고 그대로 그린다.
    } finally {
      image.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tint = widget.tint != null && (_darkLogos[widget.url] ?? false) ? widget.tint : null;
    final image = Image.network(
      widget.url,
      fit: BoxFit.contain,
      frameBuilder: (_, child, frame, wasSynchronouslyLoaded) =>
          frame == null && !wasSynchronouslyLoaded ? const SizedBox.shrink() : child,
      errorBuilder: (_, _, _) => widget.fallback,
    );
    return tint == null ? image : ColorFiltered(colorFilter: _knockOut(tint), child: image);
  }

  /// 밝을수록 투명하게(흰 바탕은 사라지고 어두운 글자는 남는다) 하면서 색은 [tint]로 바꾸는 색 행렬.
  static ColorFilter _knockOut(Color tint) => ColorFilter.matrix([
        0, 0, 0, 0, tint.r * _channelMax, //
        0, 0, 0, 0, tint.g * _channelMax, //
        0, 0, 0, 0, tint.b * _channelMax, //
        -_lumaRed, -_lumaGreen, -_lumaBlue, 1, 0,
      ]);
}

/// 판 안쪽 회색 테두리(오른쪽은 열린 둥근 사각형). 깃발이면 그 색을 덧칠한다 — 전체는 오른쪽 끝으로 갈수록 옅게,
/// 모서리는 왼쪽 위에서 [_dEdgeFlagReach]까지 번지게.
class _TowerEdgePainter extends CustomPainter {
  const _TowerEdgePainter(this.flag, this.color);

  final _EdgeFlag flag;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const half = _dEdgeWidth / 2;
    final right = size.width;
    final bottom = size.height - half;
    const radius = _dEdgeRadius - half;
    final path = Path()
      ..moveTo(right, half)
      ..lineTo(half + radius, half)
      ..arcToPoint(const Offset(half, half + radius), radius: const Radius.circular(radius), clockwise: false)
      ..lineTo(half, bottom - radius)
      ..arcToPoint(Offset(half + radius, bottom), radius: const Radius.circular(radius), clockwise: false)
      ..lineTo(right, bottom);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _dEdgeWidth;
    canvas.drawPath(path, stroke..color = AppColors.replayTowerBorder);
    if (flag == _EdgeFlag.none) {
      return;
    }
    final transparent = color.withValues(alpha: 0);
    final shader = flag == _EdgeFlag.full
        ? LinearGradient(colors: [color, color, transparent], stops: const [0, _edgeFlagSolidStop, 1])
            .createShader(Offset.zero & size)
        : RadialGradient(
            center: Alignment.topLeft,
            radius: 1,
            colors: [color, color, transparent],
            stops: const [0, _edgeFlagSolidStop, 1],
          ).createShader(Rect.fromCircle(center: Offset.zero, radius: _dEdgeFlagReach));
    canvas.drawPath(path, stroke..shader = shader);
  }

  @override
  bool shouldRepaint(_TowerEdgePainter oldDelegate) => oldDelegate.flag != flag || oldDelegate.color != color;
}

/// [base] 색 위에 왼쪽 아래에서 오른쪽 위로 가는 [stripe] 색 사선 줄무늬(깃발 배너·따라가는 차 줄).
class _TowerStripePainter extends CustomPainter {
  const _TowerStripePainter(this.base, this.stripe, {this.gap = _dBannerStripeGap, this.width = _dBannerStripeWidth});

  final Color base;
  final Color stripe;
  final double gap;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = base);
    final paint = Paint()
      ..color = stripe
      ..strokeWidth = width;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (var x = -size.height; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TowerStripePainter oldDelegate) =>
      oldDelegate.base != base || oldDelegate.stripe != stripe || oldDelegate.gap != gap || oldDelegate.width != width;
}

/// 깃발 배너 아래 칸: 어두운 바탕에 옅은 + 무늬 격자.
class _BandPainter extends CustomPainter {
  const _BandPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.replayTowerBandBody);
    final grid = Paint()
      ..color = AppColors.replayTowerBandGrid
      ..strokeWidth = _dBandGridStroke;
    for (var y = _dBandGridStep / 2; y < size.height; y += _dBandGridStep) {
      for (var x = _dBandGridStep / 2; x < size.width; x += _dBandGridStep) {
        canvas
          ..drawLine(Offset(x - _dBandGridArm, y), Offset(x + _dBandGridArm, y), grid)
          ..drawLine(Offset(x, y - _dBandGridArm), Offset(x, y + _dBandGridArm), grid);
      }
    }
  }

  @override
  bool shouldRepaint(_BandPainter oldDelegate) => false;
}

/// 피니시 칸 체커 무늬(흰·검정 칸).
class _BadgeCheckerPainter extends CustomPainter {
  const _BadgeCheckerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / _checkerCells;
    final rows = (size.height / cell).floor();
    final top = (size.height - rows * cell) / 2;
    final white = Paint()..color = AppColors.replayHudText;
    final black = Paint()..color = AppColors.replayTowerFocusInk;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < _checkerCells; c++) {
        canvas.drawRect(Rect.fromLTWH(c * cell, top + r * cell, cell, cell), (r + c).isEven ? white : black);
      }
    }
  }

  @override
  bool shouldRepaint(_BadgeCheckerPainter oldDelegate) => false;
}


/// 하단 오른쪽 텔레메트리 판 치수(디자인 크기 — 재생 화면에 맞춰 줄어든다).
const double kBroadcastTelemetryWidth = 230;
const double _telemetryRadius = 8;
const EdgeInsets _telemetryPadding = EdgeInsets.fromLTRB(12, 10, 12, 8);
const double _telemetryNameSize = 13;
const double _telemetryBarWidth = 3;
const double _telemetryBarHeight = 14;
const double _telemetryNameGap = 6;

/// 하단 오른쪽 텔레메트리: 카메라가 따라가는 차의 팀 색 띠·이름 아래, 텔레메트리 고스트 재생과 같은 다이얼
/// (바깥 고리 속도, 안쪽 고리 스로틀·브레이크, 가운데 속도, 아래 기어와 그 위 ERS 배터리 게이지 — 하이라이트 표본에는 RPM이 없어 뺀다).
class BroadcastTelemetry extends StatelessWidget {
  const BroadcastTelemetry({super.key, required this.name, required this.color, required this.frame, required this.units});

  final String name;
  final Color color;
  final ReplayFrame frame;
  final UnitSystem units;

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('highlights-telemetry'),
        width: kBroadcastTelemetryWidth,
        padding: _telemetryPadding,
        decoration: BoxDecoration(
          color: AppColors.replayDashPanel.withValues(alpha: _panelOpacity),
          borderRadius: BorderRadius.circular(_telemetryRadius),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(width: _telemetryBarWidth, height: _telemetryBarHeight, color: color),
                const SizedBox(width: _telemetryNameGap),
                Expanded(
                  child: Text(
                    name.toUpperCase(),
                    key: const ValueKey('highlights-telemetry-name'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _broadcastText(context, size: _telemetryNameSize),
                  ),
                ),
              ],
            ),
            ReplayDial(keyName: 'highlights-telemetry', frame: frame, units: units, showRpm: false, showBattery: true),
          ],
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
