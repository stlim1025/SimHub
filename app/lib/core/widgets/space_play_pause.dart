import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 스페이스로 재생·일시정지하는 영역(다시보기·하이라이트 재생기를 감싼다).
///
/// - 이 영역 안에 포커스가 있으면 [Focus]로 받아 끝낸다 — 안의 버튼이 눌리거나(웹 기본 동작) 페이지가 굴러가지 않게,
///   누른 채 반복되는 키도 삼킨다. 영역 안을 누르면 포커스를 가져온다.
/// - 포커스가 밖에 있어도(다른 곳을 눌렀거나 탭을 옮긴 뒤) 이 화면이 맨 위에 보이는 동안은 키보드 전체에서 받아
///   [onToggle]을 부르고 포커스를 가져온다(Ctrl+K 검색 창과 같은 방식).
/// - 글자 칸에 포커스가 있거나 Ctrl·Alt·⌘와 함께 누르면 넘긴다.
class SpacePlayPause extends StatefulWidget {
  const SpacePlayPause({super.key, required this.onToggle, required this.child});

  /// 재생·일시정지를 바꾼다.
  final VoidCallback onToggle;

  final Widget child;

  @override
  State<SpacePlayPause> createState() => _SpacePlayPauseState();
}

class _SpacePlayPauseState extends State<SpacePlayPause> {
  final FocusNode _node = FocusNode(debugLabel: 'space-play-pause');

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKeyAnywhere);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyAnywhere);
    _node.dispose();
    super.dispose();
  }

  bool _isPlainSpace(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    return event.logicalKey == LogicalKeyboardKey.space &&
        !keyboard.isControlPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isMetaPressed;
  }

  /// 글자 칸(EditableText)에 포커스가 있는지 — 그때 스페이스는 글자다.
  bool get _typing {
    final focused = FocusManager.instance.primaryFocus?.context;
    return focused != null &&
        (focused.widget is EditableText || focused.findAncestorWidgetOfExactType<EditableText>() != null);
  }

  /// 이 화면이 맨 위 경로이고 보이는 자리(꺼진 탭이 아닌)인지.
  bool get _visible => (ModalRoute.of(context)?.isCurrent ?? true) && TickerMode.valuesOf(context).enabled;

  /// 포커스가 이 영역 안일 때.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_isPlainSpace(event) || _typing) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      widget.onToggle();
    }
    return KeyEventResult.handled;
  }

  /// 포커스가 이 영역 밖일 때(안이면 [_onKey]가 받는다).
  bool _onKeyAnywhere(KeyEvent event) {
    if (event is! KeyDownEvent || !_isPlainSpace(event) || !mounted || _node.hasFocus || _typing || !_visible) {
      return false;
    }
    widget.onToggle();
    _node.requestFocus();
    return true;
  }

  void _claimFocus(PointerDownEvent event) {
    if (!_node.hasFocus) {
      _node.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: _claimFocus,
        child: Focus(focusNode: _node, autofocus: true, onKeyEvent: _onKey, child: widget.child),
      );
}
