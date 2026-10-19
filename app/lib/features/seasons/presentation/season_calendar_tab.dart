import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/compact_table.dart';
import '../../../core/widgets/track_flag.dart';
import '../../sessions/domain/session_detail_display.dart';
import '../../sessions/domain/session_display.dart';
import '../../sessions/presentation/session_widgets.dart';
import '../domain/season_display.dart';
import '../domain/season_models.dart';

const double _flagGap = 8;
const double _teamDotGap = 8;
const String _diffSeparator = ' / ';

/// 숫자 열 폭: 넓은 표에서는 머리글·값이 붙어 보이지 않게 넉넉히, 좁은 표([kCompactTableDefaultWidth] 미만)에서는 촘촘히.
const double _positionColumnWidth = 84;
const double _pointsColumnWidth = 100;
const double _diffColumnWidth = 150;
const double _narrowPositionColumnWidth = 52;
const double _narrowPointsColumnWidth = 72;

/// DIFF 열을 숨기는 표 폭(이보다 좁으면 이름 칸이 너무 좁아진다). 보통 데스크톱 폭(표 약 1000)에서는 보인다.
const double _diffHideBelowWidth = 880;

/// 그랑프리 세션 메뉴 폭·항목 사이 간격.
const double _sessionMenuWidth = 240;
const double _sessionMenuGap = 16;

/// 세션 메뉴가 표 위에서 묻히지 않도록: 강조색을 살짝 섞은 배경·강조색 테두리·그림자·넉넉한 항목 높이.
const double _sessionMenuTintAlpha = 0.10;
const double _sessionMenuBorderAlpha = 0.6;
const double _sessionMenuHoverAlpha = 0.18;
const double _sessionMenuElevation = 12;
const double _sessionMenuRadius = 10;
const double _sessionMenuItemHeight = 44;
const double _menuHintIconSize = 18;

/// Season 탭(F1Laps 시즌 표, docs/15 §12): 게임 캘린더 라운드 전부 한 줄씩.
/// GRAND PRIX · TEAM · SPRINT · RACE · PTS(합계) · QUALI · DIFF. 표 폭이 600 미만이면 TEAM·SPRINT를,
/// [_diffHideBelowWidth] 미만이면 DIFF를 숨겨 카드 폭을 넘지 않는다. SPRINT는 스프린트 주말이 하나라도 있을 때만.
/// RACE = 본 레이스(스프린트 주말이면 Race2). 이름을 누르면 그 주말 세션 메뉴(연습 … 레이스, 내 순위)가 열리고,
/// 고르면 그 세션으로 간다. 옛 서버(세션 목록 없음)면 본 레이스(없으면 첫 세션)로 바로 간다.
class SeasonCalendarTab extends StatelessWidget {
  const SeasonCalendarTab({super.key, required this.calendar, required this.totalPoints});

  final List<SeasonCalendarRound> calendar;

