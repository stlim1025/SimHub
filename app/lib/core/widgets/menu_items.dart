import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// 웹 드롭다운 느낌의 메뉴 한 줄 높이(Material 기본 48보다 촘촘하게).
const double kMenuItemHeight = 34;

const double _checkSlotWidth = 24;
const double _checkIconSize = 16;
const EdgeInsets _itemPadding = EdgeInsets.symmetric(horizontal: 12);

/// 선택 표시(✓)가 있는 촘촘한 팝업 메뉴 항목. [CheckedPopupMenuItem]과 같이 [checked]를 갖지만
/// 목록 타일(48px·넓은 여백) 대신 한 줄 글자 + 앞쪽 ✓ 자리로 그린다(F1Laps의 Compare with 메뉴 참고).
class CheckMenuItem<T> extends PopupMenuItem<T> {
  CheckMenuItem({super.key, required T super.value, required this.checked, required String label})
      : super(
          height: kMenuItemHeight,
          padding: _itemPadding,
          child: _CheckMenuLabel(checked: checked, label: label),
        );

  final bool checked;
}

class _CheckMenuLabel extends StatelessWidget {
  const _CheckMenuLabel({required this.checked, required this.label});

  final bool checked;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: _checkSlotWidth,
          child: checked ? Icon(Icons.check, size: _checkIconSize, color: context.palette.link) : null,
        ),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}
