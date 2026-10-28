import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../auth/domain/user_preferences.dart';
import '../domain/lap_analysis.dart';
import '../domain/lap_corners.dart';
import '../domain/lap_detail_models.dart';
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

/// 배터리: 효과가 작은 배포로 볼 직선(짧음 m·이미 빠름 km/h)과 배포량(J), 랩당 순소모가 많다고 볼 비율, lift & coast를 권할 직선 수.
const double _shortStraightM = 400;
const double _fastEntryKph = 250;
const double _notableDeployJ = 150000;
const double _heavyNetUse = 0.15;
const int _liftCoastStraights = 2;

/// 타이어: 한 바퀴 마모가 다른 바퀴보다 이만큼(%p) 크면 그 바퀴를 짚는다.
const double _wearLead = 0.1;

const String _title = '랩 분석';
const String _lossTitle = '시간을 잃은 코너';
const String _gainTitle = '앞선 코너';
const String _ersTitle = '배터리(ERS)';
const String _batteryTitle = '배터리 관리';
const String _tyreTitle = '타이어 관리';
const String _tyreCornerTitle = '타이어에 무리가 간 코너';
const String _noLossText = '기준 랩보다 시간을 잃은 코너가 없어요.';
const String _noReferenceText = '비교 랩을 고르면 코너마다 기준 랩보다 잃은 시간과 이유를 짚어 줘요.';

const Map<CornerDirection, String> _directionText = {CornerDirection.left: '왼쪽', CornerDirection.right: '오른쪽'};

String _meters(double m) => '${m.round()}m';

String _speed(double kph, UnitSystem units) =>
    units == UnitSystem.imperial ? '${kphToMph(kph).round()}mph' : '${kph.round()}km/h';

String _kj(double joules) => '${(joules / _joulesPerKj).round()}kJ';

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
    CornerFactorKind.kerbUse => '연석을 ${_meters(n)} 더 타요 → 타이어 손상·온도가 올라가요, 레이스에선 연석을 덜 쓰세요',
    CornerFactorKind.moreSteering =>
      '기준 랩보다 조향을 평균 ${n.round()}%p 더 써요 → 앞타이어가 미끄러지며 닳아요, 진입 속도를 조금 낮추고 핸들을 덜 꺾으세요',
    CornerFactorKind.brakingWhileTurning =>
      '크게 꺾은 채 강하게 ${_meters(n)} 브레이크를 밟아요 → 앞타이어 락업·플랫스팟 위험, 직선에서 더 많이 감속하세요',
    CornerFactorKind.throttleWhileTurning =>
      '크게 꺾은 채 ${_meters(n)} 풀 스로틀을 밟아요 → 뒷타이어 휠스핀·과열, 핸들을 풀면서 스로틀을 여세요',
  };
}

String _straightName(StraightErs s) => '${s.after?.label ?? '출발선'}–${s.before?.label ?? '결승선'}';

String _pct(double fraction) => '${(fraction * _percent).round()}%';

