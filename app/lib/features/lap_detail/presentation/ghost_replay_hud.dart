import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/util/lap_time.dart';
import '../../auth/domain/user_preferences.dart';
import '../../sessions/presentation/tyre_stints_view.dart';
import '../domain/ghost_replay.dart';
import '../domain/telemetry_channels.dart';
import '../domain/telemetry_math.dart';

/// 계기판 배치: 오른쪽 아래, 넓은 화면은 원래 크기·좁은 화면은 화면 폭 비율에 맞춰 줄인다.
const double _inset = 10;
const double _wideMaxWidthFraction = 0.36;
const double _narrowMaxWidthFraction = 0.44;
const double _narrowWidth = 520;

/// 계기판 판(디자인 크기, 화면에 맞춰 줄어든다).
const double _panelWidth = 250;
const double _panelRadius = 8;
const EdgeInsets _panelPadding = EdgeInsets.fromLTRB(12, 10, 12, 10);
const double _dialHeight = 210;

/// 다이얼: 바깥 고리(왼쪽 스로틀·오른쪽 브레이크), 안쪽 고리(속도). 각도는 왼쪽 아래(135°)에서 시계 방향 270°.
const double _dialStart = math.pi * 3 / 4;
const double _dialSweep = math.pi * 3 / 2;
const double _pedalGap = 0.03;
const double _outerStroke = 15;
const double _speedStroke = 13;
const double _ringGap = 4;
const double _tickInset = 15;
const double _tickFontSize = 8.5;
const double _arcLabelFontSize = 8.5;
const double _arcLabelSpacing = 0.085;
const double _dialRadiusFraction = 0.49;
const double _dialCenterYFraction = 0.53;

/// 속도 눈금: 최고 값·간격(km/h, mph).
const double _metricMaxSpeed = 360;
const double _metricTickStep = 60;
const double _imperialMaxSpeed = 220;
const double _imperialTickStep = 40;

const double _timeFontSize = 16;
const double _gapFontSize = 12;
const double _speedFontSize = 40;
const double _rpmFontSize = 19;
const double _unitFontSize = 9;
const double _gearFontSize = 20;
const double _labelFontSize = 10;
const double _sectorFontSize = 11;
const double _tyreBadgeSize = 22;
const double _tyreRingWidth = 2.5;
const double _vsBadgeSize = 24;
const double _sectorBarHeight = 3;
const double _barHeight = 4;
const double _flowBarWidth = 70;
const double _percentMax = 100;
const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

const String _throttleLabel = 'THROTTLE';
const String _brakeLabel = 'BRAKE';
const String _rpmLabel = 'RPM';
const String _gearLabel = 'GEAR';
const String _vsLabel = 'VS';

/// 고스트 재생 계기판(게임 텔레메트리 화면처럼 한 판에 모은다):
/// - 위: 경과 시간(초록)·비교 랩과의 시간 차, 오른쪽에 타이어 컴파운드.
/// - 가운데 다이얼: 바깥 고리 왼쪽 스로틀(파랑)·오른쪽 브레이크(빨강), 안쪽 고리 속도(초록, 눈금), 가운데 속도·RPM.
/// - 기어, ERS 배터리·충전/사용, 섹터 S1·S2·S3(지난 섹터는 시간·차이, 지금 섹터는 흰 밑줄).
/// - 비교 랩이 있으면 맨 아래 VS 줄(팀 색·이름·속도·기어).
class GhostReplayHud extends StatelessWidget {
  const GhostReplayHud({
    super.key,
    required this.elapsedMs,
    required this.player,
    required this.ghost,
    required this.gapMs,
    required this.sectors,
    required this.units,
    required this.playerColor,
    required this.ghostColor,
    required this.thisLapLabel,
    required this.referenceLabel,
    this.tyreCompound,
  });

  final double elapsedMs;
  final ReplayFrame player;
  final ReplayFrame? ghost;
  final double? gapMs;
  final List<ReplaySectorRow> sectors;
  final UnitSystem units;
  final Color playerColor;
  final Color ghostColor;
  final String thisLapLabel;
  final String referenceLabel;

