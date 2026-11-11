import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/domain/user_preferences.dart';
import '../../lap_detail/domain/ghost_replay.dart';
import '../../lap_detail/domain/telemetry_channels.dart';
import '../../lap_detail/domain/telemetry_math.dart';
import '../domain/broadcast_graphics.dart';
import '../domain/race_highlights.dart';
import 'highlights_broadcast_overlay.dart';

// 하이라이트 중계 그래픽(F1TV-HUD-Reworked 오버레이 모양): 속도계 · 드라이버 이름 자막 · 턴 표시 · 레이스 컨트롤 메시지.
// 참고한 오버레이의 픽셀 단위(설계 크기) 그대로 그리고, 화면에서는 부모가 통째로 키우거나 줄인다.
// 이미지·글꼴은 가져오지 않고 모양만 직접 그린다(글자는 앱 글꼴).

const List<FontFeature> _tabular = [FontFeature.tabularFigures()];
const double _degToRad = math.pi / 180;
const double _percentMax = 100;

/// 중계 그래픽 글자(설계 단위 크기): 숫자는 고정폭, 줄 높이 1.
TextStyle _f1Text(
  BuildContext context, {
  required double size,
  Color color = AppColors.replayHudText,
  FontWeight weight = FontWeight.w700,
  bool italic = false,
  double letterSpacing = 0,
  List<Shadow>? shadows,
}) =>
    DefaultTextStyle.of(context).style.copyWith(
          color: color,
          fontSize: size,
          fontWeight: weight,
          fontStyle: italic ? FontStyle.italic : FontStyle.normal,
          letterSpacing: letterSpacing,
          fontFeatures: _tabular,
          decoration: TextDecoration.none,
          height: 1,
          shadows: shadows,
        );

/// 팀 색이 어두운 판 위에서 묻히면(검정에 가까우면) 흰색으로 바꾼다.
const double _darkTeamLuminance = 0.15;
Color _readable(Color team) => team.computeLuminance() < _darkTeamLuminance ? AppColors.replayHudText : team;

// -- 속도계 ----------------------------------------------------------------------------------

/// 속도계 설계 크기(정사각형 한 변).
const double kBroadcastSpeedometerSize = 500;
const double _sCenter = kBroadcastSpeedometerSize / 2;

/// 원판 반지름·불투명도, 속도 고리·페달 고리의 가운데 반지름과 굵기.
const double _sDiscRadius = 240;
const double _sDiscOpacity = 0.84;
const double _sSpeedRadius = 219;
const double _sPedalRadius = 171;
const double _sBandWidth = 42;

/// 고리 각도(도, 3시 방향이 0°, 시계 방향이 +): 속도·스로틀은 왼쪽 아래에서 시작해 속도는 296°, 스로틀은 193°를 돌고,
/// 브레이크는 오른쪽 아래에서 거꾸로 102° 올라간다. THROTTLE·BRAKE 글자가 놓이는 가운데 각도.
const double _sStartDeg = -238;
const double _sSpeedSweepDeg = 296;
const double _sThrottleSweepDeg = 193;
const double _sBrakeStartDeg = 58;
const double _sBrakeSweepDeg = -102;
const double _sThrottleLabelDeg = -176;
const double _sBrakeLabelDeg = 2;
const double _sQuarterTurnDeg = 90;

/// 속도 눈금: 최고 값·간격(km/h, mph).
const int _sMetricMax = 360;
const int _sMetricStep = 60;
const int _sImperialMax = 225;
const int _sImperialStep = 45;

/// 글자 크기: 눈금, 고리 글자(THROTTLE·BRAKE)와 그 자간, 속도, 단위·RPM 라벨, RPM, GEAR 라벨, 기어, 표시 칸.
const double _sTickSize = 21;
const double _sArcLabelSize = 23;
const double _sArcLabelSpacing = 2.5;
const double _sSpeedSize = 92;
const double _sLabelSize = 23;
const double _sRpmSize = 46;
const double _sGearLabelSize = 23;
const double _sGearSize = 52;
const double _sIndicatorTextSize = 25;

/// 고리 위 글자(눈금 · THROTTLE · BRAKE)가 밝은 고리 색 위에서도 읽히게 까는 어두운 그림자(겹쳐서 진하게).
const double _sArcShadowBlur = 3;
const List<Shadow> _sArcShadow = [
  Shadow(color: AppColors.replayF1tvRing, blurRadius: _sArcShadowBlur),
  Shadow(color: AppColors.replayF1tvRing, blurRadius: _sArcShadowBlur),
];

/// 가운데 값 칸(속도 · 단위 · RPM · 배터리 · DRS/OT 표시)과 그 안 줄 사이 간격, 아래 기어 줄.
const double _sValueLeft = 140;
const double _sValueTop = 110;
const double _sValueWidth = 220;
const double _sValueHeight = 304;
const double _sValueGap = 8;
const double _sGearLeft = 150;
const double _sGearTop = 418;
const double _sGearWidth = 200;
const double _sGearHeight = 70;
const double _sGearGap = 10;

/// DRS·오버테이크 표시 칸: 크기, 모서리, 쓸 수 있을 때 테두리 굵기.
const double _sIndicatorWidth = 78;
const double _sIndicatorHeight = 45;
const double _sIndicatorRadius = 8;
const double _sIndicatorBorder = 3;

