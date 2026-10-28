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
import '../domain/lap_corners.dart';
import '../domain/lap_detail_models.dart';
import '../domain/telemetry_math.dart';
import '../../sessions/presentation/tyre_stints_view.dart';
import 'ghost_replay_3d_painter.dart';
import 'ghost_replay_hud.dart';
import 'ghost_replay_painter.dart';
import 'replay_circuit.dart';
import 'replay_corner_badge.dart';
import 'replay_three_view.dart';

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

/// 재생 막대 좌우 여백(막대 끝 = 이 여백 안쪽, 코너 태그가 같은 자리에 선다)·코너 태그 줄 높이·글자 크기·태그 사이 최소 간격.
const double _scrubInset = 12;
const double _cornerTagHeight = 16;
const double _cornerTagFontSize = 10;
const double _cornerTagMinGap = 22;

/// 코너로 옮길 때 코너 시작보다 이만큼(m) 앞에서 재생한다(브레이킹부터 보이게).
const double kReplayCornerLeadM = 120;

/// 고스트 재생을 밖에서 옮기는 손잡이: [seekToDistance]를 부르면 이 랩이 그 랩 거리(m)에 있던 순간으로 옮긴다.
class GhostReplaySeek extends ChangeNotifier {
  double? _distanceM;

  double? get distanceM => _distanceM;

  void seekToDistance(double distanceM) {
    _distanceM = distanceM;
    notifyListeners();
  }
}

/// 지금 코너 이름표의 위 여백.
const double _cornerBadgeInset = 10;

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
    this.corners = const [],
    this.seek,
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

  /// 이 랩에서 찾은 코너. 재생 중 지금 코너 이름을 화면 위 가운데에 띄우고, 재생 막대 아래에 코너 태그를 단다(누르면 그 코너로).
  final List<LapCorner> corners;

  /// 밖에서 재생 위치를 옮기는 손잡이(분석 탭의 코너 줄). 없으면 null.
  final GhostReplaySeek? seek;

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
    widget.seek?.addListener(_onExternalSeek);
  }

  @override
  void didUpdateWidget(GhostReplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.seek, widget.seek)) {
      oldWidget.seek?.removeListener(_onExternalSeek);
      widget.seek?.addListener(_onExternalSeek);
    }
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
    widget.seek?.removeListener(_onExternalSeek);
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  void _onExternalSeek() {
    final distance = widget.seek?.distanceM;
    if (distance != null) {
      _seekToDistance(distance);
    }
  }

  /// 이 랩이 [distanceM](랩 거리)에 있던 순간으로 옮긴다(트레이스 밖이면 처음·끝).
  void _seekToDistance(double distanceM) {
    final d = distanceM.clamp(0.0, widget.trace.lengthM);
    _seek((interpolateTimeMs(widget.trace, d) ?? 0).clamp(0.0, _durationMs.toDouble()));
  }

  /// 코너 태그를 누르면: 그 코너 시작 [kReplayCornerLeadM] 앞에서.
  void _seekToCorner(LapCorner corner) => _seekToDistance(corner.startM - kReplayCornerLeadM);

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
                    _view(playerColor, ghostColor),
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
                    ValueListenableBuilder<double>(
                      valueListenable: _time,
                      builder: (context, elapsed, _) => Align(
                        alignment: Alignment.topCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(top: _cornerBadgeInset),
                          child: ReplayCornerBadge(corner: cornerAt(widget.corners, _player.frameAt(elapsed).distanceM)),
                        ),
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

  /// 재생 화면: 3D 시점이고 WebGL 다시보기를 켰으면 three.js 그림(못 쓰면 캔버스 그림으로 돌아간다), 아니면 캔버스 그림.
  Widget _view(Color playerColor, Color ghostColor) {
    final canvas = CustomPaint(key: const ValueKey('ghost-replay-view'), painter: _painter(playerColor, ghostColor));
    final camera = _camera;
    if (camera == null || !replayThreeEnabled) {
      return canvas;
    }
    final ghost = _ghost;
    return ReplayThreeView(
      track: _track3d ??= ReplayTrack3d.build(_circuit),
      cars: [
        (car: _player, color: playerColor, opacity: 1, tyre: (_) => _playerTyre),
        if (ghost != null) (car: ghost, color: ghostColor, opacity: kGhostCarOpacity, tyre: null),
      ],
      camera: camera,
      time: _time,
      fallback: canvas,
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
    final slider = ValueListenableBuilder<double>(
      valueListenable: _time,
      builder: (context, elapsed, _) => Slider(
        key: const ValueKey('ghost-replay-scrub'),
        value: elapsed.clamp(0, _durationMs.toDouble()).toDouble(),
        max: _durationMs.toDouble(),
        activeColor: AppColors.accent,
        inactiveColor: palette.border,
        // 막대 끝을 정해 둔 여백에 맞춰 코너 태그가 같은 자리에 선다.
        padding: const EdgeInsets.symmetric(horizontal: _scrubInset),
        onChanged: _seek,
      ),
    );
    final scrub = widget.corners.isEmpty
        ? slider
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [slider, _cornerTags(palette)],
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

  /// 재생 막대 아래 코너 태그 줄: 이 랩이 코너에 들어선 시각 자리에 `T7`. 서로 가까우면 앞 태그만 쓴다. 누르면 그 코너로.
  Widget _cornerTags(AppPalette palette) {
    final duration = _durationMs.toDouble();
    final style = TextStyle(fontSize: _cornerTagFontSize, color: palette.textMuted, fontWeight: FontWeight.w600);
    return SizedBox(
      height: _cornerTagHeight,
      child: LayoutBuilder(
        builder: (context, box) {
          final width = box.maxWidth - 2 * _scrubInset;
          final tags = <Widget>[];
          var lastX = double.negativeInfinity;
          for (final corner in widget.corners) {
            final time = interpolateTimeMs(widget.trace, corner.startM);
            if (time == null || duration <= 0) {
              continue;
            }
            final x = _scrubInset + width * (time / duration).clamp(0.0, 1.0);
            if (x - lastX < _cornerTagMinGap) {
              continue;
            }
            lastX = x;
            tags.add(Positioned(
              left: x - _cornerTagMinGap / 2,
              width: _cornerTagMinGap,
              top: 0,
              bottom: 0,
              child: InkWell(
                key: ValueKey('ghost-replay-corner-${corner.label}'),
                onTap: () => _seekToCorner(corner),
                child: Center(child: Text(corner.label, style: style, maxLines: 1, softWrap: false)),
              ),
            ));
          }
          return Stack(clipBehavior: Clip.none, children: tags);
        },
      ),
    );
  }
}
