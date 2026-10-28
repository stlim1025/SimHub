import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../auth/domain/user_preferences.dart';
import '../domain/lap_analysis.dart';
import '../domain/lap_corners.dart';
import '../domain/telemetry_channels.dart';
import '../domain/telemetry_math.dart';

const EdgeInsets _cardPadding = EdgeInsets.all(16);
const double _sectionGap = 16;
const double _rowGap = 10;
const double _lineGap = 3;
const double _labelWidth = 56;
const double _chipSpacing = 8;
const double _percent = 100;
const double _joulesPerKj = 1000;

const String _title = '랩 분석';
const String _lossTitle = '시간을 잃은 코너';
const String _gainTitle = '앞선 코너';
const String _ersTitle = '배터리(ERS)';
const String _noLossText = '기준 랩보다 시간을 잃은 코너가 없어요.';

const Map<CornerDirection, String> _directionText = {CornerDirection.left: '왼쪽', CornerDirection.right: '오른쪽'};

String _meters(double m) => '${m.round()}m';

String _speed(double kph, UnitSystem units) =>
    units == UnitSystem.imperial ? '${kphToMph(kph).round()}mph' : '${kph.round()}km/h';

/// 코너 차이 하나를 엔지니어 말투로(무엇이 달랐는지 → 어떻게 고칠지).
String cornerFactorText(CornerFactor factor, UnitSystem units) {
  final n = factor.amount;
  return switch (factor.kind) {
    CornerFactorKind.brakeLater => '브레이킹이 ${_meters(n)} 늦어요 → 진입 오버슛, 브레이크 포인트를 앞당기세요',
    CornerFactorKind.brakeEarlier => '브레이킹이 ${_meters(n)} 일러요 → 더 늦게, 더 강하게 밟아도 돼요',
    CornerFactorKind.brakeNotNeeded => '기준 랩은 브레이크 없이 통과해요 → 리프트만으로 충분해요',
    CornerFactorKind.brakeLighter => '최대 브레이크 압력이 ${n.round()}%p 낮아요 → 초반에 한 번에 강하게 밟으세요',
    CornerFactorKind.brakeReleasedEarly => '브레이크를 ${_meters(n)} 일찍 떼요 → 에이펙스 가까이까지 트레일 브레이킹하세요',
    CornerFactorKind.coasting => '페달 없이 ${_meters(n)} 굴러가요(코스팅) → 브레이크에서 스로틀로 바로 넘어가세요',
    CornerFactorKind.throttleWhileBraking => '브레이킹 중 스로틀을 ${_meters(n)} 같이 밟아요 → 두 페달을 겹치지 마세요',
    CornerFactorKind.apexLater => '에이펙스가 ${_meters(n)} 늦어요(깊게 들어감) → 조금 더 일찍 턴인하세요',
    CornerFactorKind.apexEarlier => '에이펙스가 ${_meters(n)} 일러요(일찍 꺾음) → 턴인을 늦춰 탈출을 살리세요',
    CornerFactorKind.wideAtApex => '에이펙스에서 ${n.toStringAsFixed(1)}m 바깥이에요(넓게 돎) → 안쪽 연석에 더 붙이세요',
    CornerFactorKind.tightAtApex =>
      '에이펙스를 ${n.toStringAsFixed(1)}m 더 안쪽으로 깎아요 → 연석을 과하게 타 속도를 잃었을 수 있어요',
    CornerFactorKind.slowerApex => '코너 최저속도가 ${_speed(n, units)} 낮아요 → 진입 속도를 더 가져가세요',
    CornerFactorKind.throttleLift =>
      '탈출에서 스로틀을 일찍 열었다가 ${n.round()}%p 떼요 → 휠스핀·오버스티어, 더 점진적으로 여세요',
    CornerFactorKind.partialThrottle => '기준 랩이 풀 스로틀인 곳에서 ${_meters(n)} 덜 밟아요 → 더 과감하게 밟으세요',
    CornerFactorKind.throttleLater => '풀 스로틀이 ${_meters(n)} 늦어요 → 에이펙스 뒤 더 빨리 가속하세요',
    CornerFactorKind.slowerExit => '탈출 속도가 ${_speed(n, units)} 낮아요',
    CornerFactorKind.slowerThrough => '구간 평균 속도가 ${_speed(n, units)} 낮아요 → 라인 전체를 고스트와 비교해 보세요',
  };
}

