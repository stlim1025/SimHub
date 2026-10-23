import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/button_group.dart';
import '../../auth/domain/user_preferences.dart';
import '../../laps/domain/lap_models.dart';
import '../../tracks/domain/track_sample_geometry.dart';
import '../../tracks/domain/track_width_profile.dart';
import '../domain/ghost_replay.dart';
import '../domain/lap_detail_models.dart';
import '../../sessions/presentation/tyre_stints_view.dart';
import 'ghost_replay_3d_painter.dart';
import 'ghost_replay_hud.dart';
import 'ghost_replay_painter.dart';
import 'replay_circuit.dart';

/// 재생 화면 높이(넓은 화면·좁은 화면).
const double kGhostReplayWideHeight = 540;
const double kGhostReplayNarrowHeight = 380;

/// 재생 배속 선택지.
const List<double> kGhostReplaySpeeds = [0.5, 1, 2, 4];
const double _defaultSpeed = 1;

const EdgeInsets _cardPadding = EdgeInsets.all(16);
const double _viewRadius = 8;
const double _controlsGap = 12;
const double _controlSpacing = 8;

/// 조작 줄 폭이 이보다 좁으면 시간 막대를 아랫줄로 내리고 버튼은 줄을 바꿔 감싼다.
const double _singleRowControlsMinWidth = 760;
const double _microsecondsPerMs = 1000;
const String _playTooltip = '재생';
const String _pauseTooltip = '일시정지';
const String _restartTooltip = '처음부터';

/// 시점 선택지: 3D 카메라들(기본 추격)과 위에서 본 2D 지도(null).
const List<({ReplayCamera? value, String label})> kGhostReplayViews = [
  (value: ReplayCamera.chase, label: '추격'),
  (value: ReplayCamera.broadcast, label: '중계'),
  (value: ReplayCamera.helicopter, label: '헬기'),
  (value: null, label: '2D'),
];

/// 배속 글자: `0.5×`·`1×`(순수 함수).
String ghostReplaySpeedLabel(double speed) => '${speed == speed.roundToDouble() ? speed.round() : speed}×';

/// 고스트 재생 카드: 이 랩과 비교 랩을 같은 시계로 달리게 해 추격 카메라로 보여 준다(타임 트라이얼 고스트처럼).
/// 재생 중에는 이 랩의 현재 거리를 [cursor]에 써서 그래프 재생 막대·트랙 지도 점이 따라오게 한다.
/// [trace]에 위치가 있어야 하고, 고스트는 [reference]에 위치가 있을 때만 그린다.
class GhostReplay extends StatefulWidget {
  const GhostReplay({
    super.key,
    required this.trace,
    required this.reference,
    required this.cursor,
    required this.units,
    required this.height,
    required this.thisLapLabel,
    required this.referenceLabel,
    this.playerTeam,
    this.referenceTeam,
    this.playerSectors = const [],
    this.referenceSectors = const [],
    this.playerTyreCompound,
    this.realTrack,
    this.trackSamples,
    this.estimatedTrackWidthM,
    this.streetCircuit = false,
  });

  final LapTrace trace;
  final LapTrace? reference;
  final ValueNotifier<double?> cursor;
  final UnitSystem units;
  final double height;

  /// HUD 범례 이름(그래프 범례와 같은 글자).
  final String thisLapLabel;
  final String referenceLabel;

  /// 차 색을 정하는 팀. 없으면 이 랩은 강조색, 비교 랩은 청록.
  final LapTeam? playerTeam;
  final LapTeam? referenceTeam;

  /// 섹터 비교(HUD 왼쪽 위)에 쓰는 두 랩의 섹터 시간. 재생하며 지난 섹터만 채운다.
  final List<LapSector> playerSectors;
  final List<LapSector> referenceSectors;

  /// 이 랩 타이어(보이는 컴파운드 이름 `Soft`·`Medium`…). 차 타이어에 컴파운드 색을 칠한다. 모르면(비교 랩도) 띠 없음.
  final String? playerTyreCompound;

  /// 이 트랙의 실측 서킷(중심선·폭). 없거나 주행선에 맞지 않으면 주행 기록으로 추정한 모양을 그린다.
  final TrackWidthProfile? realTrack;

