import 'package:flutter/material.dart';

import '../../../core/widgets/menu_items.dart';
import '../../../core/widgets/web_dialog.dart';
import '../../../core/theme/app_palette.dart';
import '../domain/lap_compare.dart';

const double _controlGap = 8;
const double _menuIconSize = 18;
const double _faceRadius = 6;
const EdgeInsets _facePadding = EdgeInsets.symmetric(horizontal: 10, vertical: 6);

const String _comparePrefix = 'Compare with: ';
const String _filterLabel = 'Filter by';
const String _lapIdDialogTitle = '비교할 랩 ID';
const String _lapIdHint = '랩 ID 또는 랩 상세 주소를 붙여 넣으세요';
const String _lapIdInvalid = '랩 ID 형식이 아니에요';
const String _cancelLabel = '취소';
const String _confirmLabel = '비교';
const String _filtersDisabledTooltip = '내 최고 랩·리더보드 최고 랩을 고를 때만 쓸 수 있어요';

/// 비교 종류 → 메뉴 글자(F1Laps와 같은 말, docs/15 §10).
const Map<LapCompareKind, String> kCompareKindLabels = {
  LapCompareKind.best: 'Your best lap',
  LapCompareKind.leaderboard: 'Leaderboard best lap',
  LapCompareKind.lap: 'Another lap ID',
  LapCompareKind.none: "Don't compare lap",
  LapCompareKind.car: 'Another car',
};

/// 필터 → 메뉴 글자.
const Map<LapCompareFilter, String> kCompareFilterLabels = {
  LapCompareFilter.sameTeam: 'Same team',
  LapCompareFilter.sameSessionType: 'Same session type',
  LapCompareFilter.sameAssists: 'Same assists',
  LapCompareFilter.sameTyre: 'Same tyre',
};

/// 버튼 글자: `Compare with: Leaderboard best lap`, 비교 안 함이면 `Don't compare lap`.
String compareButtonText(LapCompareKind kind) =>
    kind == LapCompareKind.none ? kCompareKindLabels[kind]! : '$_comparePrefix${kCompareKindLabels[kind]}';

/// 탭 아래 "Compare with ▾" + "Filter by ▾"(docs/15 §10, D-51). 고르면 [onChanged]로 새 선택을 넘긴다(주소가 바뀐다).
/// "Another lap ID"는 랩 ID를 붙여 넣는 작은 창을 연다. 필터는 복수 선택, 내 최고 랩·리더보드 최고 랩일 때만 켤 수 있다.
class CompareControls extends StatelessWidget {
  const CompareControls({super.key, required this.selection, required this.onChanged});

  final LapCompareSelection selection;
  final ValueChanged<LapCompareSelection> onChanged;

  Future<void> _pickKind(BuildContext context, LapCompareKind kind) async {
    if (kind != LapCompareKind.lap) {
      onChanged(selection.withKind(kind));
      return;
    }
    final lapId = await showDialog<String>(
      context: context,
      builder: (_) => _LapIdDialog(initial: selection.compareLapId),
    );
    if (lapId != null) {
      onChanged(selection.withKind(LapCompareKind.lap, lapId: lapId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final filterCount = selection.filters.length;
    final filtersEnabled = selection.usesFilters;
    final filterText = filtersEnabled && filterCount > 0 ? '$_filterLabel ($filterCount)' : _filterLabel;
    final filterMenu = PopupMenuButton<LapCompareFilter>(
      key: const ValueKey('compare-filter-menu'),
      enabled: filtersEnabled,
      tooltip: filtersEnabled ? _filterLabel : null,
      onSelected: (filter) => onChanged(selection.toggle(filter)),
      itemBuilder: (_) => [
        for (final filter in LapCompareFilter.values)
          CheckMenuItem<LapCompareFilter>(value: filter, checked: selection.filters.contains(filter), label: kCompareFilterLabels[filter]!),
      ],
      child: _MenuButtonFace(text: filterText, enabled: filtersEnabled),
    );
    return Wrap(
      spacing: _controlGap,
      runSpacing: _controlGap,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        PopupMenuButton<LapCompareKind>(
          key: const ValueKey('compare-with-menu'),
          tooltip: 'Compare with',
          onSelected: (kind) => _pickKind(context, kind),
          itemBuilder: (_) => [
            // 다른 차 비교는 세션 순위표에서 고른다(메뉴에는 없다).
            for (final kind in LapCompareKind.values)
              if (kind != LapCompareKind.car)
                CheckMenuItem<LapCompareKind>(value: kind, checked: kind == selection.kind, label: compareButtonText(kind)),
          ],
          child: _MenuButtonFace(
            text: selection.kind == LapCompareKind.car && (selection.compareName ?? '').isNotEmpty
                ? '$_comparePrefix${selection.compareName}'
                : compareButtonText(selection.kind),
          ),
        ),
        if (filtersEnabled) filterMenu else Tooltip(message: _filtersDisabledTooltip, child: filterMenu),
      ],
    );
  }
}

/// 드롭다운 버튼 모양: 테두리 + 글자 + ▾.
class _MenuButtonFace extends StatelessWidget {
  const _MenuButtonFace({required this.text, this.enabled = true});

  final String text;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = enabled ? null : palette.textMuted;
    return Container(
      padding: _facePadding,
      decoration: BoxDecoration(
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(_faceRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w600, color: color),
            ),
          ),
          Icon(Icons.arrow_drop_down, size: _menuIconSize, color: color),
        ],
      ),
    );
  }
}

/// 랩 ID 붙여 넣기 창. 확인하면 다듬은 ID를, 취소하면 null을 돌려준다.
class _LapIdDialog extends StatefulWidget {
  const _LapIdDialog({this.initial});

  final String? initial;

  @override
  State<_LapIdDialog> createState() => _LapIdDialogState();
}

class _LapIdDialogState extends State<_LapIdDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial ?? '');
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final lapId = normalizeLapIdInput(_controller.text);
    if (lapId == null) {
      setState(() => _error = _lapIdInvalid);
      return;
    }
    Navigator.of(context).pop(lapId);
  }

  @override
  Widget build(BuildContext context) {
    return WebDialog(
      title: _lapIdDialogTitle,
      content: TextField(
        key: const ValueKey('compare-lap-id-field'),
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(hintText: _lapIdHint, errorText: _error),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        const WebDialogCancelButton(label: _cancelLabel),
        WebDialogPrimaryButton(label: _confirmLabel, onPressed: _submit),
      ],
    );
  }
}
