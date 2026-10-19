import 'package:flutter/material.dart';

/// 카드 안쪽 여백·제목 아래 간격(웹 대시보드처럼 넉넉하게, F1Laps 참고).
const double _cardPadding = 24;
const double _titleGap = 16;
const double _cardTitleFontSize = 20;

/// 카드 제목 글자(세션 상세·랩 상세·Telemetry App 카드 공통): 크고 굵게.
TextStyle? cardTitleStyle(BuildContext context) => Theme.of(context)
    .textTheme
    .titleLarge
    ?.copyWith(fontSize: _cardTitleFontSize, fontWeight: FontWeight.w700);

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
                Expanded(child: Text(title, style: cardTitleStyle(context))),
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