  /// 이 랩 타이어(보이는 컴파운드 이름). 모르면 표시하지 않는다.
  final String? tyreCompound;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) {
          final fraction = box.maxWidth < _narrowWidth ? _narrowMaxWidthFraction : _wideMaxWidthFraction;
          return Stack(
            children: [
              Positioned(
                right: _inset,
                bottom: _inset,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: box.maxWidth * fraction, maxHeight: box.maxHeight - _inset * 2),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.bottomRight,
                    child: _dashboard(DefaultTextStyle.of(context).style),
                  ),
                ),
              ),
            ],
          );
        },
      );

  /// [baseStyle]은 다이얼 글자(눈금·THROTTLE·BRAKE)가 앱 글꼴을 따르게 넘긴다.
  Widget _dashboard(TextStyle baseStyle) {
    const keyName = 'ghost-replay-player-hud';
    final ghostFrame = ghost;
    final gap = gapMs;
    final compound = tyreCompound;
    final battery = player.batteryPercent;
    final flow = player.ersFlowKw;
    return Container(
      key: const ValueKey(keyName),
      width: _panelWidth,
      padding: _panelPadding,
      decoration: BoxDecoration(color: AppColors.replayDashPanel, borderRadius: BorderRadius.circular(_panelRadius)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                formatLapTime(elapsedMs.round()),
                key: const ValueKey('ghost-replay-elapsed'),
                style: const TextStyle(
                  color: AppColors.replayDashTime,
                  fontSize: _timeFontSize,
                  fontWeight: FontWeight.w700,
                  fontFeatures: _tabular,
                ),
              ),
              const SizedBox(width: 8),
              if (gap != null)
                Text(
                  formatReplayGap(gap),
                  key: const ValueKey('ghost-replay-gap'),
                  style: TextStyle(
                    color: _deltaColor(gap),
                    fontSize: _gapFontSize,
                    fontWeight: FontWeight.w700,
                    fontFeatures: _tabular,
                  ),
                ),
              const Spacer(),
              if (compound != null) _TyreBadge(compound: compound),
            ],
          ),
          SizedBox(
            height: _dialHeight,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    key: const ValueKey('$keyName-dial'),
                    painter: _DialPainter(
                      throttle: player.throttle / _percentMax,
                      brake: player.brake / _percentMax,
                      speed: _speedIn(player.speedKph, units),
                      imperial: units == UnitSystem.imperial,
                      baseStyle: baseStyle,
                    ),
                  ),
                ),
                Align(
                  alignment: const Alignment(0, 0.08),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${_speedIn(player.speedKph, units).round()}',
                        style: const TextStyle(
                          color: AppColors.replayHudText,
                          fontSize: _speedFontSize,
                          fontWeight: FontWeight.w700,
                          fontFeatures: _tabular,
                          height: 1,
                        ),
                      ),
                      _unit(units == UnitSystem.imperial ? 'MPH' : 'KMH'),
                      const SizedBox(height: 6),
                      Text(
                        '${player.rpm}',
                        key: const ValueKey('$keyName-rpm'),
                        style: const TextStyle(
                          color: AppColors.replayHudText,
                          fontSize: _rpmFontSize,
                          fontWeight: FontWeight.w600,
                          fontFeatures: _tabular,
                          height: 1,
                        ),
                      ),
                      _unit(_rpmLabel),
                    ],
                  ),
                ),
                // 기어: 다이얼 아래 열린 자리.
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      _unit(_gearLabel),
                      const SizedBox(width: 6),
                      Text(
                        gearLabel(player.gear),
                        key: const ValueKey('$keyName-gear'),
                        style: const TextStyle(color: AppColors.replayHudText, fontSize: _gearFontSize, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (battery != null && flow != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.bolt, size: 13, color: AppColors.replayBattery),
                Text(
                  '${battery.round()}%',
                  key: const ValueKey('$keyName-battery-text'),
                  style: const TextStyle(
                    color: AppColors.replayBattery,
                    fontSize: _sectorFontSize,
                    fontWeight: FontWeight.w700,
                    fontFeatures: _tabular,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: _Bar(key: const ValueKey('$keyName-battery'), fraction: battery / _percentMax)),
                const SizedBox(width: 10),
                _ErsFlowBar(key: const ValueKey('$keyName-ers-flow'), fraction: flow / kErsMaxFlowKw),
                const SizedBox(width: 8),
                _ErsFlowText(textKey: const ValueKey('$keyName-ers-flow-text'), flowKw: flow),
              ],
            ),
          ],
          if (sectors.isNotEmpty) ...[
            const SizedBox(height: 10),
            _Sectors(key: const ValueKey('ghost-replay-sectors'), rows: sectors),
          ],
          if (ghostFrame != null) ...[
            const SizedBox(height: 10),
            _VersusRow(frame: ghostFrame, color: ghostColor, label: referenceLabel, units: units),
          ],
        ],
      ),
    );
  }

  static Widget _unit(String text) => Text(
        text,
        style: const TextStyle(
          color: AppColors.replayHudMuted,
          fontSize: _unitFontSize,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
      );
}

