import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../lap_detail/domain/lap_detail_display.dart';
import '../../lap_detail/presentation/car_tyres_card.dart';
import '../domain/session_detail_display.dart';
import '../domain/session_models.dart';
import 'engine_painter.dart';
import 'session_widgets.dart';

const String _emptyText = '이 세션에는 엔진 마모 데이터가 없어요.';
const String _diagramSemantics = '엔진 부품 마모 그림';

/// 그림과 목록을 옆으로 놓는 카드 안 폭.
const double _sideBySideWidth = 420;
const double _diagramGap = 20;
const double _swatchSize = 12;
const double _swatchGap = 8;
const double _swatchRadius = 2;
const double _legendRowPadding = 4;

/// Engine Wear 카드(docs/15 §11.3): 엔진 그림(부품별 마모 색) + ICE · Turbo Charger · MGU-H · MGU-K · Energy Store ·
/// Control Electronics · Gearbox · Engine Damage 목록(색 네모 + %). 색 단계는 타이어 마모와 같은 25/50/75%.
class EngineWearCard extends StatelessWidget {
  const EngineWearCard({super.key, required this.wear});

  final EngineWear? wear;

  @override
  Widget build(BuildContext context) {
    final value = wear;
    if (value == null) {
      return const SessionCard(title: 'Engine Wear', child: SessionEmptyText(_emptyText));
    }
    final palette = context.palette;
    Color colorOf(double? percent) => wearLevelColor(tyreWearLevelOf(percent), palette);
    final items = engineWearItems(value);
    final parts = [value.ice, value.turboCharger, value.mguH, value.mguK, value.energyStore, value.controlElectronics, value.gearbox];
    final diagram = Semantics(
      label: _diagramSemantics,
      child: CustomPaint(
        size: kEngineDiagramSize,
        painter: EnginePainter(partColors: [for (final p in parts) colorOf(p)], outlineColor: palette.textMuted),
      ),
    );
    final legend = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items) _LegendRow(label: item.label, value: item.value, color: colorOf(item.value)),
      ],
    );
    return SessionCard(
      title: 'Engine Wear',
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth >= _sideBySideWidth
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  diagram,
                  const SizedBox(width: _diagramGap),
                  Expanded(child: legend),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: diagram),
                  const SizedBox(height: _diagramGap),
                  legend,
                ],
              ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.label, required this.value, required this.color});

  final String label;
  final double? value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: ValueKey('engine-wear-$label'),
      padding: const EdgeInsets.symmetric(vertical: _legendRowPadding),
      child: Row(
        children: [
          Container(
            width: _swatchSize,
            height: _swatchSize,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(_swatchRadius)),
          ),
          const SizedBox(width: _swatchGap),
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
          Text(formatPercent(value), style: kTabularStyle.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
