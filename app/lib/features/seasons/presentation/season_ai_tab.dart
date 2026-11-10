import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/equal_height.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/util/lap_time.dart';
import '../../../core/widgets/compact_table.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/page_loading_bar.dart';
import '../../../core/widgets/track_flag.dart';
import '../../lap_detail/presentation/detail_list.dart';
import '../../sessions/domain/session_display.dart' show kNoValueText;
import '../../sessions/presentation/session_widgets.dart';
import '../application/seasons_providers.dart';
import '../domain/season_ai_difficulty.dart';

const String _qualifyingTitle = 'Qualifying';
const String _raceTitle = 'Race';
const String _carTitle = 'Car';
const String _weekendsTitle = 'Weekends';
const String _timeTrialTitle = 'Time Trial';
const String _errorMessage = 'AI 난이도 가이드를 불러오지 못했어요.';
const String _noWeekends = '이 시즌에 기록된 예선·레이스가 없어요.';
const String _noTimeTrial = '이 시즌 트랙의 마른 노면 타임트라이얼 기록이 없어요.';
const String _teammateAverage = '팀메이트 평균';
const String _myAverage = '내 평균';

/// 판정에 필요한 최소 세션 수(서버 판정 기준과 같다).
const int _minSamples = 3;

const double _cardsRowWidth = 900;
const double _cardGap = 20;
const double _sectionGap = 24;
const double _titleGap = 8;
const double _lineGap = 6;
const double _verdictFontSize = 26;
const double _flagGap = 8;
const double _vsGap = 6;
const int _secondsDigits = 3;
const int _percentDigits = 2;
const int _positionDigits = 1;
const int _msPerSecond = 1000;

/// 표 폭이 이 이상이면 날씨·팀메이트 열을 더 보인다.
const double _wideTableWidth = 1000;
const double _aiColumnWidth = 64;
const double _vsColumnWidth = 120;
const double _gapColumnWidth = 110;
const double _weatherColumnWidth = 110;
const double _timeColumnWidth = 120;
const double _aiTimeColumnWidth = 170;

/// 좁은 표([kCompactTableDefaultWidth] 미만)의 열 폭.
const double _narrowVsColumnWidth = 88;
const double _narrowGapColumnWidth = 72;
const double _narrowTimeColumnWidth = 84;

/// 시즌 AI 탭: 지금 AI 난이도가 맞는지(같은 차를 탄 AI 팀메이트 대비 예선 · 레이스 판정 + 차 수준), 주말별 비교 표,
/// 타임트라이얼 최고 랩 대 마른 노면 예선의 가장 빠른 AI 랩. 차이는 "나 − 팀메이트"(음수 = 내가 빠름, 초록).
class SeasonAiTab extends ConsumerWidget {
  const SeasonAiTab({super.key, required this.seasonId});

  final String seasonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guide = ref.watch(seasonAiDifficultyProvider(seasonId));
    return guide.when(
      loading: () => const PageLoadingBar(),
      error: (e, _) => ErrorRetry(
        error: e,
        fallbackMessage: _errorMessage,
        onRetry: () => ref.invalidate(seasonAiDifficultyProvider(seasonId)),
      ),
      data: (data) => _AiGuide(guide: data),
    );
  }
}

class _AiGuide extends StatelessWidget {
  const _AiGuide({required this.guide});

