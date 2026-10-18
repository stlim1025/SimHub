import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/util/lap_time.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/stat.dart';
import '../../laps/domain/lap_models.dart';
import '../domain/lap_compare.dart';
import '../domain/lap_detail_display.dart';
import '../domain/lap_detail_models.dart';

/// F1 25는 3섹터(S1·S2·S3).
const int kSectorCount = 3;

const double _sectorSpacing = 24;
const double _totalSectorGap = 12;
const int _labelFlex = 3;
const int _valueFlex = 2;
const double _comparisonRowPadding = 8;

const String _bestRowLabel = '내 최고 랩';
const String _leaderboardRowLabel = '리더보드 랩';
const String _otherLapRowLabel = '비교 랩';
const String _thisRowLabel = '이 랩';
const String _deltaRowLabel = 'Delta';
const String _percentRowLabel = '';
const String _personalBestText = '이 랩이 내 최고 기록';
const String _leaderboardBestText = '이 랩이 리더보드 최고 기록';
const String kNoComparisonText = '비교할 유효 랩이 없어요';
const String kNoLeaderboardComparisonText = '리더보드에 비교할 랩이 없어요';
const String kComparisonNoFilterMatchText = '필터에 맞는 비교 랩이 없어요';
const String kComparisonNotFoundText = '비교할 수 없는 랩이에요(없거나 공개되지 않은 랩)';

const _tabular = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

/// 섹터 [number]의 시간(ms). 없으면 null.
int? sectorTimeOf(List<LapSector> sectors, int number) =>
    sectors.where((s) => s.sectorNumber == number).firstOrNull?.sectorTimeMs;

String _timeText(int? ms) => ms == null ? kDetailNoValueText : formatLapTime(ms);

/// Lap Time 카드: Total(크게, 링크 색) + Sector 1·2·3.
class LapTimeCard extends StatelessWidget {
  const LapTimeCard({super.key, required this.lap});

  final Lap lap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      title: 'Lap Time',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formatLapTime(lap.lapTimeMs),
            key: const ValueKey('lap-time-total'),
            style: theme.textTheme.headlineLarge?.copyWith(
              color: context.palette.link,
              fontWeight: FontWeight.bold,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: _totalSectorGap),
          Wrap(
            spacing: _sectorSpacing,
            runSpacing: _totalSectorGap,
            children: [
              for (var n = 1; n <= kSectorCount; n++)
                Stat(label: 'Sector $n', value: _timeText(sectorTimeOf(lap.sectors, n))),
            ],
          ),
        ],
      ),
    );
  }
}

/// 비교 랩 행 이름(비교 종류별, D-51).
String comparisonRowLabel(LapCompareKind kind) => switch (kind) {
      LapCompareKind.leaderboard => _leaderboardRowLabel,
      LapCompareKind.lap => _otherLapRowLabel,
      _ => _bestRowLabel,
    };

/// 비교 대상이 없을 때의 안내(D-51). 필터를 켰는데 맞는 랩이 없으면 그 말을 한다.
String comparisonUnavailableText(LapDetail detail, LapCompareSelection compare) {
  if (detail.comparisonUnavailable == ComparisonUnavailable.notFound) {
    return kComparisonNotFoundText;
  }
  if (compare.filters.isNotEmpty) {
    return kComparisonNoFilterMatchText;
  }
  return compare.kind == LapCompareKind.leaderboard ? kNoLeaderboardComparisonText : kNoComparisonText;
}

/// Comparison 카드(D-46·D-51): 행 = 비교 랩 / 이 랩 / Delta / 비율(%), 열 = TOTAL · SEC 1~3.
/// 남의 랩이면 위에 드라이버 이름(익명 규칙은 서버)·팀. 내 최고·리더보드 최고가 곧 이 랩이면 그 안내, 비교 대상이 없으면 그 까닭.
class ComparisonCard extends StatelessWidget {
  const ComparisonCard({super.key, required this.detail, this.compare = LapCompareSelection.defaults});

  final LapDetail detail;
  final LapCompareSelection compare;

