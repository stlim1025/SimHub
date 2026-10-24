import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/page_padding.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/util/hex_color.dart';
import '../../../core/widgets/button_group.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/page_loading_bar.dart';
import '../../lap_detail/application/lap_detail_providers.dart';
import '../../lap_detail/domain/ghost_replay.dart';
import '../../lap_detail/domain/lap_detail_models.dart';
import '../../lap_detail/presentation/ghost_replay.dart';
import '../../lap_detail/presentation/ghost_replay_3d_painter.dart';
import '../../lap_detail/presentation/replay_circuit.dart';
import '../../tracks/application/track_widths_provider.dart';
import '../../tracks/application/tracks_providers.dart';
import '../../tracks/domain/track_sample_geometry.dart';
import '../../tracks/domain/track_width_profile.dart';
import '../application/sessions_providers.dart';
import '../domain/race_highlights.dart';
import '../domain/session_models.dart';
import 'highlights_broadcast_overlay.dart';

/// 세션 하이라이트 주소.
String sessionHighlightsLocation(String sessionId) => '/sessions/${Uri.encodeComponent(sessionId)}/highlights';

/// 하이라이트 묶음: 내 하이라이트(내 차가 낀 장면)·레이스 하이라이트(모든 차).
enum HighlightReel { mine, race }

const List<({HighlightReel value, String label})> _reelOptions = [
  (value: HighlightReel.mine, label: '내 하이라이트'),
  (value: HighlightReel.race, label: '레이스 하이라이트'),
];

/// 하이라이트 시점(3D 카메라만).
const List<({ReplayCamera value, String label})> _cameraOptions = [
  (value: ReplayCamera.chase, label: '추격'),
  (value: ReplayCamera.broadcast, label: '중계'),
  (value: ReplayCamera.helicopter, label: '헬기'),
];

const String _title = '하이라이트';
const String _backTooltip = '세션으로';
const String _noSamplesText = '이 레이스는 하이라이트를 만들 표본이 없어요.';
const String _noTrackText = '서킷을 그릴 내 랩 기록이 없어요.';
const String _emptyReelText = '장면이 없어요.';
const String _playTooltip = '재생';
const String _pauseTooltip = '일시정지';
const String _previousTooltip = '이전 장면';
const String _nextTooltip = '다음 장면';

const int _httpNotFound = 404;
const double _headerFontSize = 22;
const double _headerGap = 8;
const EdgeInsets _cardPadding = EdgeInsets.all(16);
const double _viewRadius = 8;
const double _gap = 12;
const double _controlSpacing = 8;
const double _overlayInset = 12;
const double _bannerGap = 6;

/// 재생 화면 폭이 이보다 좁으면 순위표를 좁게(간격 칸 없이).
const double _compactTowerMaxViewWidth = 600;

/// 조작 줄 폭이 이보다 좁으면 시간 막대를 아랫줄로 내린다.
const double _singleRowControlsMinWidth = 760;

/// 재생 화면 폭이 이보다 넓으면 큰 화면 높이.
const double _wideViewMinWidth = 700;
const double _microsecondsPerMs = 1000;

/// 레이스 하이라이트 화면: 내 하이라이트·레이스 하이라이트 두 묶음을 3D로 이어 재생한다.
/// 차 위에는 드라이버 이름, 세이프티카·버추얼·적기 구간에는 깃발 배너를 띄운다.
/// 서킷 모양은 이 세션의 내 최고 랩(없으면 첫 저장 랩)과 트랙 표본 형상으로 만든다.
class SessionHighlightsPage extends ConsumerWidget {
  const SessionHighlightsPage({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(sessionDetailProvider(sessionId));
    final highlights = ref.watch(raceHighlightsProvider(sessionId));
    final style = Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: _headerFontSize, fontWeight: FontWeight.bold);
    final trackName = detail.valueOrNull?.header.trackName;

    return ListView(
      padding: pagePadding(context),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: _backTooltip,
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/sessions/${Uri.encodeComponent(sessionId)}'),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Wrap(
                spacing: _headerGap,
                children: [
                  if (trackName != null) Text(trackName, style: style),
                  Text(_title, style: style?.copyWith(fontWeight: FontWeight.w500, color: context.palette.textMuted)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (highlights.hasError)
          _isNotFound(highlights.error!)
              ? const _Message(_noSamplesText)
              : ErrorRetry(
                  error: highlights.error!,
                  fallbackMessage: '하이라이트를 불러오지 못했어요.',
                  onRetry: () => ref.invalidate(raceHighlightsProvider(sessionId)),
                )
        else if (detail.hasError)
          ErrorRetry(
            error: detail.error!,
            fallbackMessage: '세션을 불러오지 못했어요.',
            onRetry: () => ref.invalidate(sessionDetailProvider(sessionId)),
          )
        else if (!highlights.hasValue || !detail.hasValue)
          const PageLoadingBar()
        else
          _Loaded(highlights: highlights.value!, detail: detail.value!),
      ],
    );
  }

  static bool _isNotFound(Object error) => error is ApiException && error.statusCode == _httpNotFound;
}

/// 서킷 재료(내 랩 트레이스·트랙 표본 형상)를 기다린 뒤 재생기를 띄운다.
class _Loaded extends ConsumerWidget {
  const _Loaded({required this.highlights, required this.detail});