  final SeasonAiDifficulty guide;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: context.palette.textMuted);
    final cards = [
      _VerdictCard(
        key: const ValueKey('ai-verdict-qualifying'),
        title: _qualifyingTitle,
        verdict: guide.qualifying,
        currentAi: guide.currentAiDifficulty,
        perLap: false,
      ),
      _VerdictCard(
        key: const ValueKey('ai-verdict-race'),
        title: _raceTitle,
        verdict: guide.race,
        currentAi: guide.currentAiDifficulty,
        perLap: true,
      ),
      _CarCard(car: guide.car),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth >= _cardsRowWidth
              ? EqualHeightRow(gap: _cardGap, children: cards)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < cards.length; i++) ...[
                      if (i > 0) const SizedBox(height: _cardGap),
                      cards[i],
                    ],
                  ],
                ),
        ),
        const SizedBox(height: _sectionGap),
        const _SectionTitle(_weekendsTitle),
        const SizedBox(height: _titleGap),
        if (guide.weekends.isEmpty) Text(_noWeekends, style: muted) else _WeekendsTable(weekends: guide.weekends),
        const SizedBox(height: _sectionGap),
        const _SectionTitle(_timeTrialTitle),
        const SizedBox(height: _titleGap),
        if (guide.timeTrial.isEmpty) Text(_noTimeTrial, style: muted) else _TimeTrialTable(rows: guide.timeTrial),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) =>
      Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold));
}

// -- 판정 카드 ------------------------------------------------------------------

/// 판정 하나: 큰 글자 판정(올려도 됨 · 적정 · 낮추는 게 좋음 · 판단 보류) + 바꿀 폭(추정) + 근거(팀메이트 대비 중앙값, 앞선 횟수).
class _VerdictCard extends StatelessWidget {
  const _VerdictCard({
    super.key,
    required this.title,
    required this.verdict,
    required this.currentAi,
    required this.perLap,
  });

  final String title;
  final AiVerdict verdict;
  final int? currentAi;

  /// 레이스면 근거가 랩당 평균 차이다.
  final bool perLap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final muted = TextStyle(color: palette.textMuted);
    final (label, color) = switch (verdict.kind) {
      AiVerdictKind.raise => ('올려도 됨', palette.success),
      AiVerdictKind.keep => ('적정', AppColors.accent),
      AiVerdictKind.lower => ('낮추는 게 좋음', palette.danger),
      AiVerdictKind.notEnoughData => ('판단 보류', palette.textMuted),
    };
    final steps = _stepsLabel(verdict);
    return SessionCard(
      title: title,
      trailing: currentAi == null ? null : PositionBadge(text: 'AI $currentAi'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: _verdictFontSize, fontWeight: FontWeight.w800, color: color)),
          if (steps != null) ...[
            const SizedBox(height: _lineGap),
            Text(steps, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
          const SizedBox(height: _lineGap),
          Text(_basis(), style: muted),
        ],
      ),
    );
  }

  /// `+1~2단계 (추정)` · `-3단계 이상 (추정)`. 적정·판단 보류면 null.
  static String? _stepsLabel(AiVerdict verdict) {
    final sign = switch (verdict.kind) {
      AiVerdictKind.raise => '+',
      AiVerdictKind.lower => '-',
      _ => null,
    };
    if (sign == null || verdict.steps == null) {
      return null;
    }
    final size = verdict.steps == '3+' ? '3단계 이상' : '1~2단계';
    return '$sign$size (추정)';
  }

  String _basis() {
    final ai = currentAi == null ? '' : 'AI $currentAi로 ';
    if (verdict.samples == 0) {
      return '$ai팀메이트와 비교할 세션이 없어요.';
    }
    final percent = verdict.medianGapPercent;
    final ms = verdict.medianGapMs;
    final gap = percent == null || ms == null
        ? ''
        : '팀메이트 대비 ${perLap ? '랩당 ' : ''}${signedPercent(percent)} (${signedSeconds(ms)}초) · ';
    final count = '${verdict.samples}번 중 ${verdict.aheadOfTeammate}번 앞섬';
    return verdict.kind == AiVerdictKind.notEnoughData
        ? '$gap$count — $ai비교한 세션이 $_minSamples번 이상 필요해요.'
        : '$gap$count';
  }
}

/// 차 수준: 팀메이트(이 차의 수준)와 나의 시즌 평균 예선·레이스 순위.
class _CarCard extends StatelessWidget {
  const _CarCard({required this.car});

  final AiCarLevel car;