  @override
  Widget build(BuildContext context) {
    final comparison = detail.comparison;
    final muted = TextStyle(color: context.palette.textMuted);
    final itself = detail.comparesWithItself && comparison?.kind != LapCompareKind.lap;
    final Widget body = switch (comparison) {
      null => Text(comparisonUnavailableText(detail, compare), style: muted),
      final ComparisonLap c when itself => Text(
          c.kind == LapCompareKind.leaderboard ? _leaderboardBestText : _personalBestText,
          style: TextStyle(color: context.palette.success, fontWeight: FontWeight.w600),
        ),
      final ComparisonLap reference => _ComparisonTable(lap: detail.lap, reference: reference),
    };
    return SectionCard(title: 'Comparison', child: body);
  }
}

class _ComparisonTable extends StatelessWidget {
  const _ComparisonTable({required this.lap, required this.reference});

  final Lap lap;
  final ComparisonLap reference;

  @override
  Widget build(BuildContext context) {
    final lapTimes = [lap.lapTimeMs, for (var n = 1; n <= kSectorCount; n++) sectorTimeOf(lap.sectors, n)];
    final refTimes = [reference.lapTimeMs, for (var n = 1; n <= kSectorCount; n++) sectorTimeOf(reference.sectors, n)];
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final header = theme.labelSmall?.copyWith(color: palette.textMuted, fontWeight: FontWeight.w600);
    final owner = reference.isMine ? null : reference.displayName;
    final team = reference.team?.name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (owner != null)
          Text(
            team == null ? owner : '$owner · $team',
            key: const ValueKey('comparison-driver'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        _ComparisonRow(
          label: '',
          cells: [for (final h in ['TOTAL', for (var n = 1; n <= kSectorCount; n++) 'SEC $n']) Text(h, style: header)],
        ),
        const Divider(height: 1),
        _ComparisonRow(
          label: comparisonRowLabel(reference.kind),
          cells: [for (final ms in refTimes) Text(_timeText(ms), style: _tabular)],
        ),
        const Divider(height: 1),
        _ComparisonRow(label: _thisRowLabel, cells: [for (final ms in lapTimes) Text(_timeText(ms), style: _tabular)]),
        const Divider(height: 1),
        _ComparisonRow(
          label: _deltaRowLabel,
          cells: [for (var i = 0; i < lapTimes.length; i++) _DeltaText(lapMs: lapTimes[i], bestMs: refTimes[i])],
        ),
        _ComparisonRow(
          key: const ValueKey('comparison-percent-row'),
          label: _percentRowLabel,
          cells: [
            for (var i = 0; i < lapTimes.length; i++) _DeltaText(lapMs: lapTimes[i], bestMs: refTimes[i], percent: true),
          ],
        ),
      ],
    );
  }
}

class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow({super.key, required this.label, required this.cells});

  final String label;
  final List<Widget> cells;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: _comparisonRowPadding),
      child: DefaultTextStyle.merge(
        style: small,
        child: Row(
          children: [
            Expanded(
              flex: _labelFlex,
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.palette.textMuted)),
            ),
            for (final cell in cells)
              Expanded(
                flex: _valueFlex,
                child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: cell),
              ),
          ],
        ),
      ),
    );
  }
}

/// Delta 칸: 빠르면 초록 `-0.123`, 느리면 빨강 `+0.456`, 같으면 흐린 `0.000`. 한쪽이라도 없으면 `-`.
/// [percent]면 비율 `+12.3%`(D-51, 굵기 없이).
class _DeltaText extends StatelessWidget {
  const _DeltaText({required this.lapMs, required this.bestMs, this.percent = false});

  final int? lapMs;
  final int? bestMs;
  final bool percent;

  @override
  Widget build(BuildContext context) {
    final lap = lapMs;
    final best = bestMs;
    final text = lap == null || best == null
        ? null
        : (percent ? formatDeltaPercent(lap, best) : formatDeltaMs(lap - best));
    if (lap == null || best == null || text == null) {
      return const Text(kDetailNoValueText);
    }
    final palette = context.palette;
    final color = switch (deltaToneOf(lap - best)) {
      DeltaTone.faster => palette.success,
      DeltaTone.slower => palette.danger,
      DeltaTone.even => palette.textMuted,
    };
    return Text(
      text,
      style: _tabular.copyWith(color: color, fontWeight: percent ? FontWeight.w500 : FontWeight.w600),
    );
  }
}
