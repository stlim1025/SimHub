import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/util/lap_time.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/user_preferences.dart';
import '../../sessions/presentation/tyre_stints_view.dart';
import '../application/lap_detail_providers.dart';
import '../domain/lap_compare.dart';
import '../domain/lap_detail_display.dart';
import '../domain/lap_detail_models.dart';
import '../domain/lap_kpis.dart';

const EdgeInsets _stripPadding = EdgeInsets.symmetric(horizontal: 18, vertical: 14);

/// 넓은 배치: 랩 정체 칸 최대 폭, 랩 정체와 첫 칸 사이, 칸 안쪽 여백(왼쪽 세로선 뒤), 칸 최소 폭.
const double _identityMaxWidth = 200;
const double _identityGap = 22;
const EdgeInsets _cellPadding = EdgeInsets.only(left: 16, right: 8);
const double _wideCellMinWidth = 116;

/// 좁은 배치: 칸 최소 폭, 칸 사이 가로·세로 간격, 랩 정체 아래 구분선 높이.
const double _gridCellMinWidth = 88;
const double _gridSpacing = 12;
const double _gridRunSpacing = 14;
const double _narrowDividerHeight = 24;

/// 글자: 칸 이름(작은 대문자), 값, 아래 줄, 랩 정체 한 줄·랩타임, 줄 사이 간격.
const double _labelFontSize = 11;
const double _labelLetterSpacing = 1.5;
const double _valueFontSize = 26;
const double _valueLineHeight = 1.05;
const double _captionFontSize = 13;
const double _titleFontSize = 12;
const double _lapTimeFontSize = 24;
const double _lineGap = 2;

/// 값 줄 높이(정수 px로 두어 칸·띠 높이가 픽셀 경계에 맞는다 — 26px × 1.05 보다 살짝 크게).
const double _valueBoxHeight = 28;

/// 작은 글자(칸 이름·아래 줄·랩 정체 한 줄)의 줄 높이 — 본문 기본(약 1.4)보다 촘촘하게.
const double _smallLineHeight = 1.25;

/// 타이어 칸 컴파운드 원(어두운 바탕 + 컴파운드 색 고리 + 한 글자).
const double _tyreBadgeSize = 24;
const double _tyreRingWidth = 2.5;
const double _tyreLetterSize = 12;

const String _bestCaption = '이 랩이 PB';
const String _leaderboardBestCaption = '이 랩이 1위';
const String _noComparisonCaption = '비교 랩 없음';
const String _sectorLabelPrefix = 'S';
const String _topSpeedLabel = 'Top Speed';
const String _tyreLabel = 'Tyre';

const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

/// 좁은 배치의 열 수: [width]에 [_gridCellMinWidth] 칸이 몇 개 들어가는지 보고, 칸 [count]개를 줄마다 고르게 나눈다
/// (6칸이 4·5열에 들어가면 3열 × 2줄). 적어도 1열(순수 함수).
int kpiGridColumns(double width, int count) {
  if (count <= 0) {
    return 1;
  }
  final fit = math.min(count, math.max(1, ((width + _gridSpacing) / (_gridCellMinWidth + _gridSpacing)).floor()));
  final rows = (count / fit).ceil();
  return (count / rows).ceil();
}

/// 랩 상세 KPI 띠(미션 컨트롤, 모든 탭 공통 — 머리줄과 탭 막대 사이): 랩 정체(`Zandvoort · Race L23` + 랩타임) |
/// 비교 랩과의 차이 | S1·S2·S3(비교 섹터와의 차이) | 최고 속도 | 타이어(컴파운드 · 사용 랩 · 평균 마모).
/// 넓으면 한 줄(칸 사이 세로선), 좁으면 랩 정체 아래로 칸을 고르게 여러 줄로 흘린다.
/// 비교 안 함이면 비교 칸이 없고, 이 랩이 비교 기준의 최고 랩이면 랩타임이 보라색이다.
/// 최고 속도는 이 랩 트레이스에서 읽는다(불러오는 중·트레이스 없음이면 `—`, 속도 단위는 사용자 설정).
class LapKpiStrip extends ConsumerWidget {
  const LapKpiStrip({super.key, required this.detail, this.compare = LapCompareSelection.defaults});

  final LapDetail detail;

