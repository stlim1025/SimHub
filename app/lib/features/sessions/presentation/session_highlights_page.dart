import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/layout_constants.dart';
import '../../../core/layout/page_padding.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/util/hex_color.dart';
import '../../../core/widgets/button_group.dart';
import '../../../core/widgets/compact_table.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/page_loading_bar.dart';
import '../../lap_detail/application/lap_detail_providers.dart';
import '../../lap_detail/domain/ghost_replay.dart';
import '../../lap_detail/domain/lap_corners.dart';
import '../../lap_detail/domain/lap_detail_models.dart';
import '../../lap_detail/presentation/ghost_replay.dart';
import '../../lap_detail/presentation/ghost_replay_3d_painter.dart';
import '../../lap_detail/presentation/replay_circuit.dart';
import '../../lap_detail/presentation/replay_corner_badge.dart';
import '../../lap_detail/presentation/replay_three_scene.dart';
import '../../lap_detail/presentation/replay_three_view.dart';
import '../../tracks/application/track_corners_provider.dart';
import '../../tracks/application/track_widths_provider.dart';
import '../../tracks/application/tracks_providers.dart';
import '../../tracks/domain/track_sample_geometry.dart';
import '../../tracks/domain/track_width_profile.dart';
import '../application/sessions_providers.dart';
import '../domain/race_highlights.dart';
import '../domain/session_models.dart';
import 'highlights_broadcast_overlay.dart';
import 'session_widgets.dart';
import 'tyre_stints_view.dart';

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

/// 장면 목록표: 재생기와의 간격, 오른쪽에 둘 때 최소·최대 폭(최소 폭이 안 남으면 재생기 아래), 아래에 둘 때 최대 높이.
const double _listGap = 12;
const double _listMinWidth = 300;
const double _listMaxWidth = 480;
const double _belowListMaxHeight = 360;

/// 장면 목록표 열: 번호·랩 칸 폭, 종류·내용 칸 비율.
const double _listIndexWidth = 24;
const double _listLapWidth = 40;
const int _listKindFlex = 3;
const int _listTitleFlex = 5;

/// 장면 종류 칩: 바탕 색 진하기, 안쪽 여백, 모서리, 점 크기, 점·글자 간격, 글자 크기.
const double _kindChipTint = 0.16;
const EdgeInsets _kindChipPadding = EdgeInsets.symmetric(horizontal: 8, vertical: 3);
const double _kindChipRadius = 4;
const double _kindDotSize = 7;
const double _kindDotGap = 6;
const double _kindFontSize = 12;

/// 드라이버 이름 앞 팀 색 막대(폭·높이), 막대·이름 간격, 이름과 화살표 사이 간격.
const double _teamBarWidth = 3;
const double _teamBarHeight = 14;
const double _teamBarGap = 6;
const double _driverJoinGap = 6;

/// 장면 종류 색: 추월 초록, 충돌 주황, 벽 충돌 빨강, 깃발은 깃발 색, 결승 금색, 출발 강조색, 리타이어·모름 흐림.
Color _kindColor(HighlightKind kind, AppPalette palette) => switch (kind) {
      HighlightKind.start => AppColors.accent,
      HighlightKind.overtake => palette.success,
      HighlightKind.collision => AppColors.wearHigh,
      HighlightKind.crash => palette.danger,
      HighlightKind.safetyCar || HighlightKind.virtualSafetyCar => AppColors.replayFlagYellow,
      HighlightKind.redFlag => AppColors.replayFlagRed,
      HighlightKind.finish => palette.podiumGold,
      HighlightKind.retirement || HighlightKind.unknown => palette.textMuted,
    };

/// 목록표 내용 칸의 차: 추월 `A → B`, 충돌 `A ↔ B`, 출발·깃발은 없음, 그 밖은 중심 차만(하단 자막과 같은 규칙).
({List<int> cars, String? join}) _sceneCars(HighlightClip clip) {
  final other = clip.otherCar;
  return switch (clip.kind) {
    HighlightKind.start || HighlightKind.safetyCar || HighlightKind.virtualSafetyCar || HighlightKind.redFlag => (
        cars: const <int>[],
        join: null,
      ),
    HighlightKind.overtake when other != null => (cars: [clip.focusCar, other], join: '→'),
    HighlightKind.collision when other != null => (cars: [clip.focusCar, other], join: '↔'),
    _ => (cars: [clip.focusCar], join: null),
  };
}
const String _listIndexLabel = '#';
const String _listLapLabel = '랩';
const String _listKindLabel = '장면';
const String _listTitleLabel = '내용';