  /// 모든 차 표본으로 만든 이 트랙 형상. 있으면 실측이 없는 트랙의 도로·높이·연석에 쓴다.
  final TrackSampleGeometry? trackSamples;

  /// 실측이 없는 구간의 직선 도로 폭(m). null이면 기본값.
  final double? estimatedTrackWidthM;

  /// 시가지 서킷인지(그래블 없이 도로 바로 옆에 벽).
  final bool streetCircuit;

  @override
  State<GhostReplay> createState() => _GhostReplayState();
}

class _GhostReplayState extends State<GhostReplay> with SingleTickerProviderStateMixin {
  late LapReplay _player;
  LapReplay? _ghost;
  late ReplayCircuit _circuit;

  /// 3D 시점 서킷(3D 시점을 처음 그릴 때 만든다)·고른 3D 카메라(기본 추격, null이면 2D 지도).
  ReplayTrack3d? _track3d;
  ReplayCamera? _camera = ReplayCamera.chase;

  /// 재생 경과 시간(ms).
  final ValueNotifier<double> _time = ValueNotifier<double>(0);
  late final Ticker _ticker = createTicker(_onTick);
  Duration _lastTick = Duration.zero;
  double _speed = _defaultSpeed;

  bool get _playing => _ticker.isActive;

  int get _durationMs => replayDurationMs(_player, _ghost);

  @override
  void initState() {
    super.initState();
    _setUp();
  }

