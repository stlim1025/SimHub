import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/util/lap_time.dart';
import '../../auth/domain/user_preferences.dart';
import '../domain/ghost_replay.dart';
import '../domain/telemetry_channels.dart';
import '../domain/telemetry_math.dart';

/// HUD 배치: 넓은 화면은 원래 크기, 좁은 화면은 화면 비율에 맞춰 줄인다(넘치지 않게).
const double _inset = 10;
const double _towerMaxWidthFraction = 0.6;
const double _cardMaxWidthFraction = 0.38;
const double _gaugeMaxWidthFraction = 0.42;
const double _gaugeMaxHeightFraction = 0.4;

/// 이 폭보다 좁으면 비교 랩 카드를 타이밍 타워 아래에 쌓는다.
const double _sideBySideMinWidth = 520;
const double _stackGap = 6;

/// 패널 공통.
const double _panelRadius = 6;
const double _accentWidth = 4;
const double _stripWidth = 4;

/// 타이밍 타워.
const double _towerHeaderHeight = 38;
const double _towerRowHeight = 25;
const double _sectorLabelWidth = 30;
const double _sectorTimeWidth = 74;
const double _sectorDeltaWidth = 62;
const double _sectorStatusWidth = 3;
const double _elapsedFontSize = 22;
const double _gapFontSize = 13;
const double _rowFontSize = 13;
const EdgeInsets _gapPillPadding = EdgeInsets.symmetric(horizontal: 7, vertical: 2);

/// 비교 랩 카드.
const double _cardWidth = 206;
const double _cardSpeedFontSize = 20;
const double _cardLabelFontSize = 12;
const double _cardUnitFontSize = 10;
const double _cardBarWidth = 64;
const double _gearBadgeSize = 24;

/// 계기판(이 랩): 속도·기어·스로틀/브레이크 호·배터리 호.
const double _gaugeWidth = 230;
const double _gaugeHeight = 150;
const double _gaugeArcStroke = 7;
const double _gaugeInnerStroke = 3.5;
const double _gaugeInnerGap = 11;
const double _gaugeCenterYFraction = 0.66;
const double _gaugeSpeedFontSize = 36;
const double _gaugeGearBadgeSize = 28;
const double _gaugeFlowBarWidth = 64;

const double _barHeight = 5;
const double _percentMax = 100;
const String _notYet = '–';
const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

/// 고스트 재생 화면 위 중계 화면식 HUD.
/// - 왼쪽 위 타이밍 타워: 경과 시간·비교 랩과의 시간 차(앞서면 초록, 뒤지면 노랑)와 섹터별 이 랩·비교 랩·차이.
/// - 오른쪽 위 비교 랩 카드: 팀 색 띠·이름·속도·기어·페달·배터리.
/// - 오른쪽 아래 이 랩 계기판: 가운데 속도·기어, 바깥 호 왼쪽 스로틀·오른쪽 브레이크, 안쪽 호 배터리, 아래 ERS 충전/사용.
///
/// 차는 화면 가운데(아래쪽 72%)에 그려지므로 HUD는 네 귀퉁이에만 둔다.
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

  @override
  Widget build(BuildContext context) {
    final ghostFrame = ghost;
    return LayoutBuilder(builder: (context, box) {
      final tower = _TimingTower(elapsedMs: elapsedMs, gapMs: gapMs, sectors: sectors, hasReference: ghostFrame != null);
      final card = ghostFrame == null
          ? null
          : _ReferenceCard(
              key: const ValueKey('ghost-replay-ghost-hud'),
              keyName: 'ghost-replay-ghost-hud',
              frame: ghostFrame,
              color: ghostColor,
              label: referenceLabel,
              units: units,
            );
      // 좁으면 타워 오른쪽에 카드 자리가 없다 — 카드를 타워 아래 같은 왼쪽 열에 둔다.
      final stacked = box.maxWidth < _sideBySideMinWidth;
      return Stack(
        children: [
          Positioned(
            left: _inset,
            top: _inset,
            child: _fit(
              maxWidth: box.maxWidth * _towerMaxWidthFraction,
              alignment: Alignment.topLeft,
              child: stacked && card != null
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [tower, const SizedBox(height: _stackGap), card],
                    )
                  : tower,
            ),
          ),
          if (!stacked && card != null)
            Positioned(
              right: _inset,
              top: _inset,
              child: _fit(maxWidth: box.maxWidth * _cardMaxWidthFraction, alignment: Alignment.topRight, child: card),
            ),
          Positioned(
            right: _inset,
            bottom: _inset,
            child: _fit(
              maxWidth: box.maxWidth * _gaugeMaxWidthFraction,
              maxHeight: box.maxHeight * _gaugeMaxHeightFraction,
              alignment: Alignment.bottomRight,
              child: _Gauge(
                key: const ValueKey('ghost-replay-player-hud'),
                keyName: 'ghost-replay-player-hud',
                frame: player,
                color: playerColor,
                label: thisLapLabel,
                units: units,
              ),
            ),
          ),
        ],
      );
    });
  }

  static Widget _fit({required double maxWidth, double? maxHeight, required Alignment alignment, required Widget child}) =>
      ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight ?? double.infinity),
        child: FittedBox(fit: BoxFit.scaleDown, alignment: alignment, child: child),
      );
}

