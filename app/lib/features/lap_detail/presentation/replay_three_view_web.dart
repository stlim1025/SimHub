import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'ghost_replay_3d_painter.dart';
import 'replay_three_scene.dart';

/// 앱 주소에 `?replay3d=three`가 있으면 3D 시점을 three.js로 그린다(기본 화면으로 바꾸기 전 확인용).
const String _flagParameter = 'replay3d';
const String _flagValue = 'three';

/// three.js 그림 모듈(앱 web 폴더, main.dart.js 기준 상대 경로).
const String _modulePath = './replay3d/replay3d.js';
const String _containerTag = 'div';
const String _fill = '100%';

bool get replayThreeEnabled => Uri.base.queryParameters[_flagParameter] == _flagValue;

extension type _SceneModule(JSObject _) implements JSObject {
  external _SceneHandle createReplayScene(web.HTMLElement container);
}

extension type _SceneHandle(JSObject _) implements JSObject {
  external bool get ok;
  /// 면 종류별 층(종류 번호·위치·무늬 좌표·색을 같은 순서의 배열로), 넓은 바닥 색, 가장 낮은 노면 높이, 시가지인지.
  external void setTrack(
    JSArray<JSNumber> surfaces,
    JSArray<JSFloat32Array> positions,
    JSArray<JSFloat32Array> uvs,
    JSArray<JSFloat32Array> colors,
    JSArray<JSNumber> groundRgb,
    double minElevation,
    bool street,
  );
  external void render(JSFloat32Array state);
  external void dispose();
}

/// 모듈은 한 번만 불러온다(다시보기를 처음 열 때).
Future<_SceneModule>? _module;

Future<_SceneModule> _loadModule() =>
    _module ??= importModule(_modulePath.toJS).toDart.then((module) => module as _SceneModule);

/// three.js(WebGL) 다시보기: [track] 메시를 한 번 넘기고, [time]이 바뀔 때마다 [cars](첫 차를 [camera]로 따라간다)의
/// 프레임 상태를 넘겨 그린다. 모듈을 불러오는 동안·WebGL을 못 쓰면 [fallback](캔버스 그림)을 그린다.
class ReplayThreeView extends StatefulWidget {
  const ReplayThreeView({
    super.key,
    required this.track,
    required this.cars,
    required this.camera,
    required this.time,
    required this.fallback,
    this.overlay,
  });

  final ReplayTrack3d track;
  final List<ReplaySceneCar> cars;
  final ReplayCamera camera;
  final ValueListenable<double> time;
  final Widget fallback;

  /// three.js 그림 위에 얹는 위젯(이름표 등). 대체 그림을 쓸 때는 얹지 않는다(대체 그림이 직접 그린다).
  final Widget? overlay;

  @override
  State<ReplayThreeView> createState() => _ReplayThreeViewState();
}

class _ReplayThreeViewState extends State<ReplayThreeView> {
  _SceneHandle? _scene;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    widget.time.addListener(_render);
  }

  @override
  void didUpdateWidget(ReplayThreeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.time, widget.time)) {
      oldWidget.time.removeListener(_render);
      widget.time.addListener(_render);
    }
    if (!identical(oldWidget.track, widget.track)) {
      _sendTrack();
    }
    _render();
  }

  @override
  void dispose() {
    widget.time.removeListener(_render);
    _scene?.dispose();
    super.dispose();
  }

  Future<void> _onElementCreated(Object element) async {
    final container = element as web.HTMLElement;
    container.style
      ..width = _fill
      ..height = _fill;
    try {
      final module = await _loadModule();
      if (!mounted) {
        return;
      }
      final scene = module.createReplayScene(container);
      if (!scene.ok) {
        setState(() => _failed = true);
        return;
      }
      setState(() => _scene = scene);
      _sendTrack();
      _render();
    } catch (error) {
      debugPrint('replay3d: failed to load ($error)');
      if (mounted) {
        setState(() => _failed = true);
      }
    }
  }

  void _sendTrack() {
    final scene = _scene;
    if (scene == null) {
      return;
    }
    final mesh = buildReplayTrackMesh(widget.track);
    final ground = mesh.groundColor;
    scene.setTrack(
      [for (final l in mesh.layers) l.surface.index.toJS].toJS,
      [for (final l in mesh.layers) l.positions.toJS].toJS,
      [for (final l in mesh.layers) l.uvs.toJS].toJS,
      [for (final l in mesh.layers) l.colors.toJS].toJS,
      [ground.r.toJS, ground.g.toJS, ground.b.toJS].toJS,
      mesh.minElevationM,
      mesh.street,
    );
  }

  void _render() {
    _scene?.render(packReplayFrame(widget.track, widget.cars, widget.camera, widget.time.value).toJS);
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return widget.fallback;
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_scene == null) widget.fallback,
        HtmlElementView.fromTagName(tagName: _containerTag, onElementCreated: _onElementCreated),
        if (_scene != null && widget.overlay != null) widget.overlay!,
      ],
    );
  }
}
