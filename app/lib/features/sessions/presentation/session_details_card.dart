import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/util/lap_time.dart';
import '../../lap_detail/domain/lap_detail_display.dart';
import '../../lap_detail/presentation/detail_list.dart';
import '../../laps/domain/lap_display.dart';
import '../../laps/presentation/lap_cells.dart';
import '../../seasons/domain/season_display.dart';
import '../domain/session_detail_display.dart';
import '../domain/session_display.dart';
import '../domain/session_models.dart';
import 'session_widgets.dart';
import 'setup_dialog.dart';

const String _viewSetupLabel = 'View Setup';
const double _chevronSize = 18;
const double _iconGap = 6;
const double _qualifyingGap = 24;
const double _qualifyingBottomGap = 8;

final DateFormat _dateFormat = DateFormat('yyyy-MM-dd HH:mm');

/// Details 카드(docs/15 §11.3): (예선이면) Q1·Q2·Q3 내 순위 + Best Lap Time(→ 랩 상세) · Setup · Difficulty · Conditions ·
/// Team · Session Type · Game Mode · (시즌이면) Round(→ 시즌) · Date.
class SessionDetailsCard extends StatelessWidget {
  const SessionDetailsCard({super.key, required this.detail});

  final SessionDetail detail;

  @override
  Widget build(BuildContext context) {
    final header = detail.header;
    final seasonId = header.seasonId;
    final round = header.round;
    final setup = detail.setup;
    return SessionCard(
      title: 'Details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (detail.qualifyingPositions.isNotEmpty) ...[
            _QualifyingPositions(positions: detail.qualifyingPositions),
            const SizedBox(height: _qualifyingBottomGap),
            const Divider(height: 1),
          ],
          DetailList(items: [
            DetailItem('Best Lap Time', value: _BestLapValue(detail: detail)),
            setup == null
                ? const DetailItem('Setup', text: kNoValueText)
                : DetailItem('Setup', value: _LinkValue(text: _viewSetupLabel, onTap: () => showSetupDialog(context, setup))),
            DetailItem('Difficulty', text: header.aiDifficulty > 0 ? '${header.aiDifficulty}' : kNoValueText),
            DetailItem('Conditions', value: _ConditionsValue(weather: header.weather)),
            DetailItem('Team', value: _TeamValue(header: header)),
            DetailItem('Session Type', text: sessionKindName(header.sessionKind, sprintWeekend: header.isSprintWeekend)),
            DetailItem('Game Mode', text: gameModeLine(header.gameMode, header.seasonNumber)),
            if (seasonId != null && round != null)
              DetailItem('Round', value: _LinkValue(text: 'R$round', onTap: () => context.go(seasonLocation(seasonId)))),
            DetailItem('Date', text: _dateFormat.format(header.classifiedAt.toLocal())),
          ]),
        ],
      ),
    );
  }
}

/// 링크 색 글자 + ›. 누르면 [onTap].
class _LinkValue extends StatelessWidget {
  const _LinkValue({required this.text, required this.onTap, this.style});

  final String text;
  final VoidCallback onTap;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final color = context.palette.link;
    return InkWell(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: (style ?? const TextStyle()).copyWith(color: color, fontWeight: FontWeight.bold),
            ),
          ),
          Icon(Icons.chevron_right, size: _chevronSize, color: color),
        ],
      ),
    );
  }
}

/// 세션 최고 랩. 랩 Id가 있으면 랩 상세로 가는 링크, 없으면 글자만(옛 서버는 헤더의 `myBestLapTimeMs`).
class _BestLapValue extends StatelessWidget {
  const _BestLapValue({required this.detail});

  final SessionDetail detail;

  @override
  Widget build(BuildContext context) {
    final best = detail.myBestLap;
    final lapId = best?.lapId;
    final time = best?.lapTimeMs ?? detail.header.myBestLapTimeMs;
    if (time == null) {
      return const Text(kNoValueText);
    }
    if (lapId == null) {
      return Text(formatLapTime(time), style: kTabularStyle.copyWith(fontWeight: FontWeight.w600));
    }
    return _LinkValue(
      text: formatLapTime(time),
      style: kTabularStyle,
      onTap: () => context.go(lapDetailLocation(lapId)),
    );
  }
}

class _ConditionsValue extends StatelessWidget {
  const _ConditionsValue({required this.weather});

  final String? weather;

  @override
  Widget build(BuildContext context) {
    final value = weather;
    if (value == null) {
      return const Text(kNoValueText);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(weatherIconOf(value), size: kWeatherIconSize, color: context.palette.textMuted),
        const SizedBox(width: _iconGap),
        Flexible(child: Text(weatherLabel(value)!, style: const TextStyle(fontWeight: FontWeight.w600))),
      ],
    );
  }
}

class _TeamValue extends StatelessWidget {
  const _TeamValue({required this.header});

  final SessionDetailHeader header;

  @override
  Widget build(BuildContext context) {
    final team = header.myTeam;
    if (team == null) {
      return const Text(kNoValueText);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TeamDot(colorHex: team.color),
        const SizedBox(width: _iconGap),
        Flexible(
          child: Text(team.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

/// `Q1 P6 · Q2 P10 · Q3 P8`. 세션 Id가 있으면 그 예선 세션으로 간다.
class _QualifyingPositions extends StatelessWidget {
  const _QualifyingPositions({required this.positions});

  final List<QualifyingPosition> positions;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodySmall?.copyWith(color: context.palette.textMuted);
    return Wrap(
      spacing: _qualifyingGap,
      runSpacing: _qualifyingBottomGap,
      children: [
        for (final q in positions)
          InkWell(
            key: ValueKey('qualifying-${q.label}'),
            onTap: q.sessionId == null ? null : () => context.go(sessionLocation(q.sessionId!)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(q.label, style: muted),
                Text(
                  switch (knownPosition(q.position)) { final p? => 'P$p', null => kNoValueText },
                  style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
