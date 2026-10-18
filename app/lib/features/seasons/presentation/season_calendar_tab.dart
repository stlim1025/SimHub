import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/compact_table.dart';
import '../../../core/widgets/track_flag.dart';
import '../../sessions/domain/session_display.dart';
import '../../sessions/presentation/session_widgets.dart';
import '../domain/season_display.dart';
import '../domain/season_models.dart';

const double _flagGap = 8;
const double _teamDotGap = 8;
const double _raceColumnWidth = 52;
const double _pointsColumnWidth = 72;
const double _qualiColumnWidth = 52;
const double _diffColumnWidth = 112;
const String _diffSeparator = ' / ';

/// Season 탭(F1Laps 시즌 표, docs/15 §12): 게임 캘린더 라운드 전부 한 줄씩.
/// GRAND PRIX · TEAM · RACE · PTS(합계) · QUALI · DIFF. 600px 미만이면 TEAM·DIFF를 숨긴다.
/// 이름을 누르면 본 레이스(없으면 그 주말 첫 세션) 결과로 간다 — 달리지 않은 라운드는 누를 수 없다.
class SeasonCalendarTab extends StatelessWidget {
  const SeasonCalendarTab({super.key, required this.calendar, required this.totalPoints});

  final List<SeasonCalendarRound> calendar;

  /// PTS 머리글 괄호 안 시즌 내 합계(Standings 기준).
  final int? totalPoints;

  @override
  Widget build(BuildContext context) {
    return CompactTable<SeasonCalendarRound>(
      rows: calendar,
      rowKey: (r) => ValueKey('season-calendar-${r.round}'),
      columns: [
        CompactColumn(label: 'Grand Prix', flex: 3, cell: (r) => _GrandPrixCell(round: r)),
        CompactColumn(label: 'Team', flex: 2, compactHidden: true, cell: (r) => _TeamCell(round: r)),
        CompactColumn(label: 'Race', width: _raceColumnWidth, cell: (r) => _PositionCell(position: r.racePosition)),
        CompactColumn(
          label: calendarPointsHeader(totalPoints),
          width: _pointsColumnWidth,
          cell: (r) => Text(r.points == null ? '' : '${r.points}', style: kTabularStyle),
        ),
        CompactColumn(label: 'Quali', width: _qualiColumnWidth, cell: (r) => _PositionCell(position: r.qualiPosition)),
        CompactColumn(
          label: 'Diff',
          width: _diffColumnWidth,
          compactHidden: true,
          cell: (r) => _DiffCell(race: r.raceAiDifficulty, quali: r.qualiAiDifficulty),
        ),
      ],
    );
  }
}

class _GrandPrixCell extends StatelessWidget {
  const _GrandPrixCell({required this.round});

  final SeasonCalendarRound round;

  @override
  Widget build(BuildContext context) {
    final target = calendarRoundTarget(round);
    final palette = context.palette;
    final name = Text(
      round.trackName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: target == null ? palette.textPrimary : palette.link,
        fontWeight: FontWeight.w600,
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TrackFlag(countryCode: round.countryCode),
        const SizedBox(width: _flagGap),
        Flexible(
          child: target == null
              ? name
              : InkWell(
                  key: ValueKey('season-calendar-link-${round.round}'),
                  // go + `from=season`: 세션 화면의 뒤로 가기가 이 시즌으로 돌아온다.
                  onTap: () => context.go(sessionLocation(target, fromSeason: true)),
                  child: name,
                ),
        ),
      ],
    );
  }
}

class _TeamCell extends StatelessWidget {
  const _TeamCell({required this.round});

  final SeasonCalendarRound round;

  @override
  Widget build(BuildContext context) {
    final team = round.myTeamName;
    if (team == null) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TeamDot(colorHex: round.myTeamColor),
        const SizedBox(width: _teamDotGap),
        Flexible(child: Text(team, maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

/// `P1` 알약. 기록이 없으면 비운다.
class _PositionCell extends StatelessWidget {
  const _PositionCell({required this.position});

  final int? position;

  @override
  Widget build(BuildContext context) {
    final value = position;
    return value == null
        ? const SizedBox.shrink()
        : FittedBox(fit: BoxFit.scaleDown, child: PositionBadge(text: 'P$value'));
  }
}

/// `100 / 105`(레이스 / 예선 AI 난이도). 모르는 쪽은 흐린 `-`.
class _DiffCell extends StatelessWidget {
  const _DiffCell({required this.race, required this.quali});

  final int? race;
  final int? quali;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: context.palette.textMuted);
    Widget part(int? value) => value == null ? Text(kNoValueText, style: muted) : PositionBadge(text: '$value');
    // 칸 폭보다 넓으면(큰 글자 설정 등) 넘치지 않게 줄인다.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [part(race), Text(_diffSeparator, style: muted), part(quali)],
      ),
    );
  }
}