/// 배터리 게이지: 몸통 크기·모서리·테두리·안쪽 여백, 단자 크기, 글자 크기·간격·칸 폭.
const double _sBatteryWidth = 54;
const double _sBatteryHeight = 24;
const double _sBatteryRadius = 4;
const double _sBatteryBorder = 2.5;
const double _sBatteryInset = 2.5;
const double _sBatteryCapWidth = 4;
const double _sBatteryCapHeight = 11;
const double _sBatteryTextSize = 23;
const double _sBatteryTextGap = 8;
const double _sBatteryTextWidth = 58;

const String _throttleLabel = 'THROTTLE';
const String _brakeLabel = 'BRAKE';
const String _rpmLabel = 'RPM';
const String _gearLabel = 'GEAR';
const String _drsLabel = 'DRS';
const String _overtakeLabel = 'OT';

/// 중계 속도계(F1TV 속도계 모양, 설계 크기 [kBroadcastSpeedometerSize] 정사각형): 검은 원판 위 바깥 파란 속도 고리(눈금 숫자),
/// 안쪽 라임 스로틀 고리와 빨간 브레이크 고리(고리를 따라 THROTTLE · BRAKE 글자), 가운데 속도 · 단위 ·
/// ([showRpm]이면) RPM, (잔량을 알면) 파란 배터리 게이지와 %, DRS/OT 표시 칸, 아래 `GEAR 7`.
/// 표시 칸: 꺼짐(어두운 칸 · 회색 글자), 오버테이크 쓸 수 있음(청록 테두리), DRS 열림(초록)·오버테이크 쓰는 중(청록)은 칸을 채운다.
/// [overtakeRegs](2026 규정 차)면 꺼졌을 때 글자가 `OT`, 아니면 `DRS`. DRS·오버테이크를 모르는 기록(랩 트레이스)은 [showBoost]를 끈다.
/// 키는 `[keyName]`(전체, [rootKey]를 주면 그 키)·`-speed`·`-rpm`·`-battery`·`-battery-text`·`-boost`·`-gear`.
class BroadcastSpeedometer extends StatelessWidget {
  const BroadcastSpeedometer({
    super.key,
    required this.frame,
    required this.units,
    this.boost = HighlightBoost.none,
    this.overtakeRegs = false,
    this.showRpm = true,
    this.showBoost = true,
    this.keyName = 'highlights-telemetry',
    this.rootKey,
  });

  final ReplayFrame frame;
  final UnitSystem units;
  final HighlightBoost boost;
  final bool overtakeRegs;

  /// RPM 줄을 보일지(옛 표본에는 RPM이 없다).
  final bool showRpm;

  /// DRS·오버테이크 표시 칸을 보일지.
  final bool showBoost;

  /// 안쪽 값 위젯 키의 앞 글자, 전체 상자의 키(null이면 [keyName]).
  final String keyName;
  final Key? rootKey;

