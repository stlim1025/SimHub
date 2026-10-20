import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_colors.dart';

/// 상단 로딩 막대의 두께(논리 px).
const double kPageLoadingBarHeight = 3;

const String _loadingSemanticsLabel = '불러오는 중';

/// 화면이 데이터를 불러오는 동안 스피너 대신 쓰는 표시(F1Laps처럼 본문 맨 위를 가로지르는 얇은 막대).
///
/// 위에 [PageLoadingHost]가 있으면 이 자리에는 아무것도 그리지 않고, 호스트가 본문 영역 맨 위 전체 폭에 막대를 띄운다.
/// 호스트가 없는 화면(스플래시·단독 위젯 테스트)에서는 이 자리에 전체 폭 막대를 그린다.
class PageLoadingBar extends StatefulWidget {
  const PageLoadingBar({super.key});

  @override
  State<PageLoadingBar> createState() => _PageLoadingBarState();
}

class _PageLoadingBarState extends State<PageLoadingBar> {
  _PageLoadingHostState? _host;

  @override
  void initState() {
    super.initState();
    _host = context.findAncestorStateOfType<_PageLoadingHostState>();
    final host = _host;
    if (host != null) {
      // 빌드 중에는 호스트 상태를 바꿀 수 없으므로 프레임이 끝난 뒤 알린다.
      SchedulerBinding.instance.addPostFrameCallback((_) => host._show(this));
    }
  }

  @override
  void dispose() {
    final host = _host;
    if (host != null) {
      // 트리 정리 중에는 다른 위젯을 다시 그리게 할 수 없으므로 프레임이 끝난 뒤 알린다.
      SchedulerBinding.instance.addPostFrameCallback((_) => host._hide(this));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _host == null
      // 화면 전체를 받는 자리(본문이 곧 로딩 상태)에서도 막대가 세로로 늘어나지 않고 맨 위에 붙게 한다.
      ? const Align(alignment: Alignment.topCenter, child: _TopProgressBar())
      : const SizedBox.shrink();
}

/// 본문 영역을 감싸, 안쪽 어딘가에 [PageLoadingBar]가 하나라도 있으면 영역 맨 위 전체 폭에 로딩 막대를 띄운다.
class PageLoadingHost extends StatefulWidget {
  const PageLoadingHost({super.key, required this.child});

  /// 본문 영역.
  final Widget child;

  @override
  State<PageLoadingHost> createState() => _PageLoadingHostState();
}

class _PageLoadingHostState extends State<PageLoadingHost> {
  /// 지금 화면에 있는 [PageLoadingBar]들. 하나라도 있으면 막대를 보인다.
  final Set<State<PageLoadingBar>> _active = {};

  void _show(State<PageLoadingBar> bar) {
    if (!mounted || !bar.mounted) return;
    if (_active.add(bar)) setState(() {});
  }

  void _hide(State<PageLoadingBar> bar) {
    if (!mounted) return;
    if (_active.remove(bar)) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_active.isNotEmpty) const Positioned(top: 0, left: 0, right: 0, child: _TopProgressBar()),
      ],
    );
  }
}

/// 트랙 없이 강조색으로 지나가는 무한 진행 막대.
class _TopProgressBar extends StatelessWidget {
  const _TopProgressBar();

  @override
  Widget build(BuildContext context) {
    return const LinearProgressIndicator(
      minHeight: kPageLoadingBarHeight,
      color: AppColors.accent,
      backgroundColor: Colors.transparent,
      semanticsLabel: _loadingSemanticsLabel,
    );
  }
}