  /// 고른 비교(D-51). 다른 차 비교면 그 차 이름·랩타임을 여기서 읽는다.
  final LapCompareSelection compare;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lap = detail.lap;
    final trace = lap.hasTrace ? ref.watch(lapTraceProvider(lap.lapId)).valueOrNull : null;
    final units = ref.watch(authControllerProvider).valueOrNull?.preferences.units ?? UnitSystem.metric;
    final kpis = lapKpisOf(detail, compare);
    final identity = _Identity(title: lapKpiTitle(lap), lapTimeMs: kpis.lapTimeMs, best: kpis.isBest);
    final cells = [
      if (kpis.compareState != LapKpiCompareState.hidden) _compareCell(context, kpis),
      for (final sector in kpis.sectors) _sectorCell(context, sector),
      _topSpeedCell(formatKpiSpeed(lapTopSpeedKph(trace), units)),
      _tyreCell(kpis),
    ];
    return Card(
      key: const ValueKey('lap-kpi-strip'),
      child: Padding(
        padding: _stripPadding,
        child: LayoutBuilder(
          builder: (context, box) => box.maxWidth >= _identityMaxWidth + _identityGap + cells.length * _wideCellMinWidth
              ? _WideStrip(identity: identity, cells: cells)
              : _NarrowStrip(identity: identity, cells: cells, width: box.maxWidth),
        ),
      ),
    );
  }

  Widget _compareCell(BuildContext context, LapKpis kpis) {
    final palette = context.palette;
    final label = lapKpiCompareLabel(kpis.compareKind, otherCarName: compare.compareName);
    const key = ValueKey('lap-kpi-compare');
    return switch (kpis.compareState) {
      LapKpiCompareState.delta => _KpiCell(
          key: key,
          label: label,
          value: _ValueText(formatDeltaMs(kpis.deltaMs!), color: _deltaColor(palette, kpis.deltaMs!)),
          caption: formatLapTime(kpis.referenceMs!),
        ),
      LapKpiCompareState.itself => _KpiCell(
          key: key,
          label: label,
          value: _ValueText(formatDeltaMs(0), color: AppColors.fastestLap),
          caption: kpis.compareKind == LapCompareKind.leaderboard ? _leaderboardBestCaption : _bestCaption,
        ),
      _ => _KpiCell(
          key: key,
          label: label,
          value: _ValueText(kLapKpiNoValueText, color: palette.textMuted),
          caption: _noComparisonCaption,
        ),
    };
  }

  Widget _sectorCell(BuildContext context, LapKpiSector sector) {
    final delta = sector.deltaMs;
    return _KpiCell(
      key: ValueKey('lap-kpi-sector-${sector.number}'),
      label: '$_sectorLabelPrefix${sector.number}',
      value: _ValueText(formatKpiSectorTime(sector.timeMs)),
      caption: delta == null ? null : formatDeltaMs(delta),
      captionColor: delta == null ? null : _deltaColor(context.palette, delta),
    );
  }

  Widget _topSpeedCell(({String value, String unit}) speed) => _KpiCell(
        key: const ValueKey('lap-kpi-top-speed'),
        label: _topSpeedLabel,
        value: _ValueText(speed.value),
        caption: speed.value == kLapKpiNoValueText ? null : speed.unit,
      );

  Widget _tyreCell(LapKpis kpis) {
    final compound = kpis.tyreCompound;
    return _KpiCell(
      key: const ValueKey('lap-kpi-tyre'),
      label: _tyreLabel,
      value: compound == null ? const _ValueText(kLapKpiNoValueText) : _TyreBadge(compound: compound),
      caption: formatTyreKpiCaption(ageLaps: kpis.tyreAgeLaps, wearPercent: kpis.tyreWearPercent),
    );
  }

  /// 빠르면 초록, 느리면 빨강, 같으면 흐린 색(Comparison 카드와 같다).
  static Color _deltaColor(AppPalette palette, int deltaMs) => switch (deltaToneOf(deltaMs)) {
        DeltaTone.faster => palette.success,
        DeltaTone.slower => palette.danger,
        DeltaTone.even => palette.textMuted,
      };
}

/// 넓은 배치: 랩 정체 | 칸 | 칸 … 한 줄. 칸은 남은 폭을 똑같이 나누고 왼쪽에 세로선을 긋는다.
class _WideStrip extends StatelessWidget {
  const _WideStrip({required this.identity, required this.cells});

  final Widget identity;
  final List<Widget> cells;

  @override
  Widget build(BuildContext context) {
    final divider = BorderSide(color: context.palette.border);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: _identityMaxWidth), child: identity),
          const SizedBox(width: _identityGap),
          for (final cell in cells)
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(border: Border(left: divider)),
                child: Padding(padding: _cellPadding, child: cell),
              ),
            ),
        ],
      ),
    );
  }
}