  @override
  Widget build(BuildContext context) {
    final imperial = units == UnitSystem.imperial;
    final speed = imperial ? kphToMph(frame.speedKph) : frame.speedKph;
    final maxSpeed = imperial ? _sImperialMax : _sMetricMax;
    final battery = frame.batteryPercent;
    return SizedBox(
      key: rootKey ?? ValueKey(keyName),
      width: kBroadcastSpeedometerSize,
      height: kBroadcastSpeedometerSize,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _SpeedometerPainter(
                speed: (speed / maxSpeed).clamp(0.0, 1.0),
                throttle: (frame.throttle / _percentMax).clamp(0.0, 1.0),
                brake: (frame.brake / _percentMax).clamp(0.0, 1.0),
                maxSpeed: maxSpeed,
                tickStep: imperial ? _sImperialStep : _sMetricStep,
                tickStyle: _f1Text(context, size: _sTickSize, weight: FontWeight.w600, shadows: _sArcShadow),
                labelStyle: _f1Text(context, size: _sArcLabelSize, weight: FontWeight.w600, shadows: _sArcShadow),
              ),
            ),
          ),
          Positioned(
            left: _sValueLeft,
            top: _sValueTop,
            width: _sValueWidth,
            height: _sValueHeight,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 숫자는 한 줄 — 글꼴이 넓어 칸을 넘으면 줄여 맞춘다.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${speed.round()}',
                    key: ValueKey('$keyName-speed'),
                    style: _f1Text(context, size: _sSpeedSize),
                  ),
                ),
                Text(imperial ? 'MPH' : 'KMH', style: _f1Text(context, size: _sLabelSize, weight: FontWeight.w800)),
                const SizedBox(height: _sValueGap),
                if (showRpm) ...[
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${frame.rpm}',
                      key: ValueKey('$keyName-rpm'),
                      style: _f1Text(context, size: _sRpmSize),
                    ),
                  ),
                  Text(_rpmLabel, style: _f1Text(context, size: _sLabelSize, weight: FontWeight.w800)),
                  const SizedBox(height: _sValueGap),
                ],
                if (battery != null) ...[
                  _SpeedometerBattery(
                    key: ValueKey('$keyName-battery'),
                    textKey: ValueKey('$keyName-battery-text'),
                    percent: battery,
                  ),
                  if (showBoost) const SizedBox(height: _sValueGap),
                ],
                if (showBoost) _BoostIndicator(boxKey: ValueKey('$keyName-boost'), boost: boost, overtakeRegs: overtakeRegs),
              ],
            ),
          ),
          Positioned(
            left: _sGearLeft,
            top: _sGearTop,
            width: _sGearWidth,
            height: _sGearHeight,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(_gearLabel, style: _f1Text(context, size: _sGearLabelSize, weight: FontWeight.w500)),
                const SizedBox(width: _sGearGap),
                Text(
                  gearLabel(frame.gear),
                  key: ValueKey('$keyName-gear'),
                  style: _f1Text(context, size: _sGearSize),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 속도계 그림: 원판, 빈 고리, 채운 고리(속도 · 스로틀 · 브레이크), 고리를 따라 도는 눈금 숫자와 THROTTLE · BRAKE 글자.
class _SpeedometerPainter extends CustomPainter {
  const _SpeedometerPainter({
    required this.speed,
    required this.throttle,
    required this.brake,
    required this.maxSpeed,
    required this.tickStep,
    required this.tickStyle,
    required this.labelStyle,
  });

  /// 0~1.
  final double speed;
  final double throttle;
  final double brake;
  final int maxSpeed;
  final int tickStep;
  final TextStyle tickStyle;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    const center = Offset(_sCenter, _sCenter);
    canvas.drawCircle(center, _sDiscRadius, Paint()..color = AppColors.replayF1tvDisc.withValues(alpha: _sDiscOpacity));

    void arc(double radius, double startDeg, double sweepDeg, Color color) => canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          startDeg * _degToRad,
          sweepDeg * _degToRad,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = _sBandWidth
            ..color = color,
        );

    arc(_sSpeedRadius, _sStartDeg, _sSpeedSweepDeg, AppColors.replayF1tvRing);
    arc(_sPedalRadius, _sStartDeg, _sSpeedSweepDeg, AppColors.replayF1tvRing);
    if (speed > 0) {
      arc(_sSpeedRadius, _sStartDeg, _sSpeedSweepDeg * speed, AppColors.replayF1tvSpeed);
    }
    if (throttle > 0) {
      arc(_sPedalRadius, _sStartDeg, _sThrottleSweepDeg * throttle, AppColors.replayF1tvThrottle);
    }
    if (brake > 0) {
      arc(_sPedalRadius, _sBrakeStartDeg, _sBrakeSweepDeg * brake, AppColors.replayF1tvBrake);
    }

    for (var value = 0; value <= maxSpeed; value += tickStep) {
      _arcText(canvas, '$value', _sSpeedRadius, _sStartDeg + _sSpeedSweepDeg * value / maxSpeed, tickStyle, spacing: 0);
    }
    _arcText(canvas, _throttleLabel, _sPedalRadius, _sThrottleLabelDeg, labelStyle, spacing: _sArcLabelSpacing);
    _arcText(canvas, _brakeLabel, _sPedalRadius, _sBrakeLabelDeg, labelStyle, spacing: _sArcLabelSpacing);
  }

  /// [text]를 반지름 [radius]의 원을 따라 시계 방향으로(글자 위쪽이 바깥) 쓴다. 글 가운데가 [centerDeg]에 온다.
  void _arcText(Canvas canvas, String text, double radius, double centerDeg, TextStyle style, {required double spacing}) {
    final glyphs = [
      for (final char in text.characters)
        TextPainter(text: TextSpan(text: char, style: style), textDirection: TextDirection.ltr)..layout(),
    ];
    final total = glyphs.fold(0.0, (sum, g) => sum + g.width) + spacing * (glyphs.length - 1);
    var along = -total / 2;
    for (final glyph in glyphs) {
      final angle = centerDeg * _degToRad + (along + glyph.width / 2) / radius;
      canvas
        ..save()
        ..translate(_sCenter, _sCenter)
        ..rotate(angle + _sQuarterTurnDeg * _degToRad)
        ..translate(0, -radius);
      glyph.paint(canvas, Offset(-glyph.width / 2, -glyph.height / 2));
      canvas.restore();
      along += glyph.width + spacing;
      glyph.dispose();
    }
  }

  @override
  bool shouldRepaint(_SpeedometerPainter oldDelegate) =>
      oldDelegate.speed != speed ||
      oldDelegate.throttle != throttle ||
      oldDelegate.brake != brake ||
      oldDelegate.maxSpeed != maxSpeed ||
      oldDelegate.tickStep != tickStep ||
      oldDelegate.tickStyle != tickStyle ||
      oldDelegate.labelStyle != labelStyle;
}

/// DRS·오버테이크 표시 칸.
class _BoostIndicator extends StatelessWidget {
  const _BoostIndicator({required this.boxKey, required this.boost, required this.overtakeRegs});

  /// 표시 칸 상자의 키.
  final Key boxKey;

  final HighlightBoost boost;
  final bool overtakeRegs;

  @override
  Widget build(BuildContext context) {
    final overtake = switch (boost) {
      HighlightBoost.overtakeAvailable || HighlightBoost.overtakeActive => true,
      HighlightBoost.drs => false,
      HighlightBoost.none => overtakeRegs,
    };
    final color = overtake ? AppColors.replayF1tvOvertake : AppColors.replayF1tvDrs;
    final active = boost == HighlightBoost.drs || boost == HighlightBoost.overtakeActive;
    final available = boost == HighlightBoost.overtakeAvailable;
    return Container(
      key: boxKey,
      width: _sIndicatorWidth,
      height: _sIndicatorHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? color : AppColors.replayF1tvIndicator,
        borderRadius: BorderRadius.circular(_sIndicatorRadius),
        border: available ? Border.all(color: color, width: _sIndicatorBorder) : null,
      ),
      child: Text(
        overtake ? _overtakeLabel : _drsLabel,
        style: _f1Text(
          context,
          size: _sIndicatorTextSize,
          weight: FontWeight.w800,
          color: active || available ? AppColors.replayHudText : AppColors.replayF1tvIndicatorOff,
        ),
      ),
    );
  }
}

