import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

const double _toggleHeight = 32;
const double _toggleRadius = 6;
const double _iconSize = 16;
const double _iconGap = 6;
const EdgeInsets _togglePadding = EdgeInsets.symmetric(horizontal: 10);

/// 켜고 끄는 웹식 테두리 버튼(☐/☑ + 글자). [ButtonGroup]과 같은 높이·테두리로 나란히 놓인다.
/// Material `FilterChip`(둥근 칩) 대신 쓴다.
class CheckToggle extends StatelessWidget {
  const CheckToggle({super.key, required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      toggled: value,
      button: true,
      excludeSemantics: true,
      label: label,
      onTap: () => onChanged(!value),
      child: Material(
        color: value ? palette.border : Colors.transparent,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: palette.border),
          borderRadius: BorderRadius.circular(_toggleRadius),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onChanged(!value),
          child: Container(
            height: _toggleHeight,
            padding: _togglePadding,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  value ? Icons.check_box : Icons.check_box_outline_blank,
                  size: _iconSize,
                  color: value ? palette.link : palette.textMuted,
                ),
                const SizedBox(width: _iconGap),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: value ? palette.textPrimary : palette.textMuted,
                        fontWeight: value ? FontWeight.w600 : FontWeight.normal,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
