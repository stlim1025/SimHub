import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/util/hex_color.dart';
import '../../../core/util/lap_time.dart';
import '../domain/lap_display.dart';
import '../domain/lap_models.dart';

const double _teamDotSize = 8;
const double _teamDotGap = 8;
const double _validIconSize = 14;
const double _validIconGap = 6;

/// 표의 날씨 아이콘 크기.
const double kWeatherIconSize = 18;

const String _validTooltip = '유효 랩';
const String _invalidTooltip = '무효 랩';

/// 랩타임 글자(눌러서 상세를 여는 값): 링크 색 굵게, 숫자 폭 고정.
TextStyle lapTimeLinkStyle(BuildContext context) => TextStyle(
      color: context.palette.link,
      fontWeight: FontWeight.bold,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

/// 날씨 → 아이콘. 모르는 값은 물음표.
IconData weatherIconOf(String weather) => switch (weather) {
      'Clear' => Icons.wb_sunny_outlined,
      'LightCloud' => Icons.wb_cloudy_outlined,
      'Overcast' => Icons.cloud_outlined,
      'LightRain' => Icons.grain,
      'HeavyRain' => Icons.water_drop_outlined,
      'Storm' => Icons.thunderstorm_outlined,
      _ => Icons.help_outline,
    };

/// TEAM 칸: 팀 색 점 + 팀 이름. 팀을 모르면(스냅샷 없음) `-`.
class LapTeamCell extends StatelessWidget {
  const LapTeamCell({super.key, required this.lap});

  final Lap lap;

  @override
  Widget build(BuildContext context) {
    final team = lap.team;
    if (team == null) {
      return const Text(kLapNoValueText);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          key: ValueKey('team-dot-${lap.lapId}'),
          width: _teamDotSize,
          height: _teamDotSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: parseHexColor(team.color, fallback: AppColors.textMuted),
          ),
        ),
        const SizedBox(width: _teamDotGap),
        Flexible(child: Text(team.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

/// TIME 칸: 링크 색 굵은 랩타임 + 유효(✓ 원)·무효(빨간 ✕) 아이콘과 툴팁.
class LapTimeCell extends StatelessWidget {
  const LapTimeCell({super.key, required this.lapTimeMs, required this.isValid});

  final int lapTimeMs;
  final bool isValid;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            formatLapTime(lapTimeMs),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: lapTimeLinkStyle(context),
          ),
        ),
        const SizedBox(width: _validIconGap),
        Tooltip(
          message: isValid ? _validTooltip : _invalidTooltip,
          child: Icon(
            isValid ? Icons.check_circle : Icons.cancel,
            size: _validIconSize,
            color: isValid ? palette.success : palette.danger,
          ),
        ),
      ],
    );
  }
}

/// 날씨 칸: 아이콘 + 이름 툴팁. 모르면 `-`.
class LapWeatherCell extends StatelessWidget {
  const LapWeatherCell({super.key, required this.weather});

  final String? weather;

  @override
  Widget build(BuildContext context) {
    final value = weather;
    if (value == null) {
      return const Text(kLapNoValueText);
    }
    return Tooltip(
      message: weatherLabel(value),
      child: Icon(weatherIconOf(value), size: kWeatherIconSize, color: context.palette.textMuted),
    );
  }
}

/// 한 줄 말줄임 글자 칸.
class LapTextCell extends StatelessWidget {
  const LapTextCell(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
}