/// 속도계 배터리 게이지: 파란 배터리 모양(잔량만큼 채움) + `62%`.
class _SpeedometerBattery extends StatelessWidget {
  const _SpeedometerBattery({super.key, required this.percent, this.textKey});

  final double percent;
  final Key? textKey;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: _sBatteryWidth,
            height: _sBatteryHeight,
            padding: const EdgeInsets.all(_sBatteryInset),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_sBatteryRadius),
              border: Border.all(color: AppColors.replayF1tvBattery, width: _sBatteryBorder),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: (percent / _percentMax).clamp(0.0, 1.0),
              child: const ColoredBox(color: AppColors.replayF1tvBattery),
            ),
          ),
          Container(width: _sBatteryCapWidth, height: _sBatteryCapHeight, color: AppColors.replayF1tvBattery),
          const SizedBox(width: _sBatteryTextGap),
          SizedBox(
            width: _sBatteryTextWidth,
            child: Text(
              '${percent.round()}%',
              key: textKey,
              style: _f1Text(context, size: _sBatteryTextSize, color: AppColors.replayF1tvBattery),
            ),
          ),
        ],
      );
}

// -- 드라이버 이름 자막 ------------------------------------------------------------------------

/// 자막 설계 높이와, 오른쪽 칸 종류별 설계 폭(차 번호 · 번호 없음 · 레이스 스토리 · 우승 · 추격).
const double kBroadcastDriverNameHeight = 118;
const double kBroadcastDriverNameMaxWidth = 905;
const double _nNumberWidth = 530;
const double _nPlainWidth = 410;
const double _nStoryWidth = 830;
const double _nWinnerWidth = 850;

/// 판(어두운 바탕) 높이·불투명도, 팀 색 줄(위치·굵기), 아래 사선 띠(위치·높이·줄 간격·굵기·불투명도).
const double _nPanelHeight = 103;
const double _nPanelOpacity = 0.94;
const double _nAccentTop = 95;
const double _nAccentHeight = 3;
const double _nStrokeTop = 103;
const double _nStrokeHeight = 15;
const double _nStrokeGap = 4;
const double _nStrokeLine = 1.25;
const double _nStrokeBaseOpacity = 0.1;
const double _nStrokeOpacity = 0.5;

/// 순위 칸(폭·높이·바탕 불투명도·오른쪽 구분선 굵기)과 순위 글자.
const double _nPositionWidth = 85;
const double _nContentHeight = 95;
const double _nPositionOpacity = 0.65;
const double _nDividerWidth = 2;
const double _nPositionSize = 35;

/// 이름: 윗줄 이름, 아랫줄 성(이름을 모르면 성만 가운데에 크게), 그 아래 팀 로고 + 팀 이름.
const double _nNameLeft = 95;
const double _nFirstTop = 2;
const double _nFirstHeight = 35;
const double _nFirstSize = 27;
const double _nLastTop = 31;
const double _nLastHeight = 35;
const double _nLastWidth = 300;
const double _nLastSize = 34;
const double _nSoloLastTop = 12;
const double _nSoloLastHeight = 46;
const double _nSoloLastSize = 42;
const double _nLogoLeft = 85;
const double _nLogoTop = 60;
const double _nLogoWidth = 45;
const double _nLogoHeight = 40;
const double _nLogoPadding = 5;
const double _nTeamBarWidth = 4;
const double _nTeamBarHeight = 18;
const double _nTeamLeft = 130;
const double _nTeamTop = 61;
const double _nTeamWidth = 265;
const double _nTeamHeight = 38;
const double _nTeamSize = 17;
const double _nTeamSpacing = 0.6;

/// 오른쪽 칸 시작(구분선·그 높이)과 차 번호: 번호 뒤 팀 색 번짐(칸 위치 · 크기, 가운데 불투명도, 짧은 변 대비 반지름), 번호 글자.
const double _nDetailLeft = 400;
const double _nSeparatorHeight = 94;
const double _nGlowLeft = 400;
const double _nGlowWidth = 130;
const double _nGlowOpacity = 0.45;
const double _nGlowRadius = 0.8;
const double _nNumberLeft = 420;
const double _nNumberTop = 5;
const double _nNumberBoxWidth = 100;
const double _nNumberBoxHeight = 85;
const double _nNumberSize = 60;
const double _nNumberOpacity = 0.85;
const double _nNumberShadowBlur = 3;
const double _nNumberShadowOffset = 1.4;

/// 추격(`CHASING NORRIS` / `FOR 8TH`): 칸 폭, 두 줄 위치·높이, 글자 크기, 낱말 사이 간격, 앞차 이름 최대 폭.
const double _nChasingWidth = 505;
const double _nChasingLine1Top = 8;
const double _nChasingLine2Top = 50;
const double _nChasingLineHeight = 40;
const double _nChasingWordSize = 25;
const double _nChasingNameSize = 35;
const double _nChasingGap = 10;
const double _nChasingNameMaxWidth = 350;

