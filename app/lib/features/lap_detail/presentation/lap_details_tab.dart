import 'package:flutter/material.dart';

import '../../../core/layout/equal_height.dart';

import '../domain/lap_compare.dart';
import '../domain/lap_detail_models.dart';
import 'car_detail_cards.dart';
import 'car_tyres_card.dart';
import 'driver_assists_card.dart';
import 'lap_info_card.dart';
import 'lap_time_cards.dart';

/// 이 콘텐츠 폭(논리 px) 이상이면 2열, 미만이면 1열(docs/15 §2.3).
const double kLapDetailTwoColumnWidth = 900;

const double _cardGap = 16;

/// 위젯 사이에 세로 간격을 끼운다.
List<Widget> _spaced(List<Widget> children) => [
  for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: _cardGap), children[i]],
];

/// Lap Details 탭(D-46, D-51): 왼쪽 = Lap Time · Comparison · Lap Details · Driver Assists(있을 때), 오른쪽 = Car & Tyres · Damage,
/// 아래 = Conditions · Fuel · ERS 세 칸. 900px 미만이면 모두 한 줄로 쌓는다. 스냅샷이 없으면 차·손상·연료·ERS 대신 안내 한 장.
class LapDetailsTab extends StatelessWidget {
  const LapDetailsTab({super.key, required this.detail, this.compare = LapCompareSelection.defaults});

  final LapDetail detail;

  /// 고른 비교(D-51). "비교 안 함"이면 Comparison 카드를 숨긴다.
  final LapCompareSelection compare;

  @override
  Widget build(BuildContext context) {
    final car = detail.car;
    final conditions = detail.conditions;
    final assists = detail.assists;
    final left = <Widget>[
      LapTimeCard(lap: detail.lap),
      if (compare.kind != LapCompareKind.none) ComparisonCard(detail: detail, compare: compare),
      LapInfoCard(detail: detail),
      if (assists != null) DriverAssistsCard(assists: assists),
    ];
    final right = car == null ? const <Widget>[NoCarDataCard()] : [CarTyresCard(car: car), DamageCard(car: car)];
    final bottom = <Widget>[
      if (conditions != null) ConditionsCard(conditions: conditions),
      if (car != null) ...[FuelCard(car: car), ErsCard(car: car)],
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < kLapDetailTwoColumnWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _spaced([...left, ...right, ...bottom]),
          );
        }
        // 두 열은 같은 폭, 짧은 열의 마지막 카드를 늘려 바닥을 맞춘다. 아래 칸들도 같은 높이(docs/15 §2.3).
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EqualHeightRow(
              gap: _cardGap,
              children: [
                FillColumn(gap: _cardGap, children: left),
                FillColumn(gap: _cardGap, children: right),
              ],
            ),
            if (bottom.isNotEmpty) ...[
              const SizedBox(height: _cardGap),
              EqualHeightRow(gap: _cardGap, children: bottom),
            ],
          ],
        );
      },
    );
  }
}