double _speedIn(double kph, UnitSystem units) => units == UnitSystem.imperial ? kphToMph(kph) : kph;

/// 앞서면 초록, 뒤지면 노랑, 같으면 흐린 색.
Color _deltaColor(double delta) => delta < 0 ? AppColors.replayFaster : (delta > 0 ? AppColors.replaySlower : AppColors.replayHudMuted);

/// 타이어 컴파운드: 컴파운드 색 고리 안 첫 글자(S·M·H·I·W).
class _TyreBadge extends StatelessWidget {
  const _TyreBadge({required this.compound});

  final String compound;

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('ghost-replay-tyre'),
        width: _tyreBadgeSize,
        height: _tyreBadgeSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.replayCarTyre,
          border: Border.all(color: tyreColorOf(compound), width: _tyreRingWidth),
        ),
        child: Text(
          compound.isEmpty ? '' : compound[0].toUpperCase(),
          style: const TextStyle(color: AppColors.replayHudText, fontSize: _labelFontSize, fontWeight: FontWeight.w800, height: 1),
        ),
      );
}

/// 섹터 S1·S2·S3: 이름, 밑줄(지난 섹터는 차이 색, 지금 섹터는 흰색), 지난 섹터의 이 랩 시간과 비교 랩과의 차이.
class _Sectors extends StatelessWidget {
  const _Sectors({super.key, required this.rows});

  final List<ReplaySectorRow> rows;