/// 레이스 스토리: 칸 폭, 제목(위치 · 높이 · 글자), 두 칸(출발 · 지금)의 위치·폭·높이, 라벨 폭·글자, 값 글자(두 자리면 작게)·접미사,
/// 칸 테두리 불투명도, 값 오른쪽 여백.
const double _nStoryBoxWidth = 430;
const double _nStoryLabelLeft = 15;
const double _nStoryLabelHeight = 40;
const double _nStoryLabelSize = 22;
const double _nStoryRowTop = 40;
const double _nStoryRowHeight = 55;
const double _nStoryStartedLeft = 2;
const double _nStoryStartedWidth = 223;
const double _nStoryNowLeft = 225;
const double _nStoryNowWidth = 205;
const double _nStoryCaptionWidth = 110;
const double _nStoryCaptionSize = 17;
const double _nStoryValueSize = 40;
const double _nStoryValueSmallSize = 35;
const double _nStorySuffixSize = 25;
const double _nStoryBorderOpacity = 0.25;
const double _nStoryValuePadding = 8;
const int _twoDigits = 10;

/// 우승(`RACE` + 팀 색 `WINNER`): 두 낱말의 위치·폭·높이·글자.
const double _nWinnerRaceLeft = 420;
const double _nWinnerRaceWidth = 170;
const double _nWinnerWordLeft = 590;
const double _nWinnerWordWidth = 245;
const double _nWinnerTop = 10;
const double _nWinnerHeight = 80;
const double _nWinnerSize = 50;

const String _chasingLabel = 'CHASING';
const String _forLabel = 'FOR';
const String _storyLabel = 'RACE STORY';
const String _startedLabel = 'STARTED:';
const String _nowLabel = 'NOW:';
const String _finishedLabel = 'FINISHED:';
const String _raceLabel = 'RACE';
const String _winnerLabel = 'WINNER';

/// 자막 오른쪽 칸 종류의 설계 폭(순수 함수). 차 번호를 모르면 번호 칸 없이 이름 칸에서 끝낸다.
double broadcastDriverNameWidth(LowerThirdDetail detail, {required bool hasNumber}) => switch (detail) {
      LowerThirdNumber() => hasNumber ? _nNumberWidth : _nPlainWidth,
      LowerThirdChasing() => kBroadcastDriverNameMaxWidth,
      LowerThirdStory() => _nStoryWidth,
      LowerThirdWinner() => _nWinnerWidth,
    };

/// 중계 드라이버 이름 자막(F1TV Driver Name 오버레이 모양, 설계 높이 [kBroadcastDriverNameHeight]).
/// 어두운 판 왼쪽에 순위 칸, 이름(윗줄 이름 · 아랫줄 굵은 성), 팀 로고 + 팀 이름, 아래 팀 색 줄과 사선 띠.
/// 오른쪽 칸([detail]): 차 번호(팀 색 번짐 위 큰 숫자), `CHASING NORRIS / FOR 8TH`, `RACE STORY — STARTED · NOW`, `RACE WINNER`.
class BroadcastDriverName extends StatelessWidget {
  const BroadcastDriverName({
    super.key,
    required this.name,
    required this.teamColor,
    required this.detail,
    this.position,
    this.teamName,
    this.logoUrl,
    this.raceNumber,
    this.otherName,
    this.otherColor,
  });

  /// 차 이름(`VERSTAPPEN`·`Max VERSTAPPEN`).
  final String name;
  final Color teamColor;
  final LowerThirdDetail detail;

  /// 지금 순위(모르면 순위 칸을 비운다).
  final int? position;
  final String? teamName;
  final String? logoUrl;
  final int? raceNumber;

  /// 추격 칸의 앞차 이름·팀 색.
  final String? otherName;
  final Color? otherColor;

