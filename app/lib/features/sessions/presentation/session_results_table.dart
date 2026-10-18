import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/util/lap_time.dart';
import '../../../core/widgets/ai_badge.dart';
import '../../../core/widgets/team_color_bar.dart';
import '../domain/session_display.dart';
import '../domain/session_models.dart';
import 'tyre_stints_view.dart';

const double _rowHeight = 44;
const double _columnSpacing = 20;
const double _horizontalMargin = 16;
const double _driverMaxWidth = 220;

const _timeStyle = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

/// 한 칸을 그리는 데 필요한 값: 이 행, Time/Gap 기준 행, 레이스 여부.
class _CellData {
  const _CellData({required this.row, required this.reference, required this.isRace});

  final SessionResult row;
  final SessionResult? reference;
  final bool isRace;
}

/// 표의 한 열. [compactHidden]이 true인 열은 좁은 화면에서 숨긴다.
class _ColumnSpec {
  const _ColumnSpec(this.label, this.cell, {this.numeric = false, this.compactHidden = false});

  final String label;
  final Widget Function(_CellData data) cell;
  final bool numeric;
  final bool compactHidden;
}

final List<_ColumnSpec> _columns = [
  _ColumnSpec('Pos', (d) => Text('${d.row.position}'), numeric: true),
  _ColumnSpec('Driver', (d) => _DriverCell(row: d.row)),
  _ColumnSpec('Team', (d) => Text(d.row.teamName)),
  _ColumnSpec(
    'Grid',
    (d) => Text(d.row.gridPosition > 0 ? '${d.row.gridPosition}' : kNoValueText),
    numeric: true,
    compactHidden: true,
  ),
  _ColumnSpec('Laps', (d) => Text('${d.row.numLaps}'), numeric: true),
  _ColumnSpec(
    'Time/Gap',
    (d) => Text(timeOrGap(d.row, d.reference, isRace: d.isRace), style: _timeStyle),
  ),
  _ColumnSpec('Best', (d) => _BestLapCell(row: d.row)),
  _ColumnSpec('Tyres', (d) => TyreStintsView(stints: d.row.tyreStints), compactHidden: true),
  _ColumnSpec('Pits', (d) => Text('${d.row.numPitStops}'), numeric: true, compactHidden: true),
  _ColumnSpec(
    'Pen',
    (d) => Text(penaltyLabel(d.row.numPenalties, d.row.penaltiesTimeMs)),
    compactHidden: true,
  ),
  _ColumnSpec('Pts', (d) => Text('${d.row.points}'), numeric: true),
];

/// 세션 결과 표(docs/12 §8.3·§8.4). 위젯이 받은 폭이 [kSessionTableCompactWidth] 미만이면
/// Grid · Tyres · Pits · Pen 열을 숨기고, 그래도 넘치면 가로로 스크롤한다.
class SessionResultsTable extends StatelessWidget {
  const SessionResultsTable({super.key, required this.results, required this.isRace});

  final List<SessionResult> results;

  /// 레이스(`SessionType.Race`)이면 Time/Gap이 총 시간 기준, 아니면 베스트 랩 기준.
  final bool isRace;

  @override
  Widget build(BuildContext context) {
    final headingStyle = Theme.of(context).textTheme.labelLarge?.copyWith(color: context.palette.textMuted);
    final reference = referenceRow(results, isRace: isRace);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < kSessionTableCompactWidth;
        final columns = [
          for (final column in _columns)
            if (!(compact && column.compactHidden)) column,
        ];

        return Card(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: DataTable(
                headingTextStyle: headingStyle,
                headingRowHeight: _rowHeight,
                dataRowMinHeight: _rowHeight,
                dataRowMaxHeight: _rowHeight,
                columnSpacing: _columnSpacing,
                horizontalMargin: _horizontalMargin,
                columns: [
                  for (final column in columns) DataColumn(label: Text(column.label), numeric: column.numeric),
                ],
                rows: [
                  for (final row in results)
                    DataRow(
                      color: row.isPlayer ? const WidgetStatePropertyAll(AppColors.playerRow) : null,
                      cells: [
                        for (final column in columns)
                          DataCell(column.cell(_CellData(row: row, reference: reference, isRace: isRace))),
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 팀 색 막대 + 이름 + (AI이면) AI 배지. 내 차는 이름을 굵게 한다.
class _DriverCell extends StatelessWidget {
  const _DriverCell({required this.row});

  final SessionResult row;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _driverMaxWidth),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TeamColorBar(key: ValueKey('team-color-bar-${row.carIndex}'), colorHex: row.teamColor),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              row.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: row.isPlayer ? const TextStyle(fontWeight: FontWeight.bold) : null,
            ),
          ),
          if (row.isAiControlled) ...[
            const SizedBox(width: 6),
            const AiBadge(),
          ],
        ],
      ),
    );
  }
}

/// 베스트 랩. 세션 최고 랩이면 `fastestLap` 색으로 굵게 보인다.
class _BestLapCell extends StatelessWidget {
  const _BestLapCell({required this.row});

  final SessionResult row;

  @override
  Widget build(BuildContext context) {
    final bestLap = row.bestLapTimeMs;
    if (bestLap == null) {
      return const Text(kNoValueText);
    }
    final style = row.isFastestLap
        ? _timeStyle.copyWith(color: AppColors.fastestLap, fontWeight: FontWeight.bold)
        : _timeStyle;
    return Text(formatLapTime(bestLap), style: style);
  }
}