  @override
  Widget build(BuildContext context) {
    String line(double? quali, double? race) => '예선 ${_avg(quali)} · 레이스 ${_avg(race)}';
    return SessionCard(
      key: const ValueKey('ai-car-level'),
      title: _carTitle,
      child: DetailList(
        items: [
          DetailItem(_teammateAverage, text: line(car.teammateQualiPosition, car.teammateRacePosition)),
          DetailItem(_myAverage, text: line(car.myQualiPosition, car.myRacePosition)),
        ],
      ),
    );
  }

  static String _avg(double? value) => value == null ? kNoValueText : 'P${value.toStringAsFixed(_positionDigits)}';
}

// -- 표 ------------------------------------------------------------------------

/// 주말별 비교: GRAND PRIX · AI · QUALI(나 / 팀메이트) · Q GAP · SPRINT · RACE · PACE / LAP · WEATHER · TEAMMATE.
class _WeekendsTable extends StatelessWidget {
  const _WeekendsTable({required this.weekends});

  final List<AiWeekend> weekends;

  @override
  Widget build(BuildContext context) {
    final hasSprint = weekends.any((w) => w.sprint != null);
    final muted = TextStyle(color: context.palette.textMuted);
    return LayoutBuilder(builder: (context, constraints) {
      final roomy = constraints.maxWidth >= kCompactTableDefaultWidth;
      final vsWidth = roomy ? _vsColumnWidth : _narrowVsColumnWidth;
      final gapWidth = roomy ? _gapColumnWidth : _narrowGapColumnWidth;
      return _table(hasSprint, muted, vsWidth, gapWidth);
    });
  }