/// 지금 장면 줄이 목록 밖이면 그 줄까지 굴리는 시간.
const Duration _listRevealDuration = Duration(milliseconds: 200);
const double _microsecondsPerMs = 1000;

/// 출발 클립 첫 순간 이 속도(km/h) 이하인 차를 그리드에 선 차로 본다(소등이 첫 표본 바로 뒤일 수 있어 정지 시간은 보지 않는다).
const double _gridStillKph = 1;

/// 출발 클립(소등 전 그리드부터 시작할 때)에서 서 있는 차들의 자리 = 실제 그리드 칸. 하나도 없으면 null.
List<ReplayGridSlot>? _startGrid(RaceHighlights highlights) {
  final slots = <int, ReplayGridSlot>{};
  for (final clip in [...highlights.race, ...highlights.mine]) {
    if (clip.kind != HighlightKind.start) {
      continue;
    }
    final t = clip.startMs.toDouble();
    for (final track in clip.cars) {
      if (slots.containsKey(track.carIndex)) {
        continue;
      }
      final path = TimedCarPath(track);
      if (!path.visibleAt(t)) {
        continue;
      }
      final now = path.frameAt(t);
      if (now.speedKph > _gridStillKph) {
        continue;
      }
      slots[track.carIndex] = (x: now.x, z: now.z, heading: now.heading);
    }
  }
  return slots.isEmpty ? null : slots.values.toList();
}

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
      // 재생 화면은 원래 폭 그대로 두고, 큰 모니터의 남는 폭에 장면 목록표를 붙인다.
      padding: pagePadding(context, maxWidth: kWideContentMaxWidth),
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
      officialCorners: ref.watch(trackCornersProvider).valueOrNull?[trackName],
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
    this.officialCorners,
  });

  final RaceHighlights highlights;

  /// 서킷 모양을 잡는 내 랩(위치가 있어야 한다).
  final LapTrace trace;
  final TrackWidthProfile? realTrack;
  final TrackSampleGeometry? trackSamples;
  final double? estimatedTrackWidthM;
  final bool streetCircuit;

  /// 이 트랙의 공식 코너(번호·위치). 없으면 주행선에서 코너를 찾는다.
  final List<OfficialCorner>? officialCorners;

  @override
  State<HighlightsPlayer> createState() => _HighlightsPlayerState();
}

class _HighlightsPlayerState extends State<HighlightsPlayer> with SingleTickerProviderStateMixin {
  late final ReplayTrack3d _track = ReplayTrack3d.build(_buildCircuit());
  late final List<ReplayGridSlot>? _grid = _startGrid(widget.highlights);

  /// 내 랩 주행선에서 찾은 코너(중심 차의 지금 코너 이름표).
  late List<LapCorner> _corners = resolveLapCorners(widget.trace, widget.officialCorners);
  late HighlightReel _reel = widget.highlights.mine.isEmpty ? HighlightReel.race : HighlightReel.mine;
  ReplayCamera _camera = ReplayCamera.chase;
  int _index = 0;

  /// 지금 클립의 중심 차·둘레 차.
  TimedCarPath? _focus;
  List<ReplayFieldCar> _field = const [];

  /// 재생 시각(세션 ms).
  final ValueNotifier<double> _time = ValueNotifier<double>(0);