  @override
  Widget build(BuildContext context) {
    final current = rows.indexWhere((r) => r.playerMs == null);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(child: _cell(rows[i], isCurrent: i == current)),
        ],
      ],
    );
  }

  Widget _cell(ReplaySectorRow row, {required bool isCurrent}) {
    final playerMs = row.playerMs;
    final referenceMs = row.referenceMs;
    final delta = playerMs != null && referenceMs != null ? (playerMs - referenceMs).toDouble() : null;
    final bar = isCurrent
        ? AppColors.replayHudText
        : (delta != null ? _deltaColor(delta) : (playerMs != null ? AppColors.replayHudMuted : AppColors.replayDashTrack));
    return Column(
      children: [
        Text(
          'S${row.sector}',
          style: TextStyle(
            color: isCurrent || playerMs != null ? AppColors.replayHudText : AppColors.replayHudMuted,
            fontSize: _sectorFontSize,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Container(height: _sectorBarHeight, color: bar),
        if (playerMs != null) ...[
          const SizedBox(height: 4),
          Text(
            formatLapTime(playerMs),
            style: const TextStyle(color: AppColors.replayHudText, fontSize: _labelFontSize, fontWeight: FontWeight.w600, fontFeatures: _tabular),
          ),
        ],
        if (delta != null)
          Text(
            formatReplayGap(delta),
            style: TextStyle(color: _deltaColor(delta), fontSize: _labelFontSize, fontWeight: FontWeight.w700, fontFeatures: _tabular),
          ),
      ],
    );
  }
}

/// 비교 랩 줄: 빨간 VS 원 · 팀 색 점 · 이름 · 속도 · 기어.
class _VersusRow extends StatelessWidget {
  const _VersusRow({required this.frame, required this.color, required this.label, required this.units});

  final ReplayFrame frame;
  final Color color;
  final String label;
  final UnitSystem units;

  @override
  Widget build(BuildContext context) => Row(
        key: const ValueKey('ghost-replay-ghost-hud'),
        children: [
          Container(
            width: _vsBadgeSize,
            height: _vsBadgeSize,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.replayHudAccent, shape: BoxShape.circle),
            child: const Text(
              _vsLabel,
              style: TextStyle(color: AppColors.replayHudText, fontSize: _unitFontSize, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 8),
          Container(width: 3, height: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.replayHudMuted, fontSize: _labelFontSize, fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            '${_speedIn(frame.speedKph, units).round()}',
            style: const TextStyle(
              color: AppColors.replayHudText,
              fontSize: _sectorFontSize + 1,
              fontWeight: FontWeight.w700,
              fontFeatures: _tabular,
            ),
          ),
          const SizedBox(width: 3),
          GhostReplayHud._unit(units == UnitSystem.imperial ? 'MPH' : 'KMH'),
          const SizedBox(width: 8),
          Text(
            gearLabel(frame.gear),
            style: const TextStyle(color: AppColors.replayHudText, fontSize: _sectorFontSize + 1, fontWeight: FontWeight.w700),
          ),
        ],
      );
}

/// 충전/사용 출력 글자: `+150 kW`(초록) · `−200 kW`(파랑) · `0 kW`.
class _ErsFlowText extends StatelessWidget {
  const _ErsFlowText({this.textKey, required this.flowKw});

  final Key? textKey;
  final double flowKw;

  @override
  Widget build(BuildContext context) {
    final kw = flowKw.round();
    final charging = kw > 0;
    return Text(
      '${charging ? '+' : (kw < 0 ? '−' : '')}${kw.abs()} kW',
      key: textKey,
      style: TextStyle(
        color: charging ? AppColors.replayThrottle : (kw < 0 ? AppColors.replayDeploy : AppColors.replayHudMuted),
        fontSize: _labelFontSize,
        fontWeight: FontWeight.w700,
        fontFeatures: _tabular,
      ),
    );
  }
}

/// 배터리 잔량 막대(노랑, 0~1 채움).
class _Bar extends StatelessWidget {
  const _Bar({super.key, required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) => Container(
        height: _barHeight,
        color: AppColors.replayDashTrack,
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: fraction.clamp(0.0, 1.0),
          heightFactor: 1,
          child: const ColoredBox(color: AppColors.replayBattery),
        ),
      );
}

/// ERS 충전/사용 막대: 가운데에서 오른쪽(초록)으로 차면 충전, 왼쪽(파랑)으로 차면 사용. [fraction]은 −1 ~ 1.
class _ErsFlowBar extends StatelessWidget {
  const _ErsFlowBar({super.key, required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    final amount = fraction.abs().clamp(0.0, 1.0);
    final charging = fraction > 0;
    return Container(
      width: _flowBarWidth,
      height: _barHeight,
      color: AppColors.replayDashTrack,
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: FractionallySizedBox(
                widthFactor: charging ? 0 : amount,
                heightFactor: 1,
                child: const ColoredBox(color: AppColors.replayDeploy),
              ),
            ),
          ),
          const SizedBox(width: 1, height: _barHeight, child: ColoredBox(color: AppColors.replayHudText)),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: charging ? amount : 0,
                heightFactor: 1,
                child: const ColoredBox(color: AppColors.replayThrottle),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 다이얼: 바깥 고리 왼쪽 절반 스로틀(아래에서 위로 파랑), 오른쪽 절반 브레이크(아래에서 위로 빨강), 고리 위 글자.
/// 안쪽 고리 속도(초록, 왼쪽 아래 0에서 시계 방향), 그 안쪽 눈금 숫자.
class _DialPainter extends CustomPainter {
  const _DialPainter({
    required this.throttle,
    required this.brake,
    required this.speed,
    required this.imperial,
    required this.baseStyle,
  });

  final double throttle;
  final double brake;
  final double speed;
  final bool imperial;
  final TextStyle baseStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * _dialCenterYFraction);
    final outer = math.min(size.width, size.height) * _dialRadiusFraction - _outerStroke / 2;
    final inner = outer - _outerStroke / 2 - _ringGap - _speedStroke / 2;
    Paint ring(Color color, double stroke) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    void arc(double radius, double start, double sweep, Paint paint) =>
        canvas.drawArc(Rect.fromCircle(center: center, radius: radius), start, sweep, false, paint);

    // 바깥 고리: 스로틀(왼쪽 아래 → 꼭대기), 브레이크(오른쪽 아래 → 꼭대기).
    const half = _dialSweep / 2 - _pedalGap;
    const brakeStart = _dialStart + _dialSweep;
    final track = ring(AppColors.replayDashTrack, _outerStroke);
    arc(outer, _dialStart, half, track);
    arc(outer, brakeStart, -half, track);
    final t = throttle.clamp(0.0, 1.0);
    final b = brake.clamp(0.0, 1.0);
    if (t > 0) {
      arc(outer, _dialStart, half * t, ring(AppColors.replayDashThrottle, _outerStroke));
    }
    if (b > 0) {
      arc(outer, brakeStart, -half * b, ring(AppColors.replayBrake, _outerStroke));
    }
    _arcText(canvas, center, outer, _throttleLabel, _dialStart + half * 0.5);
    _arcText(canvas, center, outer, _brakeLabel, brakeStart - half * 0.5);


    // 안쪽 고리: 속도.
    final maxSpeed = imperial ? _imperialMaxSpeed : _metricMaxSpeed;
    arc(inner, _dialStart, _dialSweep, ring(AppColors.replayDashTrack, _speedStroke));
    final s = (speed / maxSpeed).clamp(0.0, 1.0);
    if (s > 0) {
      arc(inner, _dialStart, _dialSweep * s, ring(AppColors.replayDashSpeed, _speedStroke));
    }
    final step = imperial ? _imperialTickStep : _metricTickStep;
    for (var v = step; v <= maxSpeed; v += step) {
      final angle = _dialStart + _dialSweep * v / maxSpeed;
      final at = center + Offset(math.cos(angle), math.sin(angle)) * (inner - _tickInset);
      final painter = _text('${v.round()}', AppColors.replayHudMuted, _tickFontSize);
      painter.paint(canvas, at - Offset(painter.width / 2, painter.height / 2));
    }
  }

  /// 고리를 따라 글자를 하나씩 세운다(시계 방향으로 읽힘 — 왼쪽은 아래에서 위로, 오른쪽은 위에서 아래로). [middle]은 가운데 각도.
  void _arcText(Canvas canvas, Offset center, double radius, String text, double middle) {
    final first = middle - _arcLabelSpacing * (text.length - 1) / 2;
    for (var k = 0; k < text.length; k++) {
      final angle = first + _arcLabelSpacing * k;
      final painter = _text(text[k], AppColors.replayHudText, _arcLabelFontSize);
      canvas
        ..save()
        ..translate(center.dx + radius * math.cos(angle), center.dy + radius * math.sin(angle))
        ..rotate(angle + math.pi / 2);
      painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
      canvas.restore();
    }
  }

  TextPainter _text(String text, Color color, double fontSize) => TextPainter(
        text: TextSpan(
          text: text,
          style: baseStyle.copyWith(color: color, fontSize: fontSize, fontWeight: FontWeight.w700, fontFeatures: _tabular),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.throttle != throttle ||
      old.brake != brake ||
      old.speed != speed ||
      old.imperial != imperial ||
      old.baseStyle != baseStyle;
}
