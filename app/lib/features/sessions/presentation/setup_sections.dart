import 'package:flutter/material.dart';

import '../../../core/layout/equal_height.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/section_card.dart';
import '../../lap_detail/presentation/detail_list.dart';
import '../domain/setup_display.dart';
import '../domain/setup_ranges.dart';

const double _cardGap = 20;
const double _metaPadding = 20;
const double _metaSpacing = 32;
const double _metaRunSpacing = 12;
const double _metaLabelGap = 2;

/// 콘텐츠 폭이 이 값 이상이면 셋업 카드 3열.
const double kSetupThreeColumnWidth = 1100;

/// 콘텐츠 폭이 이 값 이상이면 셋업 카드 2열(미만은 1열).
const double kSetupTwoColumnWidth = 640;

const int _threeColumns = 3;
const int _twoColumns = 2;
const int _oneColumn = 1;

/// 콘텐츠 폭 → 셋업 카드 열 수(순수 함수).
int setupGridColumns(double width) => width >= kSetupThreeColumnWidth
    ? _threeColumns
    : width >= kSetupTwoColumnWidth
        ? _twoColumns
        : _oneColumn;

/// 셋업 화면 머리의 요약 카드(F1Laps 셋업 페이지의 Team · Session · Lap time … 정보 줄). 좁으면 여러 줄로 감긴다.
/// 세션 셋업 화면과 셋업 모음(Setups) 상세 화면이 같이 쓴다.
class SetupMetaCard extends StatelessWidget {
  const SetupMetaCard({super.key, required this.items});

  final List<SetupMetaItem> items;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(_metaPadding),
        child: Wrap(spacing: _metaSpacing, runSpacing: _metaRunSpacing, children: items),
      ),
    );
  }
}

/// 요약 한 칸: 위 흐린 이름표 + 아래 굵은 값. `setup-meta-{이름표}` 키를 갖는다.
class SetupMetaItem extends StatelessWidget {
  SetupMetaItem({required this.label, required this.value}) : super(key: ValueKey('setup-meta-$label'));

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: textTheme.bodySmall?.copyWith(color: context.palette.textMuted)),
        const SizedBox(height: _metaLabelGap),
        DefaultTextStyle.merge(style: const TextStyle(fontWeight: FontWeight.bold), child: value),
      ],
    );
  }
}

/// 셋업 묶음 카드 격자: 넓으면 3열, 중간 2열, 좁으면 1열. 한 줄의 카드는 같은 폭·같은 높이.
class SetupGrid extends StatelessWidget {
  const SetupGrid({super.key, required this.groups});

  final List<SetupGroup> groups;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = setupGridColumns(constraints.maxWidth);
        final cards = [for (final group in groups) SetupGroupCard(group: group)];
        if (columns == _oneColumn) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(height: _cardGap),
                cards[i],
              ],
            ],
          );
        }
        final rows = <Widget>[
          for (var start = 0; start < cards.length; start += columns)
            EqualHeightRow(
              gap: _cardGap,
              children: [
                for (var i = start; i < start + columns; i++) i < cards.length ? cards[i] : const SizedBox.shrink(),
              ],
            ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: _cardGap),
              rows[i],
            ],
          ],
        );
      },
    );
  }
}

/// 셋업 묶음 하나: 카드 제목 + 이름표(왼쪽) · 범위 막대 · 값(오른쪽, 굵게) 줄 목록(F1Laps 셋업 페이지 모양).
/// 범위를 아는 항목만 막대를 그린다([setupBarFraction]). `setup-group-{제목}` 키를 갖는다.
class SetupGroupCard extends StatelessWidget {
  SetupGroupCard({required this.group}) : super(key: ValueKey('setup-group-${group.title}'));

  final SetupGroup group;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: group.title,
      child: DetailList(
        items: [
          for (final item in group.items)
            switch (setupBarFraction(item.label, item.value)) {
              final double fraction => DetailItem(item.label, value: _BarValue(fraction: fraction, text: item.value)),
              null => DetailItem(item.label, text: item.value),
            },
        ],
      ),
    );
  }
}

const double _barWidth = 140;

/// 막대가 이보다 좁아지면 막대 없이 값만 보인다.
const double _barMinWidth = 48;
const double _barHeight = 8;
const double _barRadius = 2;
const double _barValueGap = 16;
const double _barValueWidth = 64;

/// 범위 막대(회색 바탕 위 강조색 채움) + 오른쪽 정렬 값. `setup-bar` 키의 채움 폭이 비율이다.
class _BarValue extends StatelessWidget {
  const _BarValue({required this.fraction, required this.text});

  final double fraction;
  final String text;

  @override
  Widget build(BuildContext context) {
    // 남는 폭에 맞춰 막대를 줄이고, 너무 좁으면(휴대폰 폭) 막대 없이 값만 보인다.
    return LayoutBuilder(
      builder: (context, constraints) {
        final room = constraints.maxWidth - _barValueGap - _barValueWidth;
        final barWidth = room.isFinite ? room.clamp(0.0, _barWidth) : _barWidth;
        return barWidth < _barMinWidth ? _valueText() : _barRow(context, barWidth);
      },
    );
  }

  Widget _valueText() => Text(
        text,
        textAlign: TextAlign.end,
        style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()]),
      );

  Widget _barRow(BuildContext context, double barWidth) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(_barRadius),
          child: Container(
            width: barWidth,
            height: _barHeight,
            color: context.palette.border,
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              key: const ValueKey('setup-bar'),
              widthFactor: fraction,
              heightFactor: 1,
              child: const ColoredBox(color: AppColors.accent),
            ),
          ),
        ),
        const SizedBox(width: _barValueGap),
        SizedBox(width: _barValueWidth, child: _valueText()),
      ],
    );
  }
}
