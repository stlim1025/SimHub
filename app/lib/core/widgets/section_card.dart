import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 카드 안쪽 여백·제목 아래 간격(웹 대시보드처럼 넉넉하게, F1Laps 참고).
const double _cardPadding = 24;
const double _titleGap = 16;
const double _cardTitleFontSize = 20;
const double _cardTitleLetterSpacing = 0.6;

/// 제목 왼쪽 앰버 눈금(Cockpit HUD 계기판 라벨).
const double _titleTickWidth = 4;
const double _titleTickHeight = 18;
const double _titleTickGap = 10;

/// 카드 제목 글자(세션 상세·랩 상세·Telemetry App 카드 공통): 크고 굵게, 살짝 벌린 자간.
TextStyle? cardTitleStyle(BuildContext context) => Theme.of(context)
    .textTheme
    .titleLarge
    ?.copyWith(fontSize: _cardTitleFontSize, fontWeight: FontWeight.w700, letterSpacing: _cardTitleLetterSpacing);

/// 카드 제목 줄: 왼쪽 앰버 눈금 + 제목(넘치면 말줄임).
class CardTitle extends StatelessWidget {
  const CardTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: _titleTickWidth, height: _titleTickHeight, color: AppColors.accent),
        const SizedBox(width: _titleTickGap),
        Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: cardTitleStyle(context))),
      ],
    );
  }
}

/// 화면의 구획 카드: 제목(+오른쪽 보조 위젯)과 본문(Telemetry App·랩 상세 공통).
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;

  /// 제목줄 오른쪽에 둘 위젯(예: 새로고침 버튼).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(_cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: CardTitle(title)),
                ?trailing,
              ],
            ),
            const SizedBox(height: _titleGap),
            child,
          ],
        ),
      ),
    );
  }
}
