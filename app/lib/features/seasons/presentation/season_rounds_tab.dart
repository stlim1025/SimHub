import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/stat.dart';
import '../../sessions/domain/session_display.dart';
import '../domain/season_display.dart';
import '../domain/season_models.dart';

const double _cardGap = 12;
const double _statSpacing = 32;
const double _chipSpacing = 8;

/// Season 탭(docs/12 §8.3): 라운드 목록. 한 라운드 = `R{n} · 트랙` + 날짜 + 우승자 · 내 주말 점수 + 세션 칩.
/// 칩(세션 라벨 + 내 결과)을 누르면 그 세션의 결과 화면으로 간다.
class SeasonRoundsTab extends StatelessWidget {
  const SeasonRoundsTab({super.key, required this.rounds});

  final List<SeasonRound> rounds;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final round in rounds) ...[
          _RoundCard(round: round),
          const SizedBox(height: _cardGap),
        ],
      ],
    );
  }
}

class _RoundCard extends StatelessWidget {
  const _RoundCard({required this.round});

  final SeasonRound round;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final winner = round.winnerName;
    final points = round.myPoints;
    return Card(
      key: ValueKey('season-round-${round.round}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('R${round.round} · ${round.trackName}', style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  formatSeasonDate(round.firstSessionAt),
                  style: theme.textTheme.bodySmall?.copyWith(color: context.palette.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: _statSpacing,
              runSpacing: 8,
              children: [
                Stat(label: '우승', value: winner ?? kNoValueText),
                Stat(label: '내 점수', value: points == null ? kNoValueText : '$points pts'),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: _chipSpacing,
              runSpacing: _chipSpacing,
              children: [for (final session in round.sessions) _SessionChip(session: session)],
            ),
          ],
        ),
      ),
    );
  }
}

/// 세션 칩: 세션 라벨(`Q1`, `R` …) + 내 결과(`P4`, `DNF`). 누르면 `/sessions/:id?from=season`(뒤로 가기가 이 시즌으로 돌아온다).
class _SessionChip extends StatelessWidget {
  const _SessionChip({required this.session});

  final SeasonRoundSession session;

  @override
  Widget build(BuildContext context) {
    final result = sessionChipResult(session.myPosition, session.myResultStatus);
    return ActionChip(
      // go + `from=season`: 주소가 곧 화면이고, 세션 화면의 뒤로 가기가 이 시즌으로 돌아온다.
      onPressed: () => context.go(sessionLocation(session.sessionId, fromSeason: true)),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(sessionKindLabel(session.sessionKind), style: const TextStyle(fontWeight: FontWeight.w600)),
          if (result != null) ...[
            const SizedBox(width: 6),
            Text(result, style: TextStyle(color: context.palette.textMuted)),
          ],
        ],
      ),
    );
  }
}