  @override
  void didUpdateWidget(GhostReplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.trace, widget.trace) ||
        !identical(oldWidget.reference, widget.reference) ||
        !identical(oldWidget.realTrack, widget.realTrack) ||
        !identical(oldWidget.trackSamples, widget.trackSamples)) {
      _ticker.stop();
      _setUp();
      _time.value = 0;
    }
  }

  void _setUp() {
    _player = LapReplay(widget.trace);
    final reference = widget.reference;
    _ghost = reference != null && reference.hasPositions ? LapReplay(reference) : null;
    final baseWidth = widget.estimatedTrackWidthM;
    _circuit = baseWidth == null
        ? ReplayCircuit.build(
            _player,
            ghost: _ghost,
            real: widget.realTrack,
            samples: widget.trackSamples,
            street: widget.streetCircuit,
          )
        : ReplayCircuit.build(
            _player,
            ghost: _ghost,
            real: widget.realTrack,
            samples: widget.trackSamples,
            baseWidthM: baseWidth,
            street: widget.streetCircuit,
          );
    _track3d = null;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final deltaMs = (elapsed - _lastTick).inMicroseconds / _microsecondsPerMs;
    _lastTick = elapsed;
    final next = _time.value + deltaMs * _speed;
    final end = _durationMs.toDouble();
    if (next >= end) {
      _seek(end);
      setState(_ticker.stop);
      return;
    }
    _seek(next);
  }

  /// 경과 시간을 옮기고 그래프 십자선도 이 랩의 거리로 맞춘다.
  void _seek(double elapsedMs) {
    _time.value = elapsedMs;
    widget.cursor.value = _player.frameAt(elapsedMs).distanceM;
  }

  void _togglePlay() {
    setState(() {
      if (_playing) {
        _ticker.stop();
        return;
      }
      if (_time.value >= _durationMs) {
        _seek(0);
      }
      _lastTick = Duration.zero;
      _ticker.start();
    });
  }

  void _restart() => _seek(0);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final playerColor = replayCarColor(widget.playerTeam, fallback: AppColors.accent);
    final ghostColor = replayCarColor(widget.referenceTeam, fallback: palette.comparison);
    return Card(
      key: const ValueKey('ghost-replay'),
      child: Padding(
        padding: _cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(_viewRadius),
              child: SizedBox(
                height: widget.height,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CustomPaint(
                      key: const ValueKey('ghost-replay-view'),
                      painter: _painter(playerColor, ghostColor),
                    ),
                    ValueListenableBuilder<double>(
                      valueListenable: _time,
                      builder: (context, elapsed, _) => GhostReplayHud(
                        elapsedMs: elapsed,
                        player: _player.frameAt(elapsed),
                        ghost: _ghost?.frameAt(elapsed),
                        gapMs: _gapAt(elapsed),
                        sectors: replaySectorRows(widget.playerSectors, widget.referenceSectors, elapsed),
                        units: widget.units,
                        playerColor: playerColor,
                        ghostColor: ghostColor,
                        thisLapLabel: widget.thisLapLabel,
                        referenceLabel: widget.referenceLabel,
                        tyreCompound: widget.playerTyreCompound,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: _controlsGap),
            _controls(palette),
          ],
        ),
      ),
    );
  }

  /// 고른 시점의 페인터: 2D 지도 또는 3D 카메라.
  CustomPainter _painter(Color playerColor, Color ghostColor) {
    final camera = _camera;
    if (camera == null) {
      return GhostReplayPainter(
        player: _player,
        ghost: _ghost,
        circuit: _circuit,
        time: _time,
        playerColor: playerColor,
        ghostColor: ghostColor,
        playerTyre: _playerTyre,
      );
    }
    return GhostReplay3dPainter(
      player: _player,
      ghost: _ghost,
      track: _track3d ??= ReplayTrack3d.build(_circuit),
      camera: camera,
      time: _time,
      playerColor: playerColor,
      ghostColor: ghostColor,
      playerTyre: _playerTyre,
    );
  }

  /// 이 랩 타이어 컴파운드 색. 모르면 null.
  Color? get _playerTyre {
    final compound = widget.playerTyreCompound;
    return compound == null ? null : tyreColorOf(compound);
  }

  /// 이 랩의 현재 거리에서 비교 랩과의 시간 차(ms). 고스트가 없으면 null.
  double? _gapAt(double elapsedMs) {
    final ghost = _ghost;
    if (ghost == null) {
      return null;
    }
    return replayGapMs(_player.trace, ghost.trace, _player.frameAt(elapsedMs).distanceM);
  }

  /// 재생·처음부터·배속·시점, 그리고 시간 막대. 폭이 좁으면 버튼을 줄 바꿔 감싸고 시간 막대를 아랫줄에 둔다.
  Widget _controls(AppPalette palette) {
    final transport = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: const ValueKey('ghost-replay-play'),
          tooltip: _playing ? _pauseTooltip : _playTooltip,
          icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
          onPressed: _togglePlay,
        ),
        IconButton(
          key: const ValueKey('ghost-replay-restart'),
          tooltip: _restartTooltip,
          icon: const Icon(Icons.replay),
          onPressed: _restart,
        ),
      ],
    );
    final speeds = ButtonGroup<double>(
      options: [for (final speed in kGhostReplaySpeeds) (value: speed, label: ghostReplaySpeedLabel(speed))],
      selected: _speed,
      onSelected: (speed) => setState(() => _speed = speed),
      segmentKeyOf: (speed) => ValueKey('ghost-replay-speed-$speed'),
    );
    final views = ButtonGroup<ReplayCamera?>(
      options: kGhostReplayViews,
      selected: _camera,
      onSelected: (camera) => setState(() => _camera = camera),
      segmentKeyOf: (camera) => ValueKey('ghost-replay-view-${camera?.name ?? '2d'}'),
    );
    final scrub = ValueListenableBuilder<double>(
      valueListenable: _time,
      builder: (context, elapsed, _) => Slider(
        key: const ValueKey('ghost-replay-scrub'),
        value: elapsed.clamp(0, _durationMs.toDouble()).toDouble(),
        max: _durationMs.toDouble(),
        activeColor: AppColors.accent,
        inactiveColor: palette.border,
        onChanged: _seek,
      ),
    );
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth >= _singleRowControlsMinWidth
          ? Row(
              children: [
                transport,
                const SizedBox(width: _controlSpacing),
                speeds,
                const SizedBox(width: _controlSpacing),
                views,
                const SizedBox(width: _controlSpacing),
                Expanded(child: scrub),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: _controlSpacing,
                  runSpacing: _controlSpacing,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [transport, speeds, views],
                ),
                scrub,
              ],
            ),
    );
  }
}