  /// 장면 목록표 스크롤(지금 장면 줄을 보이게 굴린다).
  final ScrollController _listScroll = ScrollController();
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
  void didUpdateWidget(HighlightsPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 공식 코너 asset은 따로 읽히므로 늦게 올 수 있다.
    if (!identical(oldWidget.officialCorners, widget.officialCorners)) {
      _corners = resolveLapCorners(widget.trace, widget.officialCorners);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    _listScroll.dispose();
    super.dispose();
  }

  ReplayCircuit _buildCircuit() {
    final player = LapReplay(widget.trace);
    final baseWidth = widget.estimatedTrackWidthM;
    // 그리드에 선 차가 풀밭에 서지 않게 그 자리까지 도로를 넓힌다.
    final cover = [for (final slot in _grid ?? const <ReplayGridSlot>[]) Offset(slot.x, slot.z)];
    return baseWidth == null
        ? ReplayCircuit.build(
            player,
            real: widget.realTrack,
            samples: widget.trackSamples,
            street: widget.streetCircuit,
            cover: cover,
          )
        : ReplayCircuit.build(
            player,
            real: widget.realTrack,
            samples: widget.trackSamples,
            baseWidthM: baseWidth,
            street: widget.streetCircuit,
            cover: cover,
          );
  }

  Color _colorOf(int carIndex) => parseHexColor(widget.highlights.car(carIndex)?.teamColor, fallback: AppColors.accent);

  /// 클립 [index]를 준비하고 그 클립 처음으로 돌린다.
  void _load(int index) {
    _index = index;
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealListRow());
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

  /// 재생기 + 장면 목록표. 재생기는 원래 본문 폭([kContentMaxWidth])을 그대로 쓰고, 오른쪽에 목록표 폭이 남으면
  /// 오른쪽(재생기와 같은 높이), 아니면 재생기 아래에 둔다.
  @override
  Widget build(BuildContext context) {
    final player = _player(context);
    if (_clips.isEmpty) {
      return player;
    }
    return LayoutBuilder(
      builder: (context, box) {
        final spare = box.maxWidth - kContentMaxWidth - _listGap;
        if (spare < _listMinWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              player,
              const SizedBox(height: _listGap),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: _belowListMaxHeight),
                child: _list(context),
              ),
            ],
          );
        }
        final listWidth = spare.clamp(_listMinWidth, _listMaxWidth).toDouble();
        // 목록표는 재생기 높이에 맞춰 채우고, 넘치는 줄은 안에서 스크롤한다.
        return SizedBox(
          width: kContentMaxWidth + _listGap + listWidth,
          child: Stack(
            children: [
              SizedBox(width: kContentMaxWidth, child: player),
              Positioned(
                left: kContentMaxWidth + _listGap,
                top: 0,
                bottom: 0,
                width: listWidth,
                child: _list(context),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 장면 목록표: 번호·랩·종류·내용. 지금 장면 줄을 강조하고, 줄을 누르면 그 장면으로 옮긴다.
  Widget _list(BuildContext context) {
    final palette = context.palette;
    final muted = kTabularStyle.copyWith(color: palette.textMuted);
    Text cell(String text, {TextStyle? style}) => Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    return Card(
      key: const ValueKey('highlights-list'),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        controller: _listScroll,
        child: CompactTable<int>(
          framed: false,
          rows: [for (var i = 0; i < _clips.length; i++) i],
          rowKey: (i) => ValueKey('highlights-list-row-$i'),
          isHighlighted: (i) => i == _index,
          onRowTap: _jump,
          columns: [
            CompactColumn(label: _listIndexLabel, width: _listIndexWidth, cell: (i) => cell('${i + 1}', style: muted)),
            CompactColumn(label: _listLapLabel, width: _listLapWidth, cell: (i) => cell('L${_clips[i].lap}', style: kTabularStyle)),
            CompactColumn(label: _listKindLabel, flex: _listKindFlex, cell: (i) => _kindChip(i, palette)),
            CompactColumn(label: _listTitleLabel, flex: _listTitleFlex, cell: (i) => _drivers(_clips[i], palette)),
          ],
        ),
      ),
    );
  }

  /// 장면 종류 칩: 종류 색 점 + 이름, 바탕은 종류 색을 옅게.
  Widget _kindChip(int index, AppPalette palette) {
    final kind = _clips[index].kind;
    final color = _kindColor(kind, palette);
    return Container(
      key: ValueKey('highlights-list-kind-$index'),
      padding: _kindChipPadding,
      decoration: BoxDecoration(
        color: color.withValues(alpha: _kindChipTint),
        borderRadius: BorderRadius.circular(_kindChipRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: _kindDotSize,
            height: _kindDotSize,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: _kindDotGap),
          Flexible(
            child: Text(
              kHighlightKindLabels[kind]!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: _kindFontSize, fontWeight: FontWeight.w600, color: palette.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  /// 내용 칸: 드라이버마다 팀 색 막대 + 이름, 두 대면 사이에 → 또는 ↔.
  /// 한 줄 글로 이어 써서 짧은 이름이 남긴 폭을 긴 이름이 쓰고, 넘치면 끝만 말줄임.
  Widget _drivers(HighlightClip clip, AppPalette palette) {
    final scene = _sceneCars(clip);
    final cars = scene.cars;
    return Text.rich(
      TextSpan(
        children: [
          for (var i = 0; i < cars.length; i++) ...[
            if (i > 0)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _driverJoinGap),
                  child: Text(scene.join ?? '', style: TextStyle(color: palette.textMuted)),
                ),
              ),
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(right: _teamBarGap),
                child: Container(
                  key: ValueKey('highlights-list-team-${cars[i]}'),
                  width: _teamBarWidth,
                  height: _teamBarHeight,
                  color: _colorOf(cars[i]),
                ),
              ),
            ),
            TextSpan(text: widget.highlights.nameOf(cars[i])),
          ],
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// 지금 장면 줄이 목록 보이는 영역 밖이면 그 줄이 보이게 굴린다(줄 높이가 고정이라 위치를 계산한다).
  void _revealListRow() {
    if (!mounted || !_listScroll.hasClients) {
      return;
    }
    final position = _listScroll.position;
    const rowExtent = kCompactRowHeight + 1;
    final top = kCompactHeaderHeight + _index * rowExtent;
    final bottom = top + rowExtent;
    final double target;
    if (top - kCompactHeaderHeight < position.pixels) {
      target = _index == 0 ? 0 : top;
    } else if (bottom > position.pixels + position.viewportDimension) {
      target = bottom - position.viewportDimension;
    } else {
      return;
    }
    _listScroll.animateTo(target.clamp(0, position.maxScrollExtent).toDouble(), duration: _listRevealDuration, curve: Curves.easeOut);
  }

  Widget _player(BuildContext context) {
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

  /// 차 타이어 옆 띠 색: 그 순간 끼고 있는 컴파운드 색(모르면 띠 없음).
  static ReplayTyreAt? _tyreOf(ReplayCar car) {
    if (car is! TimedCarPath || car.track.tyre.isEmpty) {
      return null;
    }
    return (t) {
      final name = kHighlightTyreNames[car.tyreAt(t)];
      return name == null ? null : tyreColorOf(name);
    };
  }

  /// 3D 장면: WebGL 다시보기를 켰으면 three.js 그림 위에 이름표를 얹는다(못 쓰면 캔버스 그림으로 돌아간다), 아니면 캔버스 그림.
  Widget _scene(BuildContext context, HighlightClip clip) {
    final focus = _focus!;
    final focusColor = _colorOf(clip.focusCar);
    String focusLabel(double t) => highlightCarLabel(widget.highlights.nameOf(clip.focusCar), focus, t);
    final labelStyle = DefaultTextStyle.of(context).style;
    final canvas = CustomPaint(
      key: const ValueKey('highlights-view'),
      painter: GhostReplay3dPainter(
        player: focus,
        ghost: null,
        track: _track,
        camera: _camera,
        time: _time,
        playerColor: focusColor,
        ghostColor: AppColors.accent,
        field: _field,
        playerLabel: focusLabel,
        labelStyle: labelStyle,
      ),
    );
    if (!replayThreeEnabled) {
      return canvas;
    }
    return ReplayThreeView(
      track: _track,
      grid: _grid,
      cars: [
        (car: focus, color: focusColor, opacity: 1, tyre: _tyreOf(focus)),
        for (final other in _field) (car: other.car, color: other.color, opacity: 1, tyre: _tyreOf(other.car)),
      ],
      camera: _camera,
      time: _time,
      fallback: canvas,
      overlay: CustomPaint(
        painter: ReplayLabelsPainter(
          player: focus,
          track: _track,
          camera: _camera,
          time: _time,
          cars: [(car: focus, color: focusColor, label: focusLabel), ..._field],
          labelStyle: labelStyle,
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
        _scene(context, clip),
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
        Positioned(
          top: _overlayInset,
          right: _overlayInset,
          child: ValueListenableBuilder<double>(
            valueListenable: _time,
            builder: (context, time, _) => ReplayCornerBadge(corner: _cornerOf(_focus!, time)),
          ),
        ),
      ],
    );
  }

  /// 중심 차의 지금 코너: 그 위치에서 가장 가까운 내 랩 지점이 든 코너.
  LapCorner? _cornerOf(TimedCarPath car, double time) {
    final frame = car.frameAt(time);
    final distance = nearestLapDistance(widget.trace, frame.x, frame.z);
    return distance == null ? null : cornerAt(_corners, distance);
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