  Widget _table(bool hasSprint, TextStyle muted, double vsWidth, double gapWidth) {
    return CompactTable<AiWeekend>(
      rows: weekends,
      rowKey: (w) => ValueKey('ai-weekend-${w.round}'),
      columns: [
        CompactColumn(label: 'Grand Prix', flex: 3, cell: (w) => _TrackCell(name: w.trackName, countryCode: w.countryCode)),
        CompactColumn(
          label: 'AI',
          width: _aiColumnWidth,
          compactHidden: true,
          cell: (w) => Text(w.aiDifficulty?.toString() ?? kNoValueText, style: kTabularStyle),
        ),
        CompactColumn(
          label: 'Quali',
          width: vsWidth,
          cell: (w) => _VsCell(mine: w.myQualiPosition, theirs: w.teammateQualiPosition),
        ),
        CompactColumn(label: 'Q Gap', width: gapWidth, compactHidden: true, cell: (w) => _GapCell(ms: w.qualiGapMs)),
        if (hasSprint)
          CompactColumn(
            label: 'Sprint',
            width: vsWidth,
            compactHidden: true,
            cell: (w) => _VsCell(mine: w.sprint?.myPosition, theirs: w.sprint?.teammatePosition),
          ),
        CompactColumn(
          label: 'Race',
          width: vsWidth,
          cell: (w) => _VsCell(mine: w.mainRace?.myPosition, theirs: w.mainRace?.teammatePosition),
        ),
        CompactColumn(
          label: 'Pace / Lap',
          width: gapWidth,
          compactHidden: true,
          cell: (w) => _GapCell(ms: w.mainRace?.paceGapPerLapMs),
        ),
        CompactColumn(
          label: 'Weather',
          width: _weatherColumnWidth,
          hideBelowWidth: _wideTableWidth,
          cell: (w) => Text(w.weather ?? kNoValueText, style: muted),
        ),
        CompactColumn(
          label: 'Teammate',
          flex: 2,
          hideBelowWidth: _wideTableWidth,
          cell: (w) => Text(w.teammateName ?? kNoValueText, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

/// 타임트라이얼 비교: GRAND PRIX · TT BEST · AI FASTEST(그 주말 AI 난이도) · GAP(음수 = TT가 빠름).
class _TimeTrialTable extends StatelessWidget {
  const _TimeTrialTable({required this.rows});

  final List<AiTimeTrialRow> rows;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: context.palette.textMuted);
    return LayoutBuilder(builder: (context, constraints) {
      final roomy = constraints.maxWidth >= kCompactTableDefaultWidth;
      return _table(
        context,
        muted,
        roomy ? _timeColumnWidth : _narrowTimeColumnWidth,
        roomy ? _gapColumnWidth : _narrowGapColumnWidth,
      );
    });
  }

  Widget _table(BuildContext context, TextStyle muted, double timeWidth, double gapWidth) {
    return CompactTable<AiTimeTrialRow>(
      rows: rows,
      rowKey: (r) => ValueKey('ai-time-trial-${r.weekendId}'),
      columns: [
        CompactColumn(label: 'Grand Prix', flex: 3, cell: (r) => _TrackCell(name: r.trackName, countryCode: r.countryCode)),
        CompactColumn(
          label: 'TT Best',
          width: timeWidth,
          cell: (r) => Text(formatLapTime(r.timeTrialBestMs), style: kTabularStyle.copyWith(fontWeight: FontWeight.bold)),
        ),
        CompactColumn(
          label: 'AI Fastest',
          width: _aiTimeColumnWidth,
          compactHidden: true,
          cell: (r) => Text.rich(TextSpan(children: [
            TextSpan(text: formatLapTime(r.aiFastestQualiMs), style: kTabularStyle),
            TextSpan(text: '  AI ${r.aiDifficulty}', style: muted),
          ])),
        ),
        CompactColumn(
          label: 'Gap',
          width: gapWidth,
          cell: (r) => Text(
            signedPercent(r.gapPercent),
            style: kTabularStyle.copyWith(color: _gapColor(context, r.gapPercent), fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

class _TrackCell extends StatelessWidget {
  const _TrackCell({required this.name, required this.countryCode});

  final String name;
  final String? countryCode;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TrackFlag(countryCode: countryCode),
          const SizedBox(width: _flagGap),
          Flexible(
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      );
}

/// `P2 / P5`(나 / 팀메이트). 내 순위를 모르면 `-`.
class _VsCell extends StatelessWidget {
  const _VsCell({required this.mine, required this.theirs});

  final int? mine;
  final int? theirs;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: context.palette.textMuted);
    final mine = this.mine;
    if (mine == null) {
      return Text(kNoValueText, style: muted);
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PositionBadge(text: 'P$mine'),
          const SizedBox(width: _vsGap),
          Text('/ ${theirs == null ? kNoValueText : 'P$theirs'}', style: kTabularStyle.merge(muted)),
        ],
      ),
    );
  }
}

/// 팀메이트 대비 차이(초, 부호 포함). 음수 = 내가 빠름(초록), 양수 = 느림(빨강). 없으면 `-`.
class _GapCell extends StatelessWidget {
  const _GapCell({required this.ms});

  final int? ms;

  @override
  Widget build(BuildContext context) {
    final ms = this.ms;
    if (ms == null) {
      return Text(kNoValueText, style: TextStyle(color: context.palette.textMuted));
    }
    return Text(
      signedSeconds(ms),
      style: kTabularStyle.copyWith(color: _gapColor(context, ms.toDouble()), fontWeight: FontWeight.bold),
    );
  }
}

Color _gapColor(BuildContext context, double gap) {
  final palette = context.palette;
  if (gap < 0) {
    return palette.success;
  }
  return gap > 0 ? palette.danger : palette.textMuted;
}

/// `-0.312` · `+1.045`(초, 소수 셋째 자리). 순수 함수.
String signedSeconds(int ms) =>
    '${ms < 0 ? '-' : '+'}${(ms.abs() / _msPerSecond).toStringAsFixed(_secondsDigits)}';

/// `-0.42%` · `+1.10%`. 순수 함수.
String signedPercent(double percent) => '${percent < 0 ? '-' : '+'}${percent.abs().toStringAsFixed(_percentDigits)}%';