  @override
  Widget build(BuildContext context) {
    final names = broadcastDriverName(name);
    final first = names.first;
    final number = raceNumber;
    final width = broadcastDriverNameWidth(detail, hasNumber: number != null);
    final separated = detail is! LowerThirdNumber;
    return SizedBox(
      key: const ValueKey('highlights-driver-name'),
      width: width,
      height: kBroadcastDriverNameHeight,
      child: ClipRect(
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              width: width,
              height: _nPanelHeight,
              child: ColoredBox(color: AppColors.replayF1tvPanel.withValues(alpha: _nPanelOpacity)),
            ),
            Positioned(left: 0, top: _nStrokeTop, width: width, child: const BroadcastHatchStrip()),
            if (detail is LowerThirdNumber && number != null) ...[
              Positioned(
                left: _nGlowLeft,
                top: 0,
                width: _nGlowWidth,
                height: _nContentHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      radius: _nGlowRadius,
                      colors: [teamColor.withValues(alpha: _nGlowOpacity), teamColor.withValues(alpha: 0)],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: _nNumberLeft,
                top: _nNumberTop,
                width: _nNumberBoxWidth,
                height: _nNumberBoxHeight,
                child: Opacity(
                  opacity: _nNumberOpacity,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '$number',
                      key: const ValueKey('highlights-driver-number'),
                      style: _f1Text(
                        context,
                        size: _nNumberSize,
                        color: AppColors.replayF1tvName,
                        weight: FontWeight.w500,
                        italic: true,
                        shadows: const [
                          Shadow(
                            color: AppColors.replayF1tvRing,
                            offset: Offset(_nNumberShadowOffset, _nNumberShadowOffset),
                            blurRadius: _nNumberShadowBlur,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
            Positioned(left: 0, top: _nAccentTop, width: width, height: _nAccentHeight, child: ColoredBox(color: teamColor)),
            Positioned(
              left: 0,
              top: 0,
              width: _nPositionWidth,
              height: _nContentHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.replayF1tvPanel.withValues(alpha: _nPositionOpacity),
                  border: const Border(right: BorderSide(color: AppColors.replayF1tvDivider, width: _nDividerWidth)),
                ),
                child: Center(
                  child: Text(
                    position == null ? '' : '$position',
                    key: const ValueKey('highlights-driver-position'),
                    style: _f1Text(context, size: _nPositionSize, color: AppColors.replayF1tvSilver, weight: FontWeight.w800, italic: true),
                  ),
                ),
              ),
            ),
            if (first != null)
              Positioned(
                left: _nNameLeft,
                top: _nFirstTop,
                width: _nLastWidth,
                height: _nFirstHeight,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    first,
                    key: const ValueKey('highlights-driver-first'),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: _f1Text(context, size: _nFirstSize, color: AppColors.replayF1tvName, weight: FontWeight.w400, italic: true),
                  ),
                ),
              ),
            Positioned(
              left: _nNameLeft,
              top: first == null ? _nSoloLastTop : _nLastTop,
              width: _nLastWidth,
              height: first == null ? _nSoloLastHeight : _nLastHeight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  names.last,
                  key: const ValueKey('highlights-driver-last'),
                  style: _f1Text(
                    context,
                    size: first == null ? _nSoloLastSize : _nLastSize,
                    color: AppColors.replayF1tvName,
                    weight: FontWeight.w800,
                    italic: true,
                  ),
                ),
              ),
            ),
            Positioned(
              left: _nLogoLeft,
              top: _nLogoTop,
              width: _nLogoWidth,
              height: _nLogoHeight,
              child: Padding(padding: const EdgeInsets.all(_nLogoPadding), child: _teamMark()),
            ),
            if (teamName != null)
              Positioned(
                left: _nTeamLeft,
                top: _nTeamTop,
                width: _nTeamWidth,
                height: _nTeamHeight,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    teamName!.toUpperCase(),
                    key: const ValueKey('highlights-driver-team'),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: _f1Text(
                      context,
                      size: _nTeamSize,
                      color: AppColors.replayF1tvTeam,
                      weight: FontWeight.w500,
                      letterSpacing: _nTeamSpacing,
                    ),
                  ),
                ),
              ),
            if (separated)
              const Positioned(
                left: _nDetailLeft,
                top: 0,
                width: _nDividerWidth,
                height: _nSeparatorHeight,
                child: ColoredBox(color: AppColors.replayF1tvDivider),
              ),
            ...switch (detail) {
              LowerThirdNumber() => const <Widget>[],
              final LowerThirdChasing chasing => <Widget>[_chasing(context, chasing)],
              final LowerThirdStory story => <Widget>[_story(context, story)],
              LowerThirdWinner() => _winner(context),
            },
          ],
        ),
      ),
    );
  }

  /// 팀 표시: 로고가 있으면 로고(어두운 단색 로고는 팀 색으로 칠한다), 없으면 팀 색 세로 띠.
  Widget _teamMark() {
    final bar = Center(
      child: Container(
        width: _nTeamBarWidth,
        height: _nTeamBarHeight,
        decoration: BoxDecoration(color: teamColor, borderRadius: BorderRadius.circular(_nTeamBarWidth / 2)),
      ),
    );
    final url = logoUrl;
    return url == null ? bar : BroadcastTeamLogo(url: url, tint: _readable(teamColor), fallback: bar);
  }

  /// `CHASING NORRIS`(앞차 이름은 그 팀 색) 아래 `FOR 8TH`.
  Widget _chasing(BuildContext context, LowerThirdChasing chasing) {
    final word = _f1Text(context, size: _nChasingWordSize, weight: FontWeight.w400, italic: true);
    final strong = _f1Text(context, size: _nChasingNameSize, weight: FontWeight.w800, italic: true);
    final suffix = _f1Text(context, size: _nChasingWordSize, weight: FontWeight.w800, italic: true);
    Widget line(double top, List<Widget> children) => Positioned(
          left: 0,
          top: top,
          width: _nChasingWidth,
          height: _nChasingLineHeight,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: children,
            ),
          ),
        );
    return Positioned(
      key: const ValueKey('highlights-driver-chasing'),
      left: _nDetailLeft,
      top: 0,
      width: _nChasingWidth,
      height: _nContentHeight,
      child: Stack(
        children: [
          line(_nChasingLine1Top, [
            Text(_chasingLabel, style: word),
            const SizedBox(width: _nChasingGap),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _nChasingNameMaxWidth),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  broadcastDriverName(otherName ?? '').last,
                  key: const ValueKey('highlights-driver-chasing-name'),
                  style: strong.copyWith(color: _readable(otherColor ?? AppColors.replayF1tvBrake)),
                ),
              ),
            ),
          ]),
          line(_nChasingLine2Top, [
            Text(_forLabel, style: word),
            const SizedBox(width: _nChasingGap),
            Text('${chasing.position}', key: const ValueKey('highlights-driver-chasing-position'), style: strong),
            Text(ordinalSuffix(chasing.position), style: suffix),
          ]),
        ],
      ),
    );
  }

  /// `RACE STORY` 제목 아래 `STARTED: 10TH` | `NOW: 9TH` 두 칸.
  Widget _story(BuildContext context, LowerThirdStory story) {
    final border = BorderSide(color: AppColors.replayF1tvIndicatorOff.withValues(alpha: _nStoryBorderOpacity));
    final caption = _f1Text(context, size: _nStoryCaptionSize, color: AppColors.replayF1tvSilver, weight: FontWeight.w500);
    Widget value(int position, Key key) => Padding(
          padding: const EdgeInsets.only(right: _nStoryValuePadding),
          child: Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '$position',
                  key: key,
                  style: _f1Text(
                    context,
                    size: position >= _twoDigits ? _nStoryValueSmallSize : _nStoryValueSize,
                    color: AppColors.replayF1tvSilver,
                    weight: FontWeight.w800,
                    italic: true,
                  ),
                ),
                Text(
                  ordinalSuffix(position),
                  style: _f1Text(context, size: _nStorySuffixSize, color: AppColors.replayF1tvSilver, weight: FontWeight.w800, italic: true),
                ),
              ],
            ),
          ),
        );
    Widget cell({
      required double left,
      required double width,
      required String label,
      required int position,
      required Border box,
      required Key valueKey,
    }) =>
        Positioned(
          left: left,
          top: _nStoryRowTop,
          width: width,
          height: _nStoryRowHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(border: box),
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: _nStoryCaptionWidth,
                  child: Center(child: Text(label, style: caption)),
                ),
                Positioned.fill(child: value(position, valueKey)),
              ],
            ),
          ),
        );
    return Positioned(
      key: const ValueKey('highlights-driver-story'),
      left: _nDetailLeft,
      top: 0,
      width: _nStoryBoxWidth,
      height: _nContentHeight,
      child: Stack(
        children: [
          Positioned(
            left: _nStoryLabelLeft,
            top: 0,
            right: 0,
            height: _nStoryLabelHeight,
            child: Center(
              child: Text(_storyLabel, style: _f1Text(context, size: _nStoryLabelSize, color: AppColors.replayF1tvStory, weight: FontWeight.w800)),
            ),
          ),
          cell(
            left: _nStoryStartedLeft,
            width: _nStoryStartedWidth,
            label: _startedLabel,
            position: story.started,
            box: Border(top: border, right: border),
            valueKey: const ValueKey('highlights-driver-story-started'),
          ),
          cell(
            left: _nStoryNowLeft,
            width: _nStoryNowWidth,
            label: story.finished ? _finishedLabel : _nowLabel,
            position: story.now,
            box: Border(top: border),
            valueKey: const ValueKey('highlights-driver-story-now'),
          ),
        ],
      ),
    );
  }

  /// `RACE`(흰색) + `WINNER`(팀 색).
  List<Widget> _winner(BuildContext context) {
    final style = _f1Text(context, size: _nWinnerSize, weight: FontWeight.w800, italic: true);
    Widget word(String text, double left, double width, Color? color, {Key? key}) => Positioned(
          key: key,
          left: left,
          top: _nWinnerTop,
          width: width,
          height: _nWinnerHeight,
          child: FittedBox(fit: BoxFit.scaleDown, child: Text(text, style: style.copyWith(color: color))),
        );
    return [
      word(_raceLabel, _nWinnerRaceLeft, _nWinnerRaceWidth, null),
      word(_winnerLabel, _nWinnerWordLeft, _nWinnerWordWidth, _readable(teamColor), key: const ValueKey('highlights-driver-winner')),
    ];
  }
}