/// 좁은 배치: 랩 정체, 구분선, 그 아래 칸을 [kpiGridColumns]열로 고르게 흘린다(넘치지 않게 칸 폭을 내림).
class _NarrowStrip extends StatelessWidget {
  const _NarrowStrip({required this.identity, required this.cells, required this.width});

  final Widget identity;
  final List<Widget> cells;
  final double width;

  @override
  Widget build(BuildContext context) {
    final columns = kpiGridColumns(width, cells.length);
    final cellWidth = math.max(0.0, ((width - _gridSpacing * (columns - 1)) / columns).floorToDouble());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        identity,
        const Divider(height: _narrowDividerHeight),
        Wrap(
          spacing: _gridSpacing,
          runSpacing: _gridRunSpacing,
          children: [for (final cell in cells) SizedBox(width: cellWidth, child: cell)],
        ),
      ],
    );
  }
}

/// 랩 정체: `Zandvoort · Race L23`(흐린 작은 글자) 아래 랩타임(최고 랩이면 보라색).
class _Identity extends StatelessWidget {
  const _Identity({required this.title, required this.lapTimeMs, required this.best});

  final String title;
  final int lapTimeMs;
  final bool best;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('lap-kpi-identity'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: _titleFontSize, height: _smallLineHeight, color: context.palette.textMuted),
        ),
        const SizedBox(height: _lineGap),
        Text(
          formatLapTime(lapTimeMs),
          key: const ValueKey('lap-kpi-lap-time'),
          maxLines: 1,
          style: TextStyle(
            fontSize: _lapTimeFontSize,
            fontWeight: FontWeight.w700,
            height: _valueLineHeight,
            color: best ? AppColors.fastestLap : null,
            fontFeatures: _tabular,
          ),
        ),
      ],
    );
  }
}

/// KPI 칸 하나: 작은 대문자 이름 / 큰 값(좁으면 줄여 맞춘다) / 아래 줄(없으면 빈 줄 — 칸 높이를 맞춘다).
class _KpiCell extends StatelessWidget {
  const _KpiCell({super.key, required this.label, required this.value, this.caption, this.captionColor});

  final String label;
  final Widget value;
  final String? caption;

  /// 아래 줄 색. null이면 흐린 색.
  final Color? captionColor;

  @override
  Widget build(BuildContext context) {
    final muted = context.palette.textMuted;
    // 위로 붙인다: 아래 줄에 한글이 섞여 줄 높이가 조금 달라져도 칸 이름·값의 높이가 칸마다 같다.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: _labelFontSize,
            fontWeight: FontWeight.w700,
            height: _smallLineHeight,
            letterSpacing: _labelLetterSpacing,
            color: muted,
          ),
        ),
        const SizedBox(height: _lineGap),
        SizedBox(
          height: _valueBoxHeight,
          child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: value),
        ),
        const SizedBox(height: _lineGap),
        Text(
          caption ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: _captionFontSize,
            height: _smallLineHeight,
            color: captionColor ?? muted,
            fontFeatures: _tabular,
          ),
        ),
      ],
    );
  }
}

/// 칸의 큰 값 글자.
class _ValueText extends StatelessWidget {
  const _ValueText(this.text, {this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
        text,
        maxLines: 1,
        softWrap: false,
        style: TextStyle(
          fontSize: _valueFontSize,
          fontWeight: FontWeight.w800,
          height: _valueLineHeight,
          color: color,
          fontFeatures: _tabular,
        ),
      );
}

/// 타이어 칸 컴파운드 원: 어두운 바탕 + 컴파운드 색 고리 + 한 글자(S·M·H·I·W). 마우스를 올리면 컴파운드 이름.
class _TyreBadge extends StatelessWidget {
  const _TyreBadge({required this.compound});

  final String compound;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Tooltip(
      message: compound,
      child: Container(
        key: const ValueKey('lap-kpi-tyre-badge'),
        width: _tyreBadgeSize,
        height: _tyreBadgeSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: palette.background,
          border: Border.all(color: tyreColorOf(compound), width: _tyreRingWidth),
        ),
        child: Text(
          tyreLetterOf(compound),
          style: TextStyle(
            fontSize: _tyreLetterSize,
            fontWeight: FontWeight.w800,
            height: 1,
            color: palette.textPrimary,
          ),
        ),
      ),
    );
  }
}