  /// PTS 머리글 괄호 안 시즌 내 합계(Standings 기준).
  final int? totalPoints;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) => _table(constraints.maxWidth >= kCompactTableDefaultWidth));
  }

  /// [roomy]면 넓은 숫자 열, 아니면 좁은 화면용 촘촘한 열.
  Widget _table(bool roomy) {
    final hasSprint = calendar.any((r) => r.isSprintWeekend);
    final positionWidth = roomy ? _positionColumnWidth : _narrowPositionColumnWidth;
    final pointsWidth = roomy ? _pointsColumnWidth : _narrowPointsColumnWidth;
    return CompactTable<SeasonCalendarRound>(
      rows: calendar,
      rowKey: (r) => ValueKey('season-calendar-${r.round}'),
      columns: [
        CompactColumn(label: 'Grand Prix', flex: 3, cell: (r) => _GrandPrixCell(round: r)),
        CompactColumn(label: 'Team', flex: 2, compactHidden: true, cell: (r) => _TeamCell(round: r)),
        if (hasSprint)
          CompactColumn(
            label: 'Sprint',
            width: positionWidth,
            compactHidden: true,
            cell: (r) => _PositionCell(position: r.sprintPosition),
          ),
        CompactColumn(label: 'Race', width: positionWidth, cell: (r) => _PositionCell(position: r.racePosition)),
        CompactColumn(
          label: calendarPointsHeader(totalPoints),
          width: pointsWidth,
          cell: (r) => Text(r.points == null ? '' : '${r.points}', style: kTabularStyle),
        ),
        CompactColumn(label: 'Quali', width: positionWidth, cell: (r) => _PositionCell(position: r.qualiPosition)),
        CompactColumn(
          label: 'Diff',
          width: _diffColumnWidth,
          hideBelowWidth: _diffHideBelowWidth,
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
    final tappable = round.sessions.isNotEmpty || target != null;
    final palette = context.palette;
    final nameText = Text(
      round.trackName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: tappable ? palette.link : palette.textPrimary,
        fontWeight: FontWeight.w600,
      ),
    );
    // 세션 메뉴가 열리는 이름에는 ▾를 붙여 누르면 메뉴가 열린다는 것을 보인다.
    final name = round.sessions.isEmpty
        ? nameText
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: nameText),
              Icon(Icons.arrow_drop_down, size: _menuHintIconSize, color: palette.link),
            ],
          );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TrackFlag(countryCode: round.countryCode),
        const SizedBox(width: _flagGap),
        Flexible(
          child: switch ((round.sessions.isEmpty, target)) {
            (false, _) => _SessionMenu(round: round, child: name),
            // 옛 서버: 본 레이스(없으면 첫 세션)로 바로. go + `from=season`: 뒤로 가기가 이 시즌으로 돌아온다.
            (true, final id?) => InkWell(
                key: ValueKey('season-calendar-link-${round.round}'),
                onTap: () => context.go(sessionLocation(id, fromSeason: true)),
                child: name,
              ),
            (true, null) => name,
          },
        ),
      ],
    );
  }
}

/// 그랑프리 이름에 붙은 세션 메뉴(연습 … 스프린트 슛아웃 · 스프린트 · 예선 · 레이스 + 내 순위).
class _SessionMenu extends StatelessWidget {
  const _SessionMenu({required this.round, required this.child});

  final SeasonCalendarRound round;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return MenuAnchor(
      // 메뉴 밖 누름이 아래 표까지 전달되지 않게(트랙 메뉴와 같은 이유).
      consumeOutsideTap: true,
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(
          Color.alphaBlend(AppColors.accent.withValues(alpha: _sessionMenuTintAlpha), palette.surface),
        ),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(_sessionMenuElevation),
        shadowColor: const WidgetStatePropertyAll(Colors.black),
        side: WidgetStatePropertyAll(
          BorderSide(color: AppColors.accent.withValues(alpha: _sessionMenuBorderAlpha)),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(_sessionMenuRadius)),
        ),
        minimumSize: const WidgetStatePropertyAll(Size(_sessionMenuWidth, 0)),
      ),
      menuChildren: [
        for (final session in round.sessions)
          MenuItemButton(
            key: ValueKey('season-calendar-session-${session.sessionId}'),
            onPressed: () => context.go(sessionLocation(session.sessionId, fromSeason: true)),
            style: ButtonStyle(
              minimumSize: const WidgetStatePropertyAll(Size.fromHeight(_sessionMenuItemHeight)),
              foregroundColor: WidgetStatePropertyAll(palette.textPrimary),
              overlayColor: WidgetStatePropertyAll(AppColors.accent.withValues(alpha: _sessionMenuHoverAlpha)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  sessionKindName(session.sessionKind, sprintWeekend: round.isSprintWeekend),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: _sessionMenuGap),
                switch (session.myPosition) {
                  final p? => PositionBadge(text: 'P$p'),
                  null => Text(kNoValueText, style: TextStyle(color: palette.textMuted)),
                },
              ],
            ),
          ),
      ],
      builder: (context, controller, _) => InkWell(
        key: ValueKey('season-calendar-link-${round.round}'),
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        child: child,
      ),
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

/// `P1` 알약. 기록이 없거나 순위를 모르면(0 이하) 비운다.
class _PositionCell extends StatelessWidget {
  const _PositionCell({required this.position});

  final int? position;

  @override
  Widget build(BuildContext context) {
    final value = knownPosition(position);
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
