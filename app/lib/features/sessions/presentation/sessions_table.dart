import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/util/lap_time.dart';
import '../../../core/widgets/compact_table.dart';
import '../../../core/widgets/track_flag.dart';
import '../domain/session_board.dart' show kRaceSessionType;
import '../domain/session_detail_display.dart';
import '../domain/session_display.dart';
import '../domain/session_models.dart';
import 'session_widgets.dart';

const double _flagGap = 10;
const double _teamDotGap = 8;

/// 넓은 표에만 보이는 열 폭: 출발 순위·순위 변동·포인트, 최고 랩.
const double _gridColumnWidth = 80;
const double _changeColumnWidth = 80;
const double _pointsColumnWidth = 80;
const double _bestLapColumnWidth = 120;

final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');
final DateFormat _timeFormat = DateFormat('HH:mm');

/// Sessions 목록 표(docs/15 §11.2, D-54): TRACK(국기 + 트랙 / 세션 종류) · TEAM(팀 점 + 내 팀 / 모드 + 시즌) ·
/// RESULT(P 배지, 레이스는 강조) · TIME(날짜 / 시각). 600px 미만은 TEAM 아래줄·TIME 시각을 숨긴다. 행을 누르면 세션 상세.
/// 표 폭이 [kSessionTableWideWidth] 이상이면(넓은 화면 전체 폭) GRID(출발 순위) · CHANGE(레이스 순위 변동) · BEST LAP ·
/// PTS(레이스 포인트) 열을 더 보여 넓은 폭을 채운다.
class SessionsTable extends StatelessWidget {
  const SessionsTable({super.key, required this.items, this.footer});

  final List<SessionSummary> items;

  /// 카드 맨 아래(페이지 바).
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < kSessionTableCompactWidth;
        return CompactTable<SessionSummary>(
          columns: [
            CompactColumn(label: 'Track', flex: 5, cell: (s) => _TrackCell(session: s)),
            CompactColumn(label: 'Team', flex: 5, cell: (s) => _TeamCell(session: s, compact: compact)),
            CompactColumn(
              label: 'Grid',
              width: _gridColumnWidth,
              hideBelowWidth: kSessionTableWideWidth,
              cell: (s) => _PlainPosition(position: s.myGridPosition),
            ),
            CompactColumn(label: 'Result', flex: 2, cell: (s) => _ResultCell(session: s)),
            CompactColumn(
              label: 'Change',
              width: _changeColumnWidth,
              hideBelowWidth: kSessionTableWideWidth,
              cell: (s) => PositionChangeText(change: _raceChange(s)),
            ),
            CompactColumn(
              label: 'Best Lap',
              width: _bestLapColumnWidth,
              hideBelowWidth: kSessionTableWideWidth,
              cell: (s) => Text(
                s.myBestLapTimeMs == null ? kNoValueText : formatLapTime(s.myBestLapTimeMs!),
                style: kTabularStyle,
              ),
            ),
            CompactColumn(
              label: 'Pts',
              width: _pointsColumnWidth,
              hideBelowWidth: kSessionTableWideWidth,
              cell: (s) => Text(
                s.sessionType == kRaceSessionType && s.myPoints != null ? '${s.myPoints}' : kNoValueText,
                style: kTabularStyle,
              ),
            ),
            CompactColumn(label: 'Time', flex: 3, cell: (s) => _TimeCell(at: s.classifiedAt, compact: compact)),
          ],
          rows: items,
          compactWidth: kSessionTableCompactWidth,
          rowKey: (s) => ValueKey('session-row-${s.sessionId}'),
          onRowTap: (s) => context.go(sessionLocation(s.sessionId)),
          footer: footer,
        );
      },
    );
  }
}

/// 위 줄 + (있으면) 흐린 작은 아래 줄. 둘 다 한 줄 말줄임.
class _TwoLines extends StatelessWidget {
  const _TwoLines({required this.top, this.bottom});

  final Widget top;
  final String? bottom;

  @override
  Widget build(BuildContext context) {
    final text = bottom;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        top,
        if (text != null)
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.palette.textMuted),
          ),
      ],
    );
  }
}

class _TrackCell extends StatelessWidget {
  const _TrackCell({required this.session});

  final SessionSummary session;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        TrackFlag(countryCode: session.countryCode),
        const SizedBox(width: _flagGap),
        Expanded(
          child: _TwoLines(
            top: Text(
              session.trackName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.palette.link, fontWeight: FontWeight.w600),
            ),
            bottom: sessionKindName(session.sessionKind, sprintWeekend: session.isSprintWeekend),
          ),
        ),
      ],
    );
  }
}

class _TeamCell extends StatelessWidget {
  const _TeamCell({required this.session, required this.compact});

  final SessionSummary session;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final team = session.myTeam;
    final top = team == null
        ? const Text(kNoValueText)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TeamDot(colorHex: team.color),
              const SizedBox(width: _teamDotGap),
              Flexible(child: Text(team.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          );
    return _TwoLines(top: top, bottom: compact ? null : gameModeLine(session.gameMode, session.seasonNumber));
  }
}

/// 레이스의 순위 변동(출발 − 결과, + = 올라감). 레이스가 아니거나 순위를 모르면 null(`-`).
int? _raceChange(SessionSummary s) {
  final grid = s.myGridPosition;
  final finish = s.myPosition;
  return s.sessionType == kRaceSessionType && grid != null && grid > 0 && finish != null ? grid - finish : null;
}

/// 강조 없는 순위 글자(`P17`). 모르면 `-`.
class _PlainPosition extends StatelessWidget {
  const _PlainPosition({required this.position});

  final int? position;

  @override
  Widget build(BuildContext context) {
    final value = position;
    return Text(
      value == null || value <= 0 ? kNoValueText : 'P$value',
      style: kTabularStyle.copyWith(color: context.palette.textMuted),
    );
  }
}

class _ResultCell extends StatelessWidget {
  const _ResultCell({required this.session});

  final SessionSummary session;

  @override
  Widget build(BuildContext context) {
    final position = session.myPosition;
    return position == null
        ? const Text(kNoValueText)
        : PositionBadge(text: 'P$position', emphasized: session.sessionType == 'Race');
  }
}

class _TimeCell extends StatelessWidget {
  const _TimeCell({required this.at, required this.compact});

  final DateTime at;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final local = at.toLocal();
    return _TwoLines(
      top: Text(_dateFormat.format(local), maxLines: 1, overflow: TextOverflow.ellipsis, style: kTabularStyle),
      bottom: compact ? null : _timeFormat.format(local),
    );
  }
}