/// 배터리 피드백 줄들. 최대 속도 기준: 잔량·바닥난 곳·덜 써서 잃은 직선. 배터리 기준: 여기에 더해 효과가 작은 배포,
/// 배포하기 가장 좋은 직선, 랩당 소모가 클 때 lift & coast 자리.
List<String> ersFeedbackLines(ErsAnalysis ers, {AnalysisFocus focus = AnalysisFocus.pace}) {
  final refStart = ers.referenceStartFraction;
  final refEnd = ers.referenceEndFraction;
  final lines = [
    '랩 시작 ${_pct(ers.startFraction)} → 끝 ${_pct(ers.endFraction)}'
        '${refStart == null || refEnd == null ? '' : ' (기준 ${_pct(refStart)} → ${_pct(refEnd)})'}',
    if (ers.emptyAtM != null)
      '${ers.emptyNear?.label ?? '출발 직후'} 지나서 배터리가 바닥났어요 → 앞에서 배포를 아껴 나눠 쓰세요',
    for (final s in ers.underusedStraights)
      '${_straightName(s)} 직선에서 배터리를 ${_kj(-s.deployDiffJ!)} 덜 써 ${formatDeltaSeconds(s.lossS!)} 잃었어요 → 이 직선에 배포하세요',
  ];
  if (focus != AnalysisFocus.battery || ers.straights.isEmpty) {
    return lines;
  }
  // 배포 효과는 낮은 속도에서 긴 직선으로 나갈 때 가장 크다.
  final best = ers.straights.reduce((a, b) => a.lengthM / a.entryKph >= b.lengthM / b.entryKph ? a : b);
  for (final s in ers.straights) {
    if (!identical(s, best) && s.deployJ >= _notableDeployJ && (s.lengthM < _shortStraightM || s.entryKph >= _fastEntryKph)) {
      lines.add('${_straightName(s)} 직선(${_meters(s.lengthM)}, ${s.entryKph.round()}km/h에서 시작)에 ${_kj(s.deployJ)}를 써요 '
          '→ 짧거나 이미 빠른 구간이라 효과가 작아요, 아껴서 ${_straightName(best)} 직선에 쓰세요');
    }
  }
  lines.add('배포는 ${_straightName(best)} 직선(${_meters(best.lengthM)}, ${best.entryKph.round()}km/h에서 시작)이 가장 효과적이에요 '
      '— 느린 탈출에서 긴 직선으로 나갈 때 시간 이득이 커요');
  final netUse = ers.startFraction - ers.endFraction;
  final refNet = refStart == null || refEnd == null ? null : refStart - refEnd;
  if (netUse >= _heavyNetUse && (refNet == null || netUse > refNet)) {
    final longest = [...ers.straights]..sort((a, b) => b.lengthM.compareTo(a.lengthM));
    final spots = longest.take(_liftCoastStraights).map((s) => s.before?.label ?? '결승선').join('·');
    lines.add('랩당 배터리를 ${_pct(netUse)} 써요${refNet == null ? '' : '(기준 ${_pct(refNet)})'} '
        '→ 레이스 거리로는 모자라요. $spots 진입 전 브레이크 50~100m 앞에서 살짝 리프트(lift & coast)해 회수하세요 — 시간 손실은 작아요');
  }
  return lines;
}

/// 타이어 피드백 줄들: 이번 랩 바퀴별 마모, 가장 많이 닳은 바퀴와 그 원인·대처, 무리가 간 코너 수.
List<String> tyreFeedbackLines(WheelValues? wearStart, WheelValues? wearEnd, LapAnalysis analysis) {
  final lines = <String>[];
  double? delta(double? a, double? b) => a == null || b == null ? null : b - a;
  final wear = {
    '앞왼쪽': delta(wearStart?.frontLeft, wearEnd?.frontLeft),
    '앞오른쪽': delta(wearStart?.frontRight, wearEnd?.frontRight),
    '뒤왼쪽': delta(wearStart?.rearLeft, wearEnd?.rearLeft),
    '뒤오른쪽': delta(wearStart?.rearRight, wearEnd?.rearRight),
  };
  final known = {for (final e in wear.entries) if (e.value != null) e.key: e.value!};
  if (known.length == wear.length) {
    lines.add('이번 랩 마모: ${known.entries.map((e) => '${e.key} +${e.value.toStringAsFixed(1)}%').join(' · ')}');
    final sorted = known.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.first;
    if (top.value - sorted[1].value >= _wearLead) {
      final front = top.key.startsWith('앞');
      final left = top.key.endsWith('왼쪽');
      lines.add(front
          ? '${top.key} 타이어가 가장 많이 닳아요 → ${left ? '오른쪽' : '왼쪽'} 코너에서 앞이 밀리고 있어요(언더스티어). 진입 속도를 낮추고 조향을 덜 쓰세요'
          : '${top.key} 타이어가 가장 많이 닳아요 → 탈출 휠스핀이 원인이에요. ${left ? '오른쪽' : '왼쪽'} 코너 탈출에서 스로틀을 천천히 여세요');
    }
  }
  final stressed = analysis.corners.where((c) => c.factors.any((f) => isTyreFactor(f.kind))).toList();
  if (stressed.isNotEmpty) {
    lines.add('타이어에 무리가 간 코너 ${stressed.length}곳: ${stressed.map((c) => c.corner.label).join(' · ')}');
  }
  return lines;
}