String _straightName(StraightErs s) => '${s.after?.label ?? '출발선'}–${s.before?.label ?? '결승선'}';

String _pct(double fraction) => '${(fraction * _percent).round()}%';

/// ERS 피드백 줄들: 랩 시작·끝 잔량, 바닥난 곳, 덜 써서 잃은 직선.
List<String> ersFeedbackLines(ErsAnalysis ers) => [
      '랩 시작 ${_pct(ers.startFraction)} → 끝 ${_pct(ers.endFraction)} '
          '(기준 ${_pct(ers.referenceStartFraction)} → ${_pct(ers.referenceEndFraction)})',
      if (ers.emptyAtM != null)
        '${ers.emptyNear?.label ?? '출발 직후'} 지나서 배터리가 바닥났어요(기준 랩은 남아 있음) → 앞에서 배포를 아껴 나눠 쓰세요',
      for (final s in ers.underusedStraights)
        '${_straightName(s)} 직선에서 배터리를 ${(-s.deployDiffJ / _joulesPerKj).round()}kJ 덜 써 '
            '${formatDeltaSeconds(s.lossS)} 잃었어요 → 이 직선에 배포하세요',
    ];

/// 랩 분석 카드: 기준 랩([referenceLabel])보다 시간을 잃은 코너(많이 잃은 순)와 그 이유·고칠 점, 앞선 코너, ERS 피드백.
/// 코너 줄을 누르면 [onSelect]로 그 코너를 알린다(그래프·지도 위치를 옮긴다).
class LapAnalysisCard extends StatelessWidget {
  const LapAnalysisCard({
    super.key,
    required this.analysis,
    required this.referenceLabel,
    required this.units,
    this.onSelect,
  });

  final LapAnalysis analysis;
  final String referenceLabel;
  final UnitSystem units;
  final ValueChanged<LapCorner>? onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final heading = theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700);
    final muted = TextStyle(color: palette.textMuted);
    final losses = analysis.losses;
    final gains = analysis.gains;
    final ers = analysis.ers;
    final select = onSelect;
    return Card(
      key: const ValueKey('lap-analysis'),
      child: Padding(
        padding: _cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: _chipSpacing,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(_title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                Text('기준: $referenceLabel', style: muted),
              ],
            ),
            const SizedBox(height: _sectionGap),
            Text(_lossTitle, style: heading),
            const SizedBox(height: _rowGap),
            if (losses.isEmpty) Text(_noLossText, style: muted),
            for (final c in losses) ...[
              _CornerRow(analysis: c, units: units, onTap: select == null ? null : () => select(c.corner)),
              const SizedBox(height: _rowGap),
            ],
            if (gains.isNotEmpty) ...[
              const SizedBox(height: _sectionGap - _rowGap),
              Text(_gainTitle, style: heading),
              const SizedBox(height: _rowGap),
              Wrap(
                spacing: _chipSpacing,
                runSpacing: _lineGap,
                children: [
                  for (final c in gains)
                    Text(
                      '${c.corner.label} ${formatDeltaSeconds(c.lossS)}',
                      key: ValueKey('lap-analysis-gain-${c.corner.number}'),
                      style: TextStyle(color: palette.success, fontWeight: FontWeight.w600),
                    ),
                ],
              ),
            ],
            if (ers != null) ...[
              const SizedBox(height: _sectionGap),
              Text(_ersTitle, style: heading),
              const SizedBox(height: _rowGap),
              for (final line in ersFeedbackLines(ers))
                Padding(padding: const EdgeInsets.only(bottom: _lineGap), child: Text(line)),
            ],
          ],
        ),
      ),
    );
  }
}

/// 잃은 코너 한 줄: `T10`·방향, 잃은 시간, 아래에 이유·고칠 점.
class _CornerRow extends StatelessWidget {
  const _CornerRow({required this.analysis, required this.units, required this.onTap});

  final CornerAnalysis analysis;
  final UnitSystem units;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final corner = analysis.corner;
    return InkWell(
      key: ValueKey('lap-analysis-corner-${corner.number}'),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _labelWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(corner.label, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(_directionText[corner.direction]!, style: TextStyle(color: palette.textMuted)),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatDeltaSeconds(analysis.lossS),
                  style: TextStyle(color: palette.danger, fontWeight: FontWeight.w700),
                ),
                for (final f in analysis.factors)
                  Padding(
                    padding: const EdgeInsets.only(top: _lineGap),
                    child: Text(cornerFactorText(f, units)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
