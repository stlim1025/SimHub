import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

const double _boxHeight = 36;
const double _boxRadius = 6;
const double _iconSize = 18;
const double _checkIconSize = 16;
const EdgeInsets _boxPadding = EdgeInsets.only(left: 12, right: 8);

/// 목록 최대 높이 = 화면 높이의 이 비율(긴 타임존 목록은 스크롤).
const double _menuMaxHeightFactor = 0.5;

/// 선택 상자의 선택지 하나.
typedef SelectOption<T> = ({T value, String label});

/// 웹 폼의 `<select>` 같은 선택 상자: 테두리 상자(현재 값 + ⌄)를 누르면 바로 아래에 같은 폭의 목록이 열리고,
/// 고른 항목은 링크 색 + ✓로 보인다. Material `DropdownButton`(밑줄·모바일 메뉴) 대신 쓴다.
class SelectBox<T> extends StatelessWidget {
  const SelectBox({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.optionKeyOf,
  });

  /// 목록 항목(이 순서대로 보인다).
  final List<SelectOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;

  /// 항목 위젯 키(테스트·자동화용). 없으면 키를 붙이지 않는다.
  final Key Function(T value)? optionKeyOf;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final maxHeight = MediaQuery.sizeOf(context).height * _menuMaxHeightFactor;
    final current = options.where((o) => o.value == selected).firstOrNull;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : null;
        return MenuAnchor(
          crossAxisUnconstrained: false,
          consumeOutsideTap: true,
          style: MenuStyle(
            backgroundColor: WidgetStatePropertyAll(palette.surface),
            surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
            side: WidgetStatePropertyAll(BorderSide(color: palette.border)),
            minimumSize: width == null ? null : WidgetStatePropertyAll(Size(width, 0)),
            maximumSize: width == null ? null : WidgetStatePropertyAll(Size(width, maxHeight)),
          ),
          menuChildren: [
            for (final option in options)
              SizedBox(
                width: width,
                child: MenuItemButton(
                  key: optionKeyOf?.call(option.value),
                  autofocus: option.value == selected,
                  trailingIcon: option.value == selected
                      ? Icon(Icons.check, size: _checkIconSize, color: palette.link)
                      : null,
                  onPressed: () => onSelected(option.value),
                  child: Text(
                    option.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: option.value == selected ? palette.link : palette.textPrimary,
                      fontWeight: option.value == selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ),
          ],
          builder: (context, controller, _) => Material(
            color: palette.surface,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: palette.border),
              borderRadius: BorderRadius.circular(_boxRadius),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: options.isEmpty ? null : () => controller.isOpen ? controller.close() : controller.open(),
              child: Container(
                height: _boxHeight,
                padding: _boxPadding,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        current?.label ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    Icon(Icons.expand_more, size: _iconSize, color: palette.textMuted),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
