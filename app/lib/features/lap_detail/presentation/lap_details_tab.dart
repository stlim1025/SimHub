import 'package:flutter/material.dart';

import '../domain/lap_detail_models.dart';
import 'car_detail_cards.dart';
import 'car_tyres_card.dart';
import 'lap_info_card.dart';
import 'lap_time_cards.dart';

/// 이 콘텐츠 폭(논리 px) 이상이면 2열, 미만이면 1열(docs/15 §2.3).
const double kLapDetailTwoColumnWidth = 900;

const double _cardGap = 16;

/// 위젯 사이에 간격을 끼운다.
List<Widget> _spaced(List<Widget> children, {Axis axis = Axis.vertical}) => [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) axis == Axis.vertical ? const SizedBox(height: _cardGap) : const SizedBox(width: _cardGap),
        children[i],
      ],
    ];

/// Lap Details 탭(D-46): 왼쪽 = Lap Time · Comparison · Lap Details, 오른쪽 = Car & Tyres · Damage,
/// 아래 = Conditions · Fuel · ERS 세 칸. 900px 미만이면 모두 한 줄로 쌓는다. 스냅샷이 없으면 차·손상·연료·ERS 대신 안내 한 장.
class LapDetailsTab extends StatelessWidget {
  const LapDetailsTab({super.key, required this.detail});

  final LapDetail detail;

  @override
  Widget build(BuildContext context) {
    final car = detail.car;
    final conditions = detail.conditions;
    final left = <Widget>[
      LapTimeCard(lap: detail.lap),
      ComparisonCard(detail: detail),
      LapInfoCard(detail: detail),
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
        Widget column(List<Widget> cards) =>
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _spaced(cards));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _spaced([Expanded(child: column(left)), Expanded(child: column(right))], axis: Axis.horizontal),
            ),
            if (bottom.isNotEmpty) ...[
              const SizedBox(height: _cardGap),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _spaced([for (final card in bottom) Expanded(child: card)], axis: Axis.horizontal),
              ),
            ],
          ],
        );
      },
    );
  }
}
