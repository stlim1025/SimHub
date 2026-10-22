import 'package:flutter/material.dart';

import '../../../core/layout/equal_height.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/section_card.dart';
import '../../lap_detail/presentation/detail_list.dart';
import '../domain/setup_display.dart';

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

/// 셋업 묶음 하나: 카드 제목 + 이름표(왼쪽)·값(오른쪽, 굵게) 줄 목록. `setup-group-{제목}` 키를 갖는다.
class SetupGroupCard extends StatelessWidget {
  SetupGroupCard({required this.group}) : super(key: ValueKey('setup-group-${group.title}'));

  final SetupGroup group;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: group.title,
      child: DetailList(items: [for (final item in group.items) DetailItem(item.label, text: item.value)]),
    );
  }
}