/// 중계 그래픽 판 아래에 붙는 사선 띠(이름 자막 · 고스트 재생 이름판).
class BroadcastHatchStrip extends StatelessWidget {
  const BroadcastHatchStrip({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(
        height: _nStrokeHeight,
        child: Opacity(opacity: _nStrokeOpacity, child: CustomPaint(painter: _HatchPainter())),
      );
}

/// 자막 아래 사선 띠: 옅은 흰 바탕 위 어두운 사선(오른쪽 위로).
class _HatchPainter extends CustomPainter {
  const _HatchPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..clipRect(Offset.zero & size)
      ..drawRect(Offset.zero & size, Paint()..color = AppColors.replayHudText.withValues(alpha: _nStrokeBaseOpacity));
    final line = Paint()
      ..color = AppColors.replayF1tvRing
      ..strokeWidth = _nStrokeLine;
    for (var x = -size.height; x < size.width; x += _nStrokeGap) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), line);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HatchPainter oldDelegate) => false;
}

// -- 턴 표시 ---------------------------------------------------------------------------------

/// 턴 표시 설계 높이와 글자(`TURN` 얇게 · 번호 굵게), 글자 사이 간격, 검은 외곽선 두께.
const double kBroadcastTurnHeight = 80;
const double _tLabelSize = 35;
const double _tNumberSize = 55;
const double _tGap = 12;
const double _tOutline = 1.5;
const String _turnLabel = 'TURN';

/// 중계 턴 표시(F1TV Turn Indicator 모양): 기울인 흰 `TURN` + 큰 번호, 검은 외곽선(판 없이 화면 위에 바로).
class BroadcastTurnIndicator extends StatelessWidget {
  const BroadcastTurnIndicator({super.key, required this.turn});

  /// 코너 번호 글자(`3`·`7A`).
  final String turn;