  final RaceHighlights highlights;
  final SessionDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lapId = detail.myBestLap?.lapId ?? detail.laps.map((l) => l.lapId).nonNulls.firstOrNull;
    if (lapId == null) {
      return const _Message(_noTrackText);
    }
    final trace = ref.watch(lapTraceProvider(lapId));
    final geometry = ref.watch(trackGeometryProvider((trackId: highlights.trackId, gameCode: highlights.gameCode)));
    if (trace.isLoading || geometry.isLoading) {
      return const PageLoadingBar();
    }
    final lap = trace.valueOrNull;
    if (lap == null || !lap.hasPositions) {
      return const _Message(_noTrackText);
    }
    final trackName = detail.header.trackName;
    return HighlightsPlayer(
      highlights: highlights,
      trace: lap,
      realTrack: ref.watch(trackWidthsProvider).valueOrNull?[trackName],
      trackSamples: geometry.valueOrNull,
      estimatedTrackWidthM: kEstimatedTrackWidthsM[trackName],
      streetCircuit: kStreetCircuits.contains(trackName),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: _cardPadding,
          child: Text(text, style: TextStyle(color: context.palette.textMuted)),
        ),
      );
}

/// 하이라이트 재생기: 고른 묶음의 클립을 차례로 세션 시간에 맞춰 재생한다(클립이 끝나면 다음 클립).
/// 카메라는 클립의 중심 차를 따라가고, 둘레 차도 함께 그린다.
class HighlightsPlayer extends StatefulWidget {
  const HighlightsPlayer({
    super.key,
    required this.highlights,
    required this.trace,
    this.realTrack,
    this.trackSamples,
    this.estimatedTrackWidthM,
    this.streetCircuit = false,
  });

  final RaceHighlights highlights;

  /// 서킷 모양을 잡는 내 랩(위치가 있어야 한다).
  final LapTrace trace;
  final TrackWidthProfile? realTrack;
  final TrackSampleGeometry? trackSamples;
  final double? estimatedTrackWidthM;
  final bool streetCircuit;

  @override
  State<HighlightsPlayer> createState() => _HighlightsPlayerState();
}

class _HighlightsPlayerState extends State<HighlightsPlayer> with SingleTickerProviderStateMixin {
  late final ReplayTrack3d _track = ReplayTrack3d.build(_buildCircuit());
  late HighlightReel _reel = widget.highlights.mine.isEmpty ? HighlightReel.race : HighlightReel.mine;
  ReplayCamera _camera = ReplayCamera.chase;
  int _index = 0;

  /// 지금 클립의 중심 차·둘레 차.
  TimedCarPath? _focus;
  List<ReplayFieldCar> _field = const [];

  /// 재생 시각(세션 ms).
  final ValueNotifier<double> _time = ValueNotifier<double>(0);
  late final Ticker _ticker = createTicker(_onTick);
  Duration _lastTick = Duration.zero;

  bool get _playing => _ticker.isActive;

  List<HighlightClip> get _clips => _reel == HighlightReel.mine ? widget.highlights.mine : widget.highlights.race;

  HighlightClip? get _clip => _clips.isEmpty ? null : _clips[_index];

