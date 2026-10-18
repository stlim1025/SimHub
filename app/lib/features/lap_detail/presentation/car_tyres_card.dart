import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/section_card.dart';
import '../../sessions/presentation/tyre_stints_view.dart';
import '../domain/lap_detail_display.dart';
import '../domain/lap_detail_models.dart';
import 'car_painter.dart';

const double _badgeColumnWidth = 72;
const double _badgeGap = 12;
const double _badgeHeight = 40;
const double _badgeRadius = 4;
const double _badgeBorderWidth = 1.5;
const EdgeInsets _badgePadding = EdgeInsets.symmetric(horizontal: 6, vertical: 2);
const double _badgeFontSize = 12;
const double _deltaFontSize = 11;
const double _compoundGap = 8;
const double _compoundCircleSize = 22;
const double _sectionGap = 12;
const String _unknownCompound = 'Unknown';

/// 차 그림 + 양옆 배지 영역의 전체 폭.
const double _diagramWidth = kCarDiagramWidth + 2 * (_badgeColumnWidth + _badgeGap);

/// 마모·손상 단계 → 색. 값이 없으면 테두리 색(중립).
Color wearLevelColor(TyreWearLevel level, AppPalette palette) => switch (level) {
      TyreWearLevel.low => AppColors.wearLow,
      TyreWearLevel.medium => AppColors.wearMedium,
      TyreWearLevel.high => AppColors.wearHigh,
      TyreWearLevel.critical => AppColors.wearCritical,
      TyreWearLevel.unknown => palette.border,
    };

/// Car & Tyres 카드(docs/15 §2.3): 위에서 본 차(바퀴 = 마모, 앞날개 = 손상) + 바퀴 옆 `31%` 배지와 기울임 `+4.0%`, 컴파운드 원 + "N랩째".
class CarTyresCard extends StatelessWidget {
  const CarTyresCard({super.key, required this.car});

  final CarSnapshot car;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final start = car.tyreWearStart;
    final end = car.tyreWearEnd;
    Color damageColor(double? damage) => wearLevelColor(tyreWearLevelOf(damage), palette);

    final painter = CarPainter(
      wheelColors: [for (final wear in (end ?? const WheelValues()).ordered) damageColor(wear)],
      frontWingLeftColor: damageColor(car.frontLeftWingDamage),
      frontWingRightColor: damageColor(car.frontRightWingDamage),
      rearWingColor: damageColor(car.rearWingDamage),
      bodyColor: palette.border,
      outlineColor: palette.textMuted,
      cockpitColor: palette.background,
    );
    final frontTop = kFrontWheelCenterFactor * kCarDiagramSize.height - _badgeHeight / 2;
    final rearTop = kRearWheelCenterFactor * kCarDiagramSize.height - _badgeHeight / 2;

    return SectionCard(
      title: 'Car & Tyres',
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: _diagramWidth,
              height: kCarDiagramSize.height,
              child: Stack(
                children: [
                  Positioned(
                    left: _badgeColumnWidth + _badgeGap,
                    top: 0,
                    child: CustomPaint(size: kCarDiagramSize, painter: painter),
                  ),
                  _badge('fl', frontTop, left: true, wear: end?.frontLeft, start: start?.frontLeft),
                  _badge('fr', frontTop, left: false, wear: end?.frontRight, start: start?.frontRight),
                  _badge('rl', rearTop, left: true, wear: end?.rearLeft, start: start?.rearLeft),
                  _badge('rr', rearTop, left: false, wear: end?.rearRight, start: start?.rearRight),
                ],
              ),
            ),
          ),
          if (car.visualTyreCompound != null || car.tyreAgeLaps != null) ...[
            const SizedBox(height: _sectionGap),
            _CompoundRow(car: car),
          ],
        ],
      ),
    );
  }

  static Widget _badge(String wheel, double top, {required bool left, required double? wear, required double? start}) =>
      Positioned(
        top: top,
        left: left ? 0 : null,
        right: left ? null : 0,
        width: _badgeColumnWidth,
        height: _badgeHeight,
        child: _WearBadge(key: ValueKey('wear-badge-$wheel'), wear: wear, start: start, alignEnd: left),
      );
}

/// 바퀴 옆 마모 배지: 단계 색 테두리 안의 `31%` + 아래 기울임 `+4.0%`(이 랩 동안 늘어난 마모, 시작 값이 있을 때만).
class _WearBadge extends StatelessWidget {
  const _WearBadge({super.key, required this.wear, required this.start, required this.alignEnd});

  final double? wear;
  final double? start;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final delta = formatWearDelta(start, wear);
    // 글자가 칸보다 넓으면(큰 글꼴 설정 등) 줄바꿈 대신 줄여서 그린다.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: alignEnd ? Alignment.topRight : Alignment.topLeft,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            padding: _badgePadding,
            decoration: BoxDecoration(
              color: palette.background,
              borderRadius: BorderRadius.circular(_badgeRadius),
              border: Border.all(color: wearLevelColor(tyreWearLevelOf(wear), palette), width: _badgeBorderWidth),
            ),
            child: Text(
              formatPercent(wear),
              maxLines: 1,
              style: TextStyle(fontSize: _badgeFontSize, fontWeight: FontWeight.bold, color: palette.textPrimary),
            ),
          ),
          if (delta != null)
            Text(
              delta,
              maxLines: 1,
              style: TextStyle(fontSize: _deltaFontSize, fontStyle: FontStyle.italic, color: palette.textMuted),
            ),
        ],
      ),
    );
  }
}

/// 컴파운드 원 + `Soft (C3) · 3랩째`.
class _CompoundRow extends StatelessWidget {
  const _CompoundRow({required this.car});

  final CarSnapshot car;

  @override
  Widget build(BuildContext context) {
    final name = visualCompoundName(car.visualTyreCompound) ?? _unknownCompound;
    final actual = actualCompoundLabel(car.actualTyreCompound);
    final age = car.tyreAgeLaps;
    final label = '$name${actual == null ? '' : ' ($actual)'}${age == null ? '' : ' · $age랩째'}';
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TyreCompoundCircle(compound: name, tooltip: name, size: _compoundCircleSize),
        const SizedBox(width: _compoundGap),
        Flexible(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
      ],
    );
  }
}