/// 앞서면 초록, 뒤지면 노랑, 같으면 흐린 색(중계 화면의 구간 색).
Color _deltaColor(double delta) => delta < 0 ? AppColors.replayFaster : (delta > 0 ? AppColors.replaySlower : AppColors.replayHudMuted);

Widget _panel({required Widget child, Color? accent}) => ClipRRect(
      borderRadius: BorderRadius.circular(_panelRadius),
      child: DecoratedBox(
        decoration: const BoxDecoration(color: AppColors.replayHudPanel),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (accent != null) SizedBox(width: _stripWidth, child: ColoredBox(color: accent)),
              child,
            ],
          ),
        ),
      ),
    );

/// 왼쪽 위 타이밍 타워: 머리줄(빨간 띠 · 경과 시간 · 시간 차)과 섹터 줄.
class _TimingTower extends StatelessWidget {
  const _TimingTower({required this.elapsedMs, required this.gapMs, required this.sectors, required this.hasReference});

  final double elapsedMs;
  final double? gapMs;
  final List<ReplaySectorRow> sectors;
  final bool hasReference;

  @override
  Widget build(BuildContext context) {
    final gap = gapMs;
    return ClipRRect(
      borderRadius: BorderRadius.circular(_panelRadius),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: _towerHeaderHeight,
            color: AppColors.replayHudHeader,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: _accentWidth, child: ColoredBox(color: AppColors.replayHudAccent)),
                const SizedBox(width: 10),
                Text(
                  formatLapTime(elapsedMs.round()),
                  key: const ValueKey('ghost-replay-elapsed'),
                  style: const TextStyle(
                    color: AppColors.replayHudText,
                    fontSize: _elapsedFontSize,
                    fontWeight: FontWeight.w800,
                    fontStyle: FontStyle.italic,
                    fontFeatures: _tabular,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 12),
                if (gap != null)
                  Container(
                    padding: _gapPillPadding,
                    decoration: BoxDecoration(color: _deltaColor(gap), borderRadius: BorderRadius.circular(3)),
                    child: Text(
                      formatReplayGap(gap),
                      key: const ValueKey('ghost-replay-gap'),
                      style: const TextStyle(
                        color: AppColors.replayHudOnColor,
                        fontSize: _gapFontSize,
                        fontWeight: FontWeight.w800,
                        fontFeatures: _tabular,
                      ),
                    ),
                  ),
                const SizedBox(width: 10),
              ],
            ),
          ),
          if (sectors.isNotEmpty)
            Container(
              key: const ValueKey('ghost-replay-sectors'),
              color: AppColors.replayHudPanel,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < sectors.length; i++) _sectorRow(sectors[i], striped: i.isOdd),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectorRow(ReplaySectorRow row, {required bool striped}) {
    final playerMs = row.playerMs;
    final referenceMs = row.referenceMs;
    final delta = playerMs != null && referenceMs != null ? (playerMs - referenceMs).toDouble() : null;
    final status = delta == null ? AppColors.replayHudTrack : _deltaColor(delta);
    String time(int? ms) => ms == null ? _notYet : formatLapTime(ms);
    const muted = TextStyle(color: AppColors.replayHudMuted, fontSize: _rowFontSize, fontWeight: FontWeight.w600, fontFeatures: _tabular);
    return Container(
      height: _towerRowHeight,
      color: striped ? AppColors.replayHudStripe : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: _sectorStatusWidth, child: ColoredBox(color: status)),
          const SizedBox(width: 8),
          SizedBox(width: _sectorLabelWidth, child: Text('S${row.sector}', style: muted)),
          SizedBox(
            width: _sectorTimeWidth,
            child: Text(
              time(playerMs),
              textAlign: TextAlign.end,
              style: TextStyle(
                color: playerMs == null ? AppColors.replayHudMuted : AppColors.replayHudText,
                fontSize: _rowFontSize,
                fontWeight: FontWeight.w800,
                fontFeatures: _tabular,
              ),
            ),
          ),
          if (hasReference) ...[
            SizedBox(width: _sectorTimeWidth, child: Text(time(referenceMs), textAlign: TextAlign.end, style: muted)),
            SizedBox(
              width: _sectorDeltaWidth,
              child: delta == null
                  ? null
                  : Text(
                      formatReplayGap(delta),
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        color: _deltaColor(delta),
                        fontSize: _rowFontSize,
                        fontWeight: FontWeight.w800,
                        fontFeatures: _tabular,
                      ),
                    ),
            ),
          ],
          const SizedBox(width: 10),
        ],
      ),
    );
  }
}

