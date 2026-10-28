import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../domain/race_review.dart';
import 'session_widgets.dart';

const String _title = 'Race Review';
const double _sectionGap = 14;
const double _lineGap = 4;
const double _gradeGap = 8;

const Map<ReviewGrade, String> _gradeText = {
  ReviewGrade.good: '좋음',
  ReviewGrade.fair: '보통',
  ReviewGrade.poor: '아쉬움',
};

/// 레이스 총평 카드: 한 줄 총평, 항목(페이스·전략·타이어·배터리)마다 평가와 관찰 → 할 것.
class RaceReviewCard extends StatelessWidget {
  const RaceReviewCard({super.key, required this.review});

  final RaceReview review;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final sections = raceReviewSections(review);
    final summary = raceReviewSummary(sections);
    Color gradeColor(ReviewGrade grade) => switch (grade) {
          ReviewGrade.good => palette.success,
          ReviewGrade.fair => palette.textMuted,
          ReviewGrade.poor => palette.danger,
        };
    return SessionCard(
      key: const ValueKey('race-review'),
      title: _title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (summary != null)
            Text(summary, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          for (final s in sections) ...[
            const SizedBox(height: _sectionGap),
            Row(
              children: [
                Text(s.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(width: _gradeGap),
                Text(
                  _gradeText[s.section.grade]!,
                  key: ValueKey('race-review-grade-${s.title}'),
                  style: TextStyle(color: gradeColor(s.section.grade), fontWeight: FontWeight.w700),
                ),
              ],
            ),
            for (final line in s.section.lines)
              Padding(padding: const EdgeInsets.only(top: _lineGap), child: Text(line)),
          ],
        ],
      ),
    );
  }
}