  static const List<Shadow> _outline = [
    Shadow(color: AppColors.replayF1tvRing, offset: Offset(-_tOutline, -_tOutline)),
    Shadow(color: AppColors.replayF1tvRing, offset: Offset(_tOutline, -_tOutline)),
    Shadow(color: AppColors.replayF1tvRing, offset: Offset(-_tOutline, _tOutline)),
    Shadow(color: AppColors.replayF1tvRing, offset: Offset(_tOutline, _tOutline)),
  ];

  @override
  Widget build(BuildContext context) => SizedBox(
        key: const ValueKey('highlights-turn'),
        height: kBroadcastTurnHeight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(_turnLabel, style: _f1Text(context, size: _tLabelSize, weight: FontWeight.w400, italic: true, shadows: _outline)),
            const SizedBox(width: _tGap),
            Text(
              turn,
              key: const ValueKey('highlights-turn-number'),
              style: _f1Text(context, size: _tNumberSize, weight: FontWeight.w800, italic: true, shadows: _outline),
            ),
          ],
        ),
      );
}

// -- 레이스 컨트롤 메시지 ----------------------------------------------------------------------

/// 메시지 상자 설계 크기, 위 사선 띠(높이 · 불투명도 · 줄 굵기 · 간격), 왼쪽 머리 칸 폭·글자, 흰 이름판 줄무늬(폭 · 주기 · 불투명도),
/// 본문 여백·글자·줄 높이·줄 수.
const double kBroadcastMessageWidth = 710;
const double kBroadcastMessageHeight = 115;
const double _mStripeHeight = 15;
const double _mStripeOpacity = 0.5;
const double _mStripeBaseOpacity = 0.05;
const double _mStripeLineOpacity = 0.1;
const double _mStripeLine = 2;
const double _mStripeGap = 6.4;
const double _mHeadWidth = 135;
const double _mHeadSize = 22;
const double _mHeadSpacing = 1;
const double _mPlateBand = 20;
const double _mPlatePeriod = 39.6;
const double _mPlateStripeOpacity = 0.05;
const EdgeInsets _mTextPadding = EdgeInsets.fromLTRB(15, 8, 12, 8);
const double _mTextSize = 22;
const double _mTextLineHeight = 1.2;
const int _mTextMaxLines = 3;
const String _raceControlLine1 = 'RACE';
const String _raceControlLine2 = 'CONTROL';

/// 레이스 컨트롤 메시지 상자(F1TV Message Box 모양, 설계 [kBroadcastMessageWidth]×[kBroadcastMessageHeight]):
/// 위 사선 띠, 남색 머리 칸(`RACE CONTROL`), 옅은 사선 줄무늬의 흰 이름판에 남색 본문.
class BroadcastMessageBox extends StatelessWidget {
  const BroadcastMessageBox({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => SizedBox(
        key: const ValueKey('highlights-race-control'),
        width: kBroadcastMessageWidth,
        height: kBroadcastMessageHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(
              height: _mStripeHeight,
              child: Opacity(opacity: _mStripeOpacity, child: CustomPaint(painter: _MessageStripePainter())),
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: _mHeadWidth,
                    color: AppColors.replayF1tvNavy,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final line in const [_raceControlLine1, _raceControlLine2])
                          Text(line, style: _f1Text(context, size: _mHeadSize, weight: FontWeight.w800, letterSpacing: _mHeadSpacing)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: CustomPaint(
                      painter: const _PlatePainter(),
                      child: Padding(
                        padding: _mTextPadding,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            message,
                            key: const ValueKey('highlights-race-control-text'),
                            maxLines: _mTextMaxLines,
                            overflow: TextOverflow.ellipsis,
                            style: _f1Text(context, size: _mTextSize, color: AppColors.replayF1tvNavy, weight: FontWeight.w700)
                                .copyWith(height: _mTextLineHeight),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

/// 메시지 상자 위 띠: 옅은 흰 바탕 + 흰 사선(오른쪽 아래로).
class _MessageStripePainter extends CustomPainter {
  const _MessageStripePainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..clipRect(Offset.zero & size)
      ..drawRect(Offset.zero & size, Paint()..color = AppColors.replayF1tvPlate.withValues(alpha: _mStripeBaseOpacity));
    final line = Paint()
      ..color = AppColors.replayF1tvPlate.withValues(alpha: _mStripeLineOpacity)
      ..strokeWidth = _mStripeLine;
    for (var x = -size.height; x < size.width + size.height; x += _mStripeGap) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), line);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MessageStripePainter oldDelegate) => false;
}

/// 흰 이름판: 흰 바탕 위 넓고 옅은 사선 줄무늬.
class _PlatePainter extends CustomPainter {
  const _PlatePainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..clipRect(Offset.zero & size)
      ..drawRect(Offset.zero & size, Paint()..color = AppColors.replayF1tvPlate);
    final band = Paint()..color = AppColors.replayF1tvRing.withValues(alpha: _mPlateStripeOpacity);
    for (var x = -size.height; x < size.width + size.height; x += _mPlatePeriod) {
      canvas.drawPath(
        Path()
          ..moveTo(x, 0)
          ..lineTo(x + _mPlateBand, 0)
          ..lineTo(x + _mPlateBand + size.height, size.height)
          ..lineTo(x + size.height, size.height)
          ..close(),
        band,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PlatePainter oldDelegate) => false;
}