/// 오른쪽 위 비교 랩 카드: 팀 색 띠 · 이름 · 속도 · 기어 · 페달 · 배터리.
class _ReferenceCard extends StatelessWidget {
  const _ReferenceCard({
    super.key,
    required this.keyName,
    required this.frame,
    required this.color,
    required this.label,
    required this.units,
  });

  final String keyName;
  final ReplayFrame frame;
  final Color color;
  final String label;
  final UnitSystem units;

  @override
  Widget build(BuildContext context) {
    final battery = frame.batteryPercent;
    final flow = frame.ersFlowKw;
    return _panel(
      accent: color,
      child: SizedBox(
        width: _cardWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.replayHudText,
                  fontSize: _cardLabelFontSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _SpeedText(frame: frame, units: units, fontSize: _cardSpeedFontSize, unitFontSize: _cardUnitFontSize),
                  const Spacer(),
                  _GearBadge(gear: frame.gear, size: _gearBadgeSize),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _Bar(key: ValueKey('$keyName-throttle'), fraction: frame.throttle / _percentMax, color: AppColors.replayThrottle),
                  const SizedBox(width: 6),
                  _Bar(key: ValueKey('$keyName-brake'), fraction: frame.brake / _percentMax, color: AppColors.replayBrake),
                ],
              ),
              if (battery != null && flow != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.bolt, size: 13, color: AppColors.replayBattery),
                    Text(
                      '${battery.round()}%',
                      style: const TextStyle(
                        color: AppColors.replayBattery,
                        fontSize: _cardUnitFontSize + 1,
                        fontWeight: FontWeight.w700,
                        fontFeatures: _tabular,
                      ),
                    ),
                    const Spacer(),
                    _ErsFlowText(flowKw: flow, fontSize: _cardUnitFontSize + 1),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 오른쪽 아래 이 랩 계기판. 바깥 호: 왼쪽 끝에서 위로 스로틀(초록), 오른쪽 끝에서 위로 브레이크(빨강). 안쪽 호: 배터리(노랑).
/// 가운데 속도·단위, 그 아래 기어, 맨 아래 배터리 %·ERS 충전/사용.
class _Gauge extends StatelessWidget {
  const _Gauge({
    super.key,
    required this.keyName,
    required this.frame,
    required this.color,
    required this.label,
    required this.units,
  });

  final String keyName;
  final ReplayFrame frame;
  final Color color;
  final String label;
  final UnitSystem units;

  @override
  Widget build(BuildContext context) {
    final battery = frame.batteryPercent;
    final flow = frame.ersFlowKw;
    return SizedBox(
      width: _gaugeWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _panel(
            accent: color,
            child: Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.replayHudText, fontSize: _cardLabelFontSize, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(_panelRadius * 2),
            child: Container(
              height: _gaugeHeight,
              color: AppColors.replayHudPanel,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      key: ValueKey('$keyName-throttle'),
                      painter: _ArcPainter(fraction: frame.throttle / _percentMax, color: AppColors.replayThrottle, fromLeft: true),
                    ),
                  ),
                  Positioned.fill(
                    child: CustomPaint(
                      key: ValueKey('$keyName-brake'),
                      painter: _ArcPainter(fraction: frame.brake / _percentMax, color: AppColors.replayBrake, fromLeft: false),
                    ),
                  ),
                  if (battery != null)
                    Positioned.fill(
                      child: CustomPaint(
                        key: ValueKey('$keyName-battery'),
                        painter: _ArcPainter(
                          fraction: battery / _percentMax,
                          color: AppColors.replayBattery,
                          fromLeft: true,
                          inner: true,
                        ),
                      ),
                    ),
                  Align(
                    alignment: const Alignment(0, 0.05),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _SpeedText(frame: frame, units: units, fontSize: _gaugeSpeedFontSize, unitFontSize: _cardUnitFontSize, stacked: true),
                        const SizedBox(height: 4),
                        _GearBadge(gear: frame.gear, size: _gaugeGearBadgeSize),
                      ],
                    ),
                  ),
                  if (battery != null && flow != null)
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 8,
                      child: Row(
                        children: [
                          Text(
                            '${battery.round()}%',
                            key: ValueKey('$keyName-battery-text'),
                            style: const TextStyle(
                              color: AppColors.replayBattery,
                              fontSize: _cardUnitFontSize + 1,
                              fontWeight: FontWeight.w800,
                              fontFeatures: _tabular,
                            ),
                          ),
                          const Spacer(),
                          _ErsFlowBar(key: ValueKey('$keyName-ers-flow'), fraction: flow / kErsMaxFlowKw),
                          const Spacer(),
                          _ErsFlowText(textKey: ValueKey('$keyName-ers-flow-text'), flowKw: flow, fontSize: _cardUnitFontSize + 1),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 속도 숫자와 단위. [stacked]면 단위를 숫자 아래에 둔다.
class _SpeedText extends StatelessWidget {
  const _SpeedText({required this.frame, required this.units, required this.fontSize, required this.unitFontSize, this.stacked = false});

  final ReplayFrame frame;
  final UnitSystem units;
  final double fontSize;
  final double unitFontSize;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final imperial = units == UnitSystem.imperial;
    final speed = (imperial ? kphToMph(frame.speedKph) : frame.speedKph).round();
    final number = Text(
      '$speed',
      style: TextStyle(
        color: AppColors.replayHudText,
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        fontStyle: FontStyle.italic,
        fontFeatures: _tabular,
        height: 1,
      ),
    );
    final unit = Text(
      imperial ? 'MPH' : 'KM/H',
      style: TextStyle(color: AppColors.replayHudMuted, fontSize: unitFontSize, fontWeight: FontWeight.w700, letterSpacing: 0.8),
    );
    return stacked
        ? Column(mainAxisSize: MainAxisSize.min, children: [number, const SizedBox(height: 2), unit])
        : Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [number, const SizedBox(width: 4), unit],
          );
  }
}

/// 기어 원형 배지(흰 원 안 진한 글자).
class _GearBadge extends StatelessWidget {
  const _GearBadge({required this.gear, required this.size});

  final int gear;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: AppColors.replayHudText, shape: BoxShape.circle),
        child: Text(
          gearLabel(gear),
          style: TextStyle(color: AppColors.replayHudOnColor, fontSize: size * 0.55, fontWeight: FontWeight.w900, height: 1),
        ),
      );
}

/// 충전/사용 출력 글자: `+150 kW`(초록) · `−200 kW`(파랑) · `0 kW`.
class _ErsFlowText extends StatelessWidget {
  const _ErsFlowText({this.textKey, required this.flowKw, required this.fontSize});

