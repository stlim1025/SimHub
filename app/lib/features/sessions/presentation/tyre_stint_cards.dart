import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/util/lap_time.dart';
import '../../lap_detail/domain/telemetry_math.dart';
import '../domain/session_detail_display.dart';
import '../domain/session_models.dart';
import 'session_widgets.dart';
import 'stint_line_chart.dart';
import 'tyre_stints_view.dart';

const String _tyreLifeTitle = 'Tyre Stints: Tyre Life Remaining';
const String _lapTimesTitle = 'Tyre Stints: Lap Times';
const String _tyreLifeEmpty = '이 세션에는 타이어 마모 데이터가 없어요.';
const String _lapTimesEmpty = '이 세션에는 스틴트 랩타임 데이터가 없어요.';
const String _xTitle = 'Lap in stint';
const String _hardCompound = 'Hard';

/// 선 색: 컴파운드 색. 흰 Hard는 밝은 표면에서 안 보이므로 테마 글자색으로 그린다.
Color stintLineColor(String compound, AppPalette palette) =>
    compound == _hardCompound ? palette.textPrimary : tyreColorOf(compound);

List<StintChartSeries> _seriesOf(List<StintLine> lines, AppPalette palette) => [
      for (final line in lines)
        StintChartSeries(
          label: line.label,
          color: stintLineColor(line.compound, palette),
          points: line.points,
          startLap: line.startLap,
          compound: line.compound,
        ),
    ];

/// Tyre Stints: Tyre Life Remaining 카드(docs/15 §11.3): x = 스틴트 안 랩, y = 100 − 평균 마모(%).
class TyreLifeCard extends StatelessWidget {
  const TyreLifeCard({super.key, required this.stints});

  final List<SessionTyreStint> stints;

  @override
  Widget build(BuildContext context) {
    final lines = tyreLifeLines(stints);
    if (lines.isEmpty) {
      return const SessionCard(title: _tyreLifeTitle, child: SessionEmptyText(_tyreLifeEmpty));
    }
    final range = tyreLifeRange(lines);
    return SessionCard(
      title: _tyreLifeTitle,
      child: StintLineChart(
        series: _seriesOf(lines, context.palette),
        maxX: stintChartMaxX(lines),
        range: ValueRange(range.min, range.max),
        formatY: (value) => '${value.round()}',
        yTitle: 'Tyre life remaining (%)',
        xTitle: _xTitle,
        semanticLabel: '타이어 수명 그래프',
      ),
    );
  }
}

/// Tyre Stints: Lap Times 카드(docs/15 §11.3): x = 스틴트 안 랩, y = 랩타임.
class StintLapTimesCard extends StatelessWidget {
  const StintLapTimesCard({super.key, required this.stints});

  final List<SessionTyreStint> stints;

  @override
  Widget build(BuildContext context) {
    final lines = lapTimeLines(stints);
    if (lines.isEmpty) {
      return const SessionCard(title: _lapTimesTitle, child: SessionEmptyText(_lapTimesEmpty));
    }
    final range = lapTimeRange(lines);
    return SessionCard(
      title: _lapTimesTitle,
      child: StintLineChart(
        series: _seriesOf(lines, context.palette),
        maxX: stintChartMaxX(lines),
        range: ValueRange(range.min, range.max),
        formatY: (value) => formatLapTime(value.round()),
        yTitle: 'Lap time',
        xTitle: _xTitle,
        semanticLabel: '스틴트 랩타임 그래프',
      ),
    );
  }
}
