import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/util/hex_color.dart';
import '../domain/session_detail_display.dart';

const double _cardTitlePadding = 16;
const double _teamDotSize = 8;
const double _teamDotGap = 8;
const double _arrowSize = 14;
const double _badgeRadius = 999;
const EdgeInsets _badgePadding = EdgeInsets.symmetric(horizontal: 8, vertical: 2);
const double _badgeFontSize = 12;

/// 내 차를 가리키는 이름(F1Laps "You", docs/15 §11.3).
const String kPlayerName = 'You';

/// 숫자 폭을 맞춘 글자.
const TextStyle kTabularStyle = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

/// 세션 상세 카드: 제목 + 본문. [padded]가 false면 본문을 가장자리까지(표).
class SessionCard extends StatelessWidget {
  const SessionCard({super.key, required this.title, required this.child, this.padded = true});

  final String title;
  final Widget child;
  final bool padded;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(_cardTitlePadding, _cardTitlePadding, _cardTitlePadding, 12),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          if (padded)
            Padding(
              padding: const EdgeInsets.fromLTRB(_cardTitlePadding, 0, _cardTitlePadding, _cardTitlePadding),
              child: child,
            )
          else
            child,
        ],
      ),
    );
  }
}

/// 카드에 데이터가 없을 때의 안내(카드는 숨기지 않는다, docs/15 §11.3).
class SessionEmptyText extends StatelessWidget {
  const SessionEmptyText(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(message, style: TextStyle(color: context.palette.textMuted)),
      );
}

/// 팀 색 점. 잘못된 색이면 `textMuted`.
class TeamDot extends StatelessWidget {
  const TeamDot({super.key, required this.colorHex});

  final String? colorHex;

  @override
  Widget build(BuildContext context) => Container(
        width: _teamDotSize,
        height: _teamDotSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: parseHexColor(colorHex, fallback: AppColors.textMuted),
        ),
      );
}

/// 팀 색 점 + 이름(한 줄 말줄임). 내 차는 `You` 굵게.
class DriverNameCell extends StatelessWidget {
  const DriverNameCell({super.key, required this.name, required this.teamColor, required this.isPlayer});

  final String name;
  final String? teamColor;
  final bool isPlayer;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TeamDot(colorHex: teamColor),
        const SizedBox(width: _teamDotGap),
        Flexible(
          child: Text(
            isPlayer ? kPlayerName : name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: isPlayer ? const TextStyle(fontWeight: FontWeight.bold) : null,
          ),
        ),
      ],
    );
  }
}

/// 순위 변동 `↑1`(초록) · `↓9`(빨강) · `-`. 값이 없으면 `-`.
class PositionChangeText extends StatelessWidget {
  const PositionChangeText({super.key, required this.change});

  final int? change;

  @override
  Widget build(BuildContext context) {
    final value = positionChangeOf(change);
    if (value == null || value.trend == PositionTrend.same) {
      return Text(value?.text ?? '-', style: TextStyle(color: context.palette.textMuted));
    }
    final up = value.trend == PositionTrend.up;
    final color = up ? context.palette.success : context.palette.danger;
    return Semantics(
      label: '${up ? '올라감' : '내려감'} ${value.text}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(up ? Icons.arrow_upward : Icons.arrow_downward, size: _arrowSize, color: color),
          Text(value.text, style: kTabularStyle.copyWith(color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// `P8` 알약 배지(RESULT·POSITION 칸). [emphasized]면 강조색 채움(레이스, D-54).
class PositionBadge extends StatelessWidget {
  const PositionBadge({super.key, required this.text, this.emphasized = false});

  final String text;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: _badgePadding,
      decoration: BoxDecoration(
        color: emphasized ? AppColors.accent : palette.tableHeader,
        borderRadius: BorderRadius.circular(_badgeRadius),
        border: Border.all(color: emphasized ? AppColors.accent : palette.border),
      ),
      child: Text(
        text,
        style: kTabularStyle.copyWith(
          fontSize: _badgeFontSize,
          fontWeight: FontWeight.bold,
          color: emphasized ? AppColors.onAccent : palette.textPrimary,
        ),
      ),
    );
  }
}
