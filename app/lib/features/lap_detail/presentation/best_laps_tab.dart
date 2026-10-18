import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/compact_table.dart';
import '../../../core/widgets/error_retry.dart';
import '../../laps/domain/lap_display.dart';
import '../../laps/domain/lap_models.dart';
import '../../laps/presentation/empty_laps_card.dart';
import '../../laps/presentation/lap_cells.dart';
import '../../sessions/domain/session_display.dart';
import '../application/lap_detail_providers.dart';
import '../domain/lap_detail_display.dart';
import '../domain/lap_detail_models.dart';

const double _rankColumnWidth = 32;
const String _noValidLapsText = '이 트랙에 유효 랩이 없습니다';

/// 순위가 붙은 랩 한 줄(1위 랩타임과 함께).
typedef _RankedLap = ({int rank, Lap lap, int leaderMs});

final List<CompactColumn<_RankedLap>> _columns = [
  CompactColumn(label: '#', width: _rankColumnWidth, cell: (row) => LapTextCell('${row.rank}')),
  CompactColumn(label: 'Team', flex: 3, cell: (row) => LapTeamCell(lap: row.lap)),
  CompactColumn(
    label: 'Time',
    flex: 3,
    cell: (row) => LapTimeCell(lapTimeMs: row.lap.lapTimeMs, isValid: row.lap.isValid),
  ),
  CompactColumn(
    label: 'Gap',
    flex: 2,
    cell: (row) => LapTextCell(row.rank == 1 ? kLapNoValueText : formatGapMs(row.lap.lapTimeMs - row.leaderMs)),
  ),
  CompactColumn(
    label: 'Mode',
    flex: 3,
    compactHidden: true,
    cell: (row) => LapTextCell(lapModeLabel(gameMode: row.lap.gameMode, sessionType: row.lap.sessionType)),
  ),
  CompactColumn(
    label: 'Date',
    flex: 3,
    compactHidden: true,
    cell: (row) => LapTextCell(formatLapDate(row.lap.setAt)),
  ),
];

/// Your Best Laps 탭(docs/15 §2.3): 이 트랙의 내 유효 랩 빠른 순 10개. # · TEAM · TIME · GAP(1위 대비) · MODE · DATE,
/// 지금 보는 랩은 강조, 행을 누르면 그 랩 상세. 600px 미만이면 MODE·DATE를 숨긴다.
class BestLapsTab extends ConsumerWidget {
  const BestLapsTab({super.key, required this.detail});

  final LapDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final best = ref.watch(bestLapsProvider(detail.trackId));
    return best.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => ErrorRetry(
        error: e,
        fallbackMessage: '최고 기록을 불러오지 못했어요.',
        onRetry: () => ref.invalidate(bestLapsProvider(detail.trackId)),
      ),
      data: (data) {
        if (data.laps.isEmpty) {
          return const EmptyLapsCard(message: _noValidLapsText);
        }
        final leaderMs = data.laps.first.lapTimeMs;
        final rows = [
          for (var i = 0; i < data.laps.length; i++) (rank: i + 1, lap: data.laps[i], leaderMs: leaderMs),
        ];
        return CompactTable<_RankedLap>(
          columns: _columns,
          rows: rows,
          compactWidth: kLapTableCompactWidth,
          rowKey: (row) => ValueKey('best-row-${row.lap.lapId}'),
          isHighlighted: (row) => row.lap.lapId == detail.lap.lapId,
          onRowTap: (row) => context.go(lapDetailLocation(row.lap.lapId)),
        );
      },
    );
  }
}