  final Key? textKey;
  final double flowKw;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final kw = flowKw.round();
    final charging = kw > 0;
    return Text(
      '${charging ? '+' : (kw < 0 ? '−' : '')}${kw.abs()} kW',
      key: textKey,
      style: TextStyle(
        color: charging ? AppColors.replayThrottle : (kw < 0 ? AppColors.replayDeploy : AppColors.replayHudMuted),
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        fontFeatures: _tabular,
      ),
    );
  }
}

/// 가로 막대(0~1 채움).
class _Bar extends StatelessWidget {
  const _Bar({super.key, required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(_barHeight / 2),
        child: Container(
          width: _cardBarWidth,
          height: _barHeight,
          color: AppColors.replayHudTrack,
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(widthFactor: fraction.clamp(0.0, 1.0), heightFactor: 1, child: ColoredBox(color: color)),
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(_barHeight / 2),
      child: Container(
        width: _gaugeFlowBarWidth,
        height: _barHeight,
        color: AppColors.replayHudTrack,
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
      ),
    );
  }
}

/// 계기판 호. 바깥 호(스로틀·브레이크)는 왼쪽/오른쪽 끝에서 꼭대기까지 반쪽씩, 안쪽 호(배터리)는 왼쪽 끝에서 오른쪽 끝까지 반원.
class _ArcPainter extends CustomPainter {
  const _ArcPainter({required this.fraction, required this.color, required this.fromLeft, this.inner = false});

  final double fraction;
  final Color color;
  final bool fromLeft;
  final bool inner;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * _gaugeCenterYFraction);
    final outer = math.min(size.width / 2, center.dy) - _gaugeArcStroke;
    final radius = inner ? outer - _gaugeInnerGap : outer;
    final stroke = inner ? _gaugeInnerStroke : _gaugeArcStroke;
    final rect = Rect.fromCircle(center: center, radius: radius);
    Paint arc(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final amount = fraction.clamp(0.0, 1.0);

    // 각도: 왼쪽 끝 = π, 꼭대기 = 1.5π, 오른쪽 끝 = 2π(시계 방향이 +).
    final start = inner || fromLeft ? math.pi : 2 * math.pi;
    final sweep = inner ? math.pi : (fromLeft ? math.pi / 2 : -math.pi / 2);
    canvas.drawArc(rect, start, sweep, false, arc(AppColors.replayHudTrack));
    if (amount > 0) {
      canvas.drawArc(rect, start, sweep * amount, false, arc(color));
    }
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.fraction != fraction || old.color != color || old.fromLeft != fromLeft || old.inner != inner;
}
