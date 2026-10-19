import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// 알림 종류(색·아이콘).
enum NoticeTone { success, error, info }

/// 오른쪽 위 알림이 떠 있는 기본 시간.
const Duration kToastDuration = Duration(seconds: 4);

const double _bannerRadius = 8;
const double _bannerPaddingX = 16;
const double _bannerPaddingY = 12;
const double _bannerTintAlpha = 0.14;
const double _bannerBorderAlpha = 0.4;
const double _iconSize = 18;
const double _iconGap = 10;
const double _toastMargin = 16;
const double _toastMaxWidth = 380;
const double _toastElevation = 8;
const Duration _fadeDuration = Duration(milliseconds: 150);

Color _toneColor(BuildContext context, NoticeTone tone) => switch (tone) {
      NoticeTone.success => context.palette.success,
      NoticeTone.error => context.palette.danger,
      NoticeTone.info => context.palette.link,
    };

IconData _toneIcon(NoticeTone tone) => switch (tone) {
      NoticeTone.success => Icons.check_circle,
      NoticeTone.error => Icons.error_outline,
      NoticeTone.info => Icons.info_outline,
    };

/// 페이지 안에 들어가는 알림 줄(웹 화면의 "Changes saved successfully." 같은 배너).
/// 저장 성공·로그인 실패처럼 그 화면의 결과를 알릴 때 쓴다 — 화면 아래에서 올라오는 모바일식 알림(SnackBar)은 쓰지 않는다.
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({super.key, required this.message, this.tone = NoticeTone.success});

  final String message;
  final NoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final color = _toneColor(context, tone);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: _bannerPaddingX, vertical: _bannerPaddingY),
        decoration: BoxDecoration(
          color: color.withValues(alpha: _bannerTintAlpha),
          borderRadius: BorderRadius.circular(_bannerRadius),
          border: Border.all(color: color.withValues(alpha: _bannerBorderAlpha)),
        ),
        child: Row(
          children: [
            Icon(_toneIcon(tone), size: _iconSize, color: color),
            const SizedBox(width: _iconGap),
            Expanded(
              child: Text(message, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

/// 오른쪽 위에 잠깐 떴다가 사라지는 알림(웹 알림 방식). 화면을 가리지 않고, 새 알림이 오면 앞의 것을 바꾼다.
///
/// 비동기 작업 뒤에 띄울 때는 작업 전에 `AppToaster.of(context)`를 잡아 둔다(비동기 뒤 context 사용 금지).
class AppToaster {
  AppToaster._(this._overlay);

  /// 화면(Overlay)마다 지금 떠 있는 알림. 새 알림이 오면 이것을 지운다.
  static final Expando<OverlayEntry> _current = Expando<OverlayEntry>('AppToaster.current');

  final OverlayState _overlay;

  static AppToaster of(BuildContext context) => AppToaster._(Overlay.of(context, rootOverlay: true));

  /// 알림을 띄운다. [actionLabel]·[onAction]이 있으면 동작 버튼을 붙인다(누르면 알림을 닫고 실행한다).
  void show(
    String message, {
    NoticeTone tone = NoticeTone.info,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = kToastDuration,
    Key? key,
  }) {
    if (!_overlay.mounted) {
      return;
    }
    _remove(_current[_overlay]);

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => Positioned(
        top: _toastMargin,
        right: _toastMargin,
        child: SafeArea(
          child: AppToast(
            key: key,
            message: message,
            tone: tone,
            actionLabel: actionLabel,
            duration: duration,
            onAction: onAction == null
                ? null
                : () {
                    _remove(entry);
                    onAction();
                  },
            onClose: () => _remove(entry),
          ),
        ),
      ),
    );
    _current[_overlay] = entry;
    _overlay.insert(entry);
  }

  void _remove(OverlayEntry? entry) {
    if (entry == null || !entry.mounted) {
      return;
    }
    entry.remove();
    if (identical(_current[_overlay], entry)) {
      _current[_overlay] = null;
    }
  }
}

/// [AppToaster]가 그리는 알림 카드. [duration]이 지나면 [onClose]를 부른다(화면이 사라지면 타이머도 멈춘다).
class AppToast extends StatefulWidget {
  const AppToast({
    super.key,
    required this.message,
    required this.tone,
    required this.duration,
    required this.onClose,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final NoticeTone tone;
  final Duration duration;
  final VoidCallback onClose;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  State<AppToast> createState() => _AppToastState();
}

class _AppToastState extends State<AppToast> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, widget.onClose);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = _toneColor(context, widget.tone);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: _fadeDuration,
      builder: (context, opacity, child) => Opacity(opacity: opacity, child: child),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _toastMaxWidth),
        child: Material(
          color: palette.surface,
          elevation: _toastElevation,
          shadowColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_bannerRadius),
            side: BorderSide(color: palette.border),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(_bannerPaddingX, _iconGap, _iconGap, _iconGap),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_toneIcon(widget.tone), size: _iconSize, color: color),
                const SizedBox(width: _iconGap),
                Flexible(child: Text(widget.message, style: TextStyle(color: palette.textPrimary))),
                if (widget.actionLabel != null && widget.onAction != null) ...[
                  const SizedBox(width: _iconGap),
                  TextButton(onPressed: widget.onAction, child: Text(widget.actionLabel!)),
                ],
                IconButton(
                  tooltip: '닫기',
                  visualDensity: VisualDensity.compact,
                  iconSize: _iconSize,
                  color: palette.textMuted,
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