/// 랩 분석 카드: 기준([AnalysisFocus])에 맞는 배터리·타이어 조언, 비교 랩([referenceLabel])보다 시간을 잃은 코너(많이 잃은 순)와
/// 이유·고칠 점, 타이어 기준이면 시간은 안 잃었어도 타이어에 무리가 간 코너, 앞선 코너. 코너 줄을 누르면 [onSelect].
class LapAnalysisCard extends StatelessWidget {
  const LapAnalysisCard({
    super.key,
    required this.analysis,
    required this.referenceLabel,
    required this.units,
    this.tyreWearStart,
    this.tyreWearEnd,
    this.onSelect,
  });

  final LapAnalysis analysis;

  /// 비교 랩 이름. 비교 랩이 없으면 null.
  final String? referenceLabel;
  final UnitSystem units;

  /// 이번 랩 시작·끝 타이어 마모(%, 타이어 기준의 바퀴별 마모).
  final WheelValues? tyreWearStart;
  final WheelValues? tyreWearEnd;
  final ValueChanged<LapCorner>? onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final heading = theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700);
    final muted = TextStyle(color: palette.textMuted);
    final focus = analysis.focus;
    final ers = analysis.ers;
    final select = onSelect;
    final label = referenceLabel;
    Widget lines(List<String> texts) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [for (final t in texts) Padding(padding: const EdgeInsets.only(bottom: _lineGap), child: Text(t))],
        );
    Widget corners(List<CornerAnalysis> list, {required bool showLoss}) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final c in list) ...[
              _CornerRow(
                analysis: c,
                units: units,
                showLoss: showLoss,
                onTap: select == null ? null : () => select(c.corner),
              ),
              const SizedBox(height: _rowGap),
            ],
          ],
        );
    final batteryLines = ers == null ? const <String>[] : ersFeedbackLines(ers, focus: focus);
    final tyreLines = tyreFeedbackLines(tyreWearStart, tyreWearEnd, analysis);
    final losses = analysis.losses;
    final gains = analysis.gains;
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
                if (label != null) Text('기준: $label', style: muted),
              ],
            ),
            if (focus == AnalysisFocus.battery && batteryLines.isNotEmpty) ...[
              const SizedBox(height: _sectionGap),
              Text(_batteryTitle, style: heading),
              const SizedBox(height: _rowGap),
              lines(batteryLines),
            ],
            if (focus == AnalysisFocus.tyres && tyreLines.isNotEmpty) ...[
              const SizedBox(height: _sectionGap),
              Text(_tyreTitle, style: heading),
              const SizedBox(height: _rowGap),
              lines(tyreLines),
            ],
            const SizedBox(height: _sectionGap),
            Text(_lossTitle, style: heading),
            const SizedBox(height: _rowGap),
            if (!analysis.hasReference)
              Text(_noReferenceText, style: muted)
            else if (losses.isEmpty)
              Text(_noLossText, style: muted)
            else
              corners(losses, showLoss: true),
            if (focus == AnalysisFocus.tyres && analysis.tyreStress.isNotEmpty) ...[
              const SizedBox(height: _sectionGap - _rowGap),
              Text(_tyreCornerTitle, style: heading),
              const SizedBox(height: _rowGap),
              corners(analysis.tyreStress, showLoss: false),
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
                      key: ValueKey('lap-analysis-gain-${c.corner.label}'),
                      style: TextStyle(color: palette.success, fontWeight: FontWeight.w600),
                    ),
                ],
              ),
            ],
            if (focus == AnalysisFocus.pace && batteryLines.isNotEmpty) ...[
              const SizedBox(height: _sectionGap),
              Text(_ersTitle, style: heading),
              const SizedBox(height: _rowGap),
              lines(batteryLines),
            ],
          ],
        ),
      ),
    );
  }
}

/// 코너 한 줄: `T10`·방향, 잃은 시간([showLoss]), 아래에 이유·고칠 점.
class _CornerRow extends StatelessWidget {
  const _CornerRow({required this.analysis, required this.units, required this.showLoss, required this.onTap});

  final CornerAnalysis analysis;
  final UnitSystem units;
  final bool showLoss;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final corner = analysis.corner;
    return InkWell(
      key: ValueKey('lap-analysis-corner-${corner.label}'),
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
                if (showLoss)
                  Text(
                    formatDeltaSeconds(analysis.lossS),
                    style: TextStyle(color: palette.danger, fontWeight: FontWeight.w700),
                  ),
                for (final (i, f) in analysis.factors.indexed)
                  Padding(
                    padding: EdgeInsets.only(top: showLoss || i > 0 ? _lineGap : 0),
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
