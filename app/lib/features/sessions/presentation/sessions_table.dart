import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/compact_table.dart';
import '../../../core/widgets/track_flag.dart';
import '../domain/session_detail_display.dart';
import '../domain/session_display.dart';
import '../domain/session_models.dart';
import 'session_widgets.dart';

const double _flagGap = 10;
const double _teamDotGap = 8;

final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');
final DateFormat _timeFormat = DateFormat('HH:mm');

/// Sessions 목록 표(docs/15 §11.2, D-54): TRACK(국기 + 트랙 / 세션 종류) · TEAM(팀 점 + 내 팀 / 모드 + 시즌) ·
/// RESULT(P 배지, 레이스는 강조) · TIME(날짜 / 시각). 600px 미만은 TEAM 아래줄·TIME 시각을 숨긴다. 행을 누르면 세션 상세.
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
            CompactColumn(label: 'Result', flex: 2, cell: (s) => _ResultCell(session: s)),
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
            bottom: sessionKindName(session.sessionKind),
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
