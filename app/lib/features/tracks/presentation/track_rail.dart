import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/track_flag.dart';
import '../../sessions/presentation/session_widgets.dart';

const double _rowHeight = 44;
const double _flagGap = 10;
const double _selectedBarWidth = 3;
const EdgeInsets _rowPadding = EdgeInsets.symmetric(horizontal: 16);

/// 트랙 목록 열의 한 줄: Id, 이름, 국기 코드, 오른쪽 흐린 글자(최고 랩 등, 없으면 비움).
typedef TrackRailItem = ({String id, String name, String? countryCode, String? detail});

/// 목록 보드 왼쪽의 트랙 목록(넓은 화면): 국기 + 이름 + 오른쪽 작은 글자. 지금 트랙은 강조색 막대·바탕으로 표시하고,
/// 다른 줄을 누르면 [onSelected]로 그 트랙으로 옮겨 간다(트랙 메뉴를 열지 않고 바로).
class TrackRail extends StatelessWidget {
  const TrackRail({super.key, required this.title, required this.items, required this.selectedId, required this.onSelected});

  final String title;
  final List<TrackRailItem> items;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SessionCard(
      key: const ValueKey('track-rail'),
      title: title,
      padded: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final item in items) _RailRow(item: item, selected: item.id == selectedId, onTap: () => onSelected(item.id))],
      ),
    );
  }
}

class _RailRow extends StatelessWidget {
  const _RailRow({required this.item, required this.selected, required this.onTap});

  final TrackRailItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final detail = item.detail;
    return Material(
      color: selected ? AppColors.playerRow : Colors.transparent,
      child: InkWell(
        key: ValueKey('track-rail-${item.id}'),
        onTap: selected ? null : onTap,
        child: Container(
          height: _rowHeight,
          padding: _rowPadding,
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: selected ? AppColors.accent : Colors.transparent, width: _selectedBarWidth),
              top: BorderSide(color: palette.border),
            ),
          ),
          child: Row(
            children: [
              TrackFlag(countryCode: item.countryCode),
              const SizedBox(width: _flagGap),
              Expanded(
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
                ),
              ),
              if (detail != null) Text(detail, style: kTabularStyle.copyWith(color: palette.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}