  @override
  void initState() {
    super.initState();
    _load(0);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  ReplayCircuit _buildCircuit() {
    final player = LapReplay(widget.trace);
    final baseWidth = widget.estimatedTrackWidthM;
    return baseWidth == null
        ? ReplayCircuit.build(player, real: widget.realTrack, samples: widget.trackSamples, street: widget.streetCircuit)
        : ReplayCircuit.build(
            player,
            real: widget.realTrack,
            samples: widget.trackSamples,
            baseWidthM: baseWidth,
            street: widget.streetCircuit,
          );
  }

  Color _colorOf(int carIndex) => parseHexColor(widget.highlights.car(carIndex)?.teamColor, fallback: AppColors.accent);

  /// 클립 [index]를 준비하고 그 클립 처음으로 돌린다.
  void _load(int index) {
    _index = index;
    final clip = _clip;
    if (clip == null) {
      _focus = null;
      _field = const [];
      return;
    }
    _focus = TimedCarPath(clip.focus!);
    _field = [
      for (final car in clip.cars)
        if (car.carIndex != clip.focusCar)
          _fieldCar(car),
    ];
    _time.value = clip.startMs.toDouble();
  }

  ReplayFieldCar _fieldCar(HighlightCarTrack track) {
    final path = TimedCarPath(track);
    final name = widget.highlights.nameOf(track.carIndex);
    return (car: path, color: _colorOf(track.carIndex), label: (t) => highlightCarLabel(name, path, t));
  }

  void _onTick(Duration elapsed) {
    final clip = _clip;
    if (clip == null) {
      setState(_ticker.stop);
      return;
    }
    final deltaMs = (elapsed - _lastTick).inMicroseconds / _microsecondsPerMs;
    _lastTick = elapsed;
    final next = _time.value + deltaMs;
    if (next < clip.endMs) {
      _time.value = next;
      return;
    }
    // 클립이 끝나면 다음 클립, 마지막이면 멈춘다.
    setState(() {
      if (_index < _clips.length - 1) {
        _load(_index + 1);
      } else {
        _time.value = clip.endMs.toDouble();
        _ticker.stop();
      }
    });
  }

  void _togglePlay() {
    setState(() {
      if (_playing) {
        _ticker.stop();
        return;
      }
      final clip = _clip;
      if (clip == null) {
        return;
      }
      if (_index == _clips.length - 1 && _time.value >= clip.endMs) {
        _load(0);
      }
      _lastTick = Duration.zero;
      _ticker.start();
    });
  }

  /// 다른 클립으로 옮긴다. 재생 중이면 이어서 재생한다.
  void _jump(int index) {
    final playing = _playing;
    setState(() {
      _ticker.stop();
      _load(index);
      if (playing) {
        _lastTick = Duration.zero;
        _ticker.start();
      }
    });
  }

  void _selectReel(HighlightReel reel) {
    setState(() {
      _ticker.stop();
      _reel = reel;
      _load(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final clip = _clip;
    return Card(
      key: const ValueKey('highlights-player'),
      child: Padding(
        padding: _cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: ButtonGroup<HighlightReel>(
                options: _reelOptions,
                selected: _reel,
                onSelected: _selectReel,
                segmentKeyOf: (reel) => ValueKey('highlights-reel-${reel.name}'),
              ),
            ),
            const SizedBox(height: _gap),
            LayoutBuilder(
              builder: (context, box) => ClipRRect(
                borderRadius: BorderRadius.circular(_viewRadius),
                child: SizedBox(
                  height: box.maxWidth >= _wideViewMinWidth ? kGhostReplayWideHeight : kGhostReplayNarrowHeight,
                  child: clip == null ? _emptyView(palette) : _view(context, clip),
                ),
              ),
            ),
            const SizedBox(height: _gap),
            _controls(palette),
          ],
        ),
      ),
    );
  }

  Widget _emptyView(AppPalette palette) => ColoredBox(
        color: AppColors.replayDashPanel,
        child: Center(child: Text(_emptyReelText, style: TextStyle(color: palette.textMuted))),
      );

  Widget _view(BuildContext context, HighlightClip clip) => LayoutBuilder(builder: (context, box) => _viewSized(context, clip, box));

  /// 재생 화면(중계 그래픽: 왼쪽 순위표, 아래 자막, 위 깃발·피니시 띠). 좁으면(폰) 순위표는 간격 칸 없이 좁게.
  Widget _viewSized(BuildContext context, HighlightClip clip, BoxConstraints box) {
    final highlights = widget.highlights;
    final compact = box.maxWidth < _compactTowerMaxViewWidth;
    final towerWidth = clip.standings.isEmpty ? 0.0 : (compact ? kBroadcastCompactTowerWidth : kBroadcastTowerWidth);
    final captionLeft = _overlayInset + (towerWidth == 0 ? 0 : towerWidth + _overlayInset);
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(
          key: const ValueKey('highlights-view'),
          painter: GhostReplay3dPainter(
            player: _focus!,
            ghost: null,
            track: _track,
            camera: _camera,
            time: _time,
            playerColor: _colorOf(clip.focusCar),
            ghostColor: AppColors.accent,
            field: _field,
            playerLabel: (t) => highlightCarLabel(highlights.nameOf(clip.focusCar), _focus!, t),
            labelStyle: DefaultTextStyle.of(context).style,
          ),
        ),
        if (clip.standings.isNotEmpty)
          Positioned(
            left: _overlayInset,
            top: _overlayInset,
            bottom: _overlayInset,
            width: towerWidth,
            child: ValueListenableBuilder<double>(
              valueListenable: _time,
              builder: (context, time, _) => BroadcastStandingsTower(
                compact: compact,
                standing: clip.standingAt(time)!,
                totalLaps: highlights.totalLaps,
                nameOf: highlights.nameOf,
                colorOf: _colorOf,
                focusCar: clip.focusCar,
              ),
            ),
          ),
        Positioned(
          left: captionLeft,
          right: _overlayInset,
          bottom: _overlayInset,
          child: Align(
            alignment: Alignment.bottomLeft,
            child: BroadcastCaption(
              tag: highlightCaptionTag(clip),
              title: highlightCaptionTitle(clip, highlights.nameOf),
              accent: _colorOf(clip.focusCar),
            ),
          ),
        ),
        Positioned(
          top: _overlayInset,
          left: captionLeft,
          right: _overlayInset,
          child: ValueListenableBuilder<double>(
            valueListenable: _time,
            builder: (context, time, _) {
              final flag = activeRaceFlag(highlights.flags, time);
              final finished = highlightFinished(clip, time);
              return Column(
                children: [
                  if (flag != null) BroadcastFlagStrip(flag),
                  if (flag != null && finished) const SizedBox(height: _bannerGap),
                  if (finished) const BroadcastFinishStrip(),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _controls(AppPalette palette) {
    final clip = _clip;
    final count = _clips.length;
    final transport = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: const ValueKey('highlights-previous'),
          tooltip: _previousTooltip,
          icon: const Icon(Icons.skip_previous),
          onPressed: _index > 0 ? () => _jump(_index - 1) : null,
        ),
        IconButton(
          key: const ValueKey('highlights-play'),
          tooltip: _playing ? _pauseTooltip : _playTooltip,
          icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
          onPressed: clip == null ? null : _togglePlay,
        ),
        IconButton(
          key: const ValueKey('highlights-next'),
          tooltip: _nextTooltip,
          icon: const Icon(Icons.skip_next),
          onPressed: _index < count - 1 ? () => _jump(_index + 1) : null,
        ),
        if (count > 0) Text('${_index + 1} / $count', style: TextStyle(color: palette.textMuted)),
      ],
    );
    final views = ButtonGroup<ReplayCamera>(
      options: _cameraOptions,
      selected: _camera,
      onSelected: (camera) => setState(() => _camera = camera),
      segmentKeyOf: (camera) => ValueKey('highlights-view-${camera.name}'),
    );
    final scrub = clip == null
        ? const SizedBox.shrink()
        : ValueListenableBuilder<double>(
            valueListenable: _time,
            builder: (context, time, _) => Slider(
              key: const ValueKey('highlights-scrub'),
              value: time.clamp(clip.startMs.toDouble(), clip.endMs.toDouble()),
              min: clip.startMs.toDouble(),
              max: clip.endMs.toDouble(),
              activeColor: AppColors.accent,
              inactiveColor: palette.border,
              onChanged: (value) => _time.value = value,
            ),
          );
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth >= _singleRowControlsMinWidth
          ? Row(
              children: [
                transport,
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
                  children: [transport, views],
                ),
                scrub,
              ],
            ),
    );
  }
}
