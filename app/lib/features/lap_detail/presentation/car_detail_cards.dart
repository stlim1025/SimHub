import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/section_card.dart';
import '../../laps/domain/lap_display.dart';
import '../../laps/presentation/lap_cells.dart';
import '../domain/lap_detail_display.dart';
import '../domain/lap_detail_models.dart';
import 'detail_list.dart';

const double _weatherIconGap = 6;
const double _placeholderPadding = 32;
const String _noCarDataText = '이 랩에는 차량 데이터가 없어요';

/// 앞날개 좌·우: `- / 60%`. 둘 다 없거나 0이면 `-`.
String _frontWingText(CarSnapshot car) {
  final left = damageText(car.frontLeftWingDamage);
  final right = damageText(car.frontRightWingDamage);
  return left == kDetailNoValueText && right == kDetailNoValueText ? kDetailNoValueText : '$left / $right';
}

/// Damage 카드(docs/15 §2.3). 0은 `-`, 바퀴 값은 FL / FR / RL / RR.
class DamageCard extends StatelessWidget {
  const DamageCard({super.key, required this.car});

  final CarSnapshot car;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Damage',
      child: DetailList(items: [
        DetailItem('Front Wing (L/R)', text: _frontWingText(car)),
        DetailItem('Rear Wing', text: damageText(car.rearWingDamage)),
        DetailItem('Floor', text: damageText(car.floorDamage)),
        DetailItem('Diffuser', text: damageText(car.diffuserDamage)),
        DetailItem('Sidepod', text: damageText(car.sidepodDamage)),
        DetailItem('Gear Box', text: damageText(car.gearboxDamage)),
        DetailItem('Engine', text: damageText(car.engineDamage)),
        DetailItem('Tyre Wear', text: wheelValuesText(car.tyreWearEnd)),
        DetailItem('Brake Damage', text: wheelValuesText(car.brakeDamage)),
      ]),
    );
  }
}

/// Conditions 카드: 날씨(아이콘 + 이름) · 기온 · 노면 온도 · 비 예보.
class ConditionsCard extends StatelessWidget {
  const ConditionsCard({super.key, required this.conditions});

  final LapConditions conditions;

  @override
  Widget build(BuildContext context) {
    final weather = conditions.weather;
    return SectionCard(
      title: 'Conditions',
      child: DetailList(items: [
        if (weather == null)
          const DetailItem('Weather', text: kDetailNoValueText)
        else
          DetailItem(
            'Weather',
            value: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(weatherIconOf(weather), size: kWeatherIconSize, color: context.palette.textMuted),
                const SizedBox(width: _weatherIconGap),
                Flexible(child: Text(weatherLabel(weather)!, style: const TextStyle(fontWeight: FontWeight.w600))),
              ],
            ),
          ),
        DetailItem('Air temperature', text: formatTemperature(conditions.airTempC)),
        DetailItem('Track temperature', text: formatTemperature(conditions.trackTempC)),
        DetailItem('Rain forecast', text: formatRainForecast(conditions.rainForecastPercent)),
      ]),
    );
  }
}

/// Fuel 카드: 이 랩 사용량(시작 − 끝) · 남은 양 · 남은 랩.
class FuelCard extends StatelessWidget {
  const FuelCard({super.key, required this.car});

  final CarSnapshot car;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Fuel',
      child: DetailList(items: [
        DetailItem('Fuel used this lap', text: formatKg(fuelUsedKg(car))),
        DetailItem('Fuel remaining', text: formatKg(car.fuelEndKg)),
        DetailItem('Laps remaining', text: formatLapsRemaining(car.fuelRemainingLaps)),
      ]),
    );
  }
}

/// ERS 카드: 이 랩 사용량 · 남은 양(배터리 최대 4 MJ 기준 %).
class ErsCard extends StatelessWidget {
  const ErsCard({super.key, required this.car});

  final CarSnapshot car;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'ERS',
      child: DetailList(items: [
        DetailItem('ERS used this lap', text: formatOneDecimalPercent(ersUsedPercent(car))),
        DetailItem('ERS remaining', text: formatOneDecimalPercent(ersPercentOf(car.ersStoreEndJ))),
      ]),
    );
  }
}

/// 스냅샷 없는 랩(이전 Agent로 기록)의 안내 한 장 — 차·손상·연료·ERS 자리를 대신한다.
class NoCarDataCard extends StatelessWidget {
  const NoCarDataCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(_placeholderPadding),
        child: Center(
          child: Text(_noCarDataText, textAlign: TextAlign.center, style: TextStyle(color: context.palette.textMuted)),
        ),
      ),
    );
  }
}
