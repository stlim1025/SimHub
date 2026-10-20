import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

const double _maxWidth = 460;
const double _screenInset = 16;
const double _radius = 8;
const double _titleFontSize = 16;
const double _headerPaddingLeft = 20;
const double _headerPaddingRight = 8;
const double _headerPaddingY = 8;
const double _closeIconSize = 18;
const double _contentPadding = 20;
const double _footerPaddingX = 20;
const double _footerPaddingY = 12;
const double _actionGap = 8;
const double _shadowAlpha = 0.25;
const double _shadowBlur = 24;
const double _shadowOffsetY = 8;
const String _closeTooltip = '닫기';
const String _defaultCancelLabel = '취소';

/// 웹 대시보드식 모달(F1Laps 참고). 모바일 Material 대화상자 대신 쓴다.
/// 머리(제목 + ✕) · 구분선 · 본문 · 구분선 · 오른쪽 정렬 버튼 줄로 이루어진다.
/// ✕는 null로 닫는다. 폭은 최대 [_maxWidth]이고 좁은 화면에서는 양옆 16px을 남기고 줄어든다.
class WebDialog extends StatelessWidget {
  const WebDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions = const [],
    this.closeEnabled = true,
  });

  /// 머리에 보이는 제목.
  final String title;

  /// 본문.
  final Widget content;

  /// 아래 줄 버튼들. 보통 [WebDialogCancelButton] 다음 [WebDialogPrimaryButton].
  final List<Widget> actions;

  /// false면 ✕ 버튼을 누를 수 없다(저장 중 등).
  final bool closeEnabled;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Dialog(
      insetPadding: const EdgeInsets.all(_screenInset),
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxWidth),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(_radius),
            border: Border.all(color: palette.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _shadowAlpha),
                blurRadius: _shadowBlur,
                offset: const Offset(0, _shadowOffsetY),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(_headerPaddingLeft, _headerPaddingY, _headerPaddingRight, _headerPaddingY),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: _titleFontSize,
                          fontWeight: FontWeight.w600,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('web-dialog-close'),
                      tooltip: _closeTooltip,
                      iconSize: _closeIconSize,
                      color: palette.textMuted,
                      onPressed: closeEnabled ? () => Navigator.of(context).pop() : null,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(_contentPadding),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(color: palette.textPrimary),
                    child: content,
                  ),
                ),
              ),
              if (actions.isNotEmpty) ...[
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _footerPaddingX, vertical: _footerPaddingY),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: _actionGap,
                    runSpacing: _actionGap,
                    children: actions,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 모달의 보조 버튼(테두리). 누르면 [onPressed], 없으면 null로 닫는다.
class WebDialogCancelButton extends StatelessWidget {
  const WebDialogCancelButton({super.key, this.label = _defaultCancelLabel, this.onPressed, this.enabled = true});

  final String label;
  final VoidCallback? onPressed;

  /// false면 누를 수 없다.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: enabled ? (onPressed ?? () => Navigator.of(context).pop()) : null,
      child: Text(label),
    );
  }
}

/// 모달의 주 버튼(채움). [destructive]면 삭제·해제처럼 위험 색으로 그린다.
class WebDialogPrimaryButton extends StatelessWidget {
  const WebDialogPrimaryButton({super.key, required this.label, required this.onPressed, this.destructive = false});

  final String label;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return FilledButton(
      onPressed: onPressed,
      style: destructive ? FilledButton.styleFrom(backgroundColor: palette.danger, foregroundColor: palette.surface) : null,
      child: Text(label),
    );
  }
}
