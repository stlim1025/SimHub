import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/compact_table.dart';
import '../../lap_detail/domain/lap_detail_display.dart';
import '../domain/lap_display.dart';
import '../domain/lap_models.dart';
import 'lap_cells.dart';

const double _weatherColumnWidth = 40;
const String _weatherHeaderTooltip = '날씨';

/// Laps 표의 열(docs/15 §2.1): TEAM · TIME · MODE · 날씨 · DATE. 600px 미만이면 MODE·날씨를 숨긴다.
final List<CompactColumn<Lap>> _columns = [
  CompactColumn(label: 'Team', flex: 3, cell: (lap) => LapTeamCell(lap: lap)),
  CompactColumn(label: 'Time', flex: 3, cell: (lap) => LapTimeCell(lapTimeMs: lap.lapTimeMs, isValid: lap.isValid)),
  CompactColumn(
    label: 'Mode',
    flex: 3,
    compactHidden: true,
    cell: (lap) => LapTextCell(lapModeLabel(gameMode: lap.gameMode, sessionType: lap.sessionType)),
  ),
  CompactColumn(
    label: _weatherHeaderTooltip,
    width: _weatherColumnWidth,
    compactHidden: true,
    alignment: Alignment.center,
    header: const _WeatherHeader(),
    cell: (lap) => LapWeatherCell(weather: lap.weather),
  ),
  CompactColumn(label: 'Date', flex: 3, cell: (lap) => LapTextCell(formatLapDate(lap.setAt))),
];

/// 한 트랙의 내 랩 표. 행 전체를 누르면 랩 상세(`/laps/:lapId`)로 간다.
class LapsTable extends StatelessWidget {
  const LapsTable({super.key, required this.laps, this.footer});

  final List<Lap> laps;

  /// 카드 맨 아래(페이지 바).
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return CompactTable<Lap>(
      columns: _columns,
      rows: laps,
      compactWidth: kLapTableCompactWidth,
      rowKey: (lap) => ValueKey('lap-row-${lap.lapId}'),
      onRowTap: (lap) => context.go(lapDetailLocation(lap.lapId)),
      footer: footer,
    );
  }
}

/// 날씨 열 머리글(F1Laps처럼 글자 대신 아이콘).
class _WeatherHeader extends StatelessWidget {
  const _WeatherHeader();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _weatherHeaderTooltip,
      child: Icon(Icons.wb_sunny_outlined, size: kWeatherIconSize, color: context.palette.textMuted),
    );
  }
}
