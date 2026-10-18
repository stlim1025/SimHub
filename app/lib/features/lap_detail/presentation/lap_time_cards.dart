import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/util/lap_time.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/stat.dart';
import '../../laps/domain/lap_models.dart';
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
const String _thisRowLabel = '이 랩';
const String _deltaRowLabel = 'Delta';
const String _personalBestText = '이 랩이 내 최고 기록';
const String kNoComparisonText = '비교할 유효 랩이 없어요';

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

/// Comparison 카드(D-46): 행 = 내 최고 랩 / 이 랩 / Delta, 열 = TOTAL · SEC 1~3. 이 랩이 최고면 그 안내, 비교 대상이 없으면 그 안내.
class ComparisonCard extends StatelessWidget {
  const ComparisonCard({super.key, required this.detail});

  final LapDetail detail;

  @override
  Widget build(BuildContext context) {
    final comparison = detail.comparison;
    final muted = TextStyle(color: context.palette.textMuted);
    final Widget body = switch (comparison) {
      null => Text(kNoComparisonText, style: muted),
      _ when detail.isPersonalBest => Text(
          _personalBestText,
          style: TextStyle(color: context.palette.success, fontWeight: FontWeight.w600),
        ),
      final ComparisonLap best => _ComparisonTable(lap: detail.lap, best: best),
    };
    return SectionCard(title: 'Comparison', child: body);
  }
}

class _ComparisonTable extends StatelessWidget {
  const _ComparisonTable({required this.lap, required this.best});

  final Lap lap;
  final ComparisonLap best;

  @override
  Widget build(BuildContext context) {
    final lapTimes = [lap.lapTimeMs, for (var n = 1; n <= kSectorCount; n++) sectorTimeOf(lap.sectors, n)];
    final bestTimes = [best.lapTimeMs, for (var n = 1; n <= kSectorCount; n++) sectorTimeOf(best.sectors, n)];
    final palette = context.palette;
    final header = Theme.of(context).textTheme.labelSmall?.copyWith(color: palette.textMuted, fontWeight: FontWeight.w600);
    return Column(
      children: [
        _ComparisonRow(
          label: '',
          cells: [for (final h in ['TOTAL', for (var n = 1; n <= kSectorCount; n++) 'SEC $n']) Text(h, style: header)],
        ),
        const Divider(height: 1),
        _ComparisonRow(label: _bestRowLabel, cells: [for (final ms in bestTimes) Text(_timeText(ms), style: _tabular)]),
        const Divider(height: 1),
        _ComparisonRow(label: _thisRowLabel, cells: [for (final ms in lapTimes) Text(_timeText(ms), style: _tabular)]),
        const Divider(height: 1),
        _ComparisonRow(
          label: _deltaRowLabel,
          cells: [for (var i = 0; i < lapTimes.length; i++) _DeltaText(lapMs: lapTimes[i], bestMs: bestTimes[i])],
        ),
      ],
    );
  }
}

class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow({required this.label, required this.cells});

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
class _DeltaText extends StatelessWidget {
  const _DeltaText({required this.lapMs, required this.bestMs});

  final int? lapMs;
  final int? bestMs;

  @override
  Widget build(BuildContext context) {
    final lap = lapMs;
    final best = bestMs;
    if (lap == null || best == null) {
      return const Text(kDetailNoValueText);
    }
    final delta = lap - best;
    final palette = context.palette;
    final color = switch (deltaToneOf(delta)) {
      DeltaTone.faster => palette.success,
      DeltaTone.slower => palette.danger,
      DeltaTone.even => palette.textMuted,
    };
    return Text(formatDeltaMs(delta), style: _tabular.copyWith(color: color, fontWeight: FontWeight.w600));
  }
}
