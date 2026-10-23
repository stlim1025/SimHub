import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/util/lap_time.dart';
import '../../../core/widgets/button_group.dart';
import '../../auth/domain/user_preferences.dart';
import '../../laps/domain/lap_models.dart';
import '../domain/ghost_replay.dart';
import '../domain/lap_detail_models.dart';
import '../domain/telemetry_channels.dart';
import '../domain/telemetry_math.dart';
import 'ghost_replay_painter.dart';
import 'telemetry_chart.dart';

/// 재생 화면 높이(넓은 화면·좁은 화면).
const double kGhostReplayWideHeight = 360;
const double kGhostReplayNarrowHeight = 260;

/// 재생 배속 선택지.
const List<double> kGhostReplaySpeeds = [0.5, 1, 2, 4];
const double _defaultSpeed = 1;

const EdgeInsets _cardPadding = EdgeInsets.all(16);
const double _viewRadius = 8;
const double _controlsGap = 12;
const double _controlSpacing = 8;

/// 조작 줄 폭이 이보다 좁으면 시간 막대를 아랫줄로 내린다.
const double _singleRowControlsMinWidth = 520;
const EdgeInsets _hudInset = EdgeInsets.all(10);
const EdgeInsets _hudPadding = EdgeInsets.symmetric(horizontal: 10, vertical: 6);
const double _hudRadius = 6;
const double _hudRowGap = 4;
const double _hudDotGap = 6;

/// HUD 폭이 이보다 좁으면 시간과 두 차 정보를 위아래로 쌓는다.
const double _hudSideBySideMinWidth = 480;
const double _elapsedFontSize = 20;
const double _gapFontSize = 16;
const double _microsecondsPerMs = 1000;
const String _playTooltip = '재생';
const String _pauseTooltip = '일시정지';
const String _restartTooltip = '처음부터';

/// 배속 글자: `0.5×`·`1×`(순수 함수).
String ghostReplaySpeedLabel(double speed) => '${speed == speed.roundToDouble() ? speed.round() : speed}×';

/// 고스트 재생 카드: 이 랩과 비교 랩을 같은 시계로 달리게 해 추격 카메라로 보여 준다(타임 트라이얼 고스트처럼).
/// 재생 중에는 이 랩의 현재 거리를 [cursor]에 써서 그래프 십자선·트랙 지도 점이 따라오게 한다.
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

  @override
  State<GhostReplay> createState() => _GhostReplayState();
}

class _GhostReplayState extends State<GhostReplay> with SingleTickerProviderStateMixin {
  late LapReplay _player;
  LapReplay? _ghost;
  late Path _road;

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
    if (!identical(oldWidget.trace, widget.trace) || !identical(oldWidget.reference, widget.reference)) {
      _ticker.stop();
      _setUp();
      _time.value = 0;
    }
  }

  void _setUp() {
    _player = LapReplay(widget.trace);
    final reference = widget.reference;
    _ghost = reference != null && reference.hasPositions ? LapReplay(reference) : null;
    _road = replayRoadPath(_player);
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
                      painter: GhostReplayPainter(
                        player: _player,
                        ghost: _ghost,
                        road: _road,
                        time: _time,
                        playerColor: playerColor,
                        ghostColor: ghostColor,
                      ),
                    ),
                    ValueListenableBuilder<double>(
                      valueListenable: _time,
                      builder: (context, elapsed, _) => _Hud(
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

  /// 이 랩의 현재 거리에서 비교 랩과의 시간 차(ms). 고스트가 없으면 null.
  double? _gapAt(double elapsedMs) {
    final ghost = _ghost;
    if (ghost == null) {
      return null;
    }
    return replayGapMs(_player.trace, ghost.trace, _player.frameAt(elapsedMs).distanceM);
  }

  /// 재생·처음부터·배속, 그리고 시간 막대. 폭이 좁으면 시간 막대를 아랫줄에 둔다.
  Widget _controls(AppPalette palette) {
    final buttons = <Widget>[
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
      const SizedBox(width: _controlSpacing),
      ButtonGroup<double>(
        options: [for (final speed in kGhostReplaySpeeds) (value: speed, label: ghostReplaySpeedLabel(speed))],
        selected: _speed,
        onSelected: (speed) => setState(() => _speed = speed),
        segmentKeyOf: (speed) => ValueKey('ghost-replay-speed-$speed'),
      ),
    ];
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
                ...buttons,
                const SizedBox(width: _controlSpacing),
                Expanded(child: scrub),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: buttons),
                scrub,
              ],
            ),
    );
  }
}

/// 재생 화면 위 HUD: 왼쪽 위 경과 시간·시간 차(앞서면 초록 `-`, 뒤처지면 빨강 `+`), 오른쪽 위 두 차의 범례·속도·기어.
class _Hud extends StatelessWidget {
  const _Hud({
    required this.elapsedMs,
    required this.player,
    required this.ghost,
    required this.gapMs,
    required this.sectors,
    required this.units,
    required this.playerColor,
    required this.ghostColor,
    required this.thisLapLabel,
    required this.referenceLabel,
  });

  final double elapsedMs;
  final ReplayFrame player;
  final ReplayFrame? ghost;
  final double? gapMs;
  final List<ReplaySectorRow> sectors;
  final UnitSystem units;
  final Color playerColor;
  final Color ghostColor;
  final String thisLapLabel;
  final String referenceLabel;

  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  @override
  Widget build(BuildContext context) {
    final gap = gapMs;
    final ghostFrame = ghost;
    final timing = _box(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            formatLapTime(elapsedMs.round()),
            key: const ValueKey('ghost-replay-elapsed'),
            style: const TextStyle(
              color: AppColors.replayHudText,
              fontSize: _elapsedFontSize,
              fontWeight: FontWeight.w700,
              fontFeatures: _tabular,
            ),
          ),
          if (gap != null)
            Text(
              formatReplayGap(gap),
              key: const ValueKey('ghost-replay-gap'),
              style: TextStyle(
                color: gap < 0 ? AppColors.success : (gap > 0 ? AppColors.danger : AppColors.replayHudMuted),
                fontSize: _gapFontSize,
                fontWeight: FontWeight.w700,
                fontFeatures: _tabular,
              ),
            ),
          if (sectors.isNotEmpty) ...[
            const SizedBox(height: _hudRowGap),
            _sectorTable(),
          ],
        ],
      ),
    );
    Widget cars(CrossAxisAlignment alignment) => _box(
      Column(
        crossAxisAlignment: alignment,
        mainAxisSize: MainAxisSize.min,
        children: [
          _carRow(const ValueKey('ghost-replay-player-hud'), playerColor, thisLapLabel, player),
          if (ghostFrame != null) ...[
            const SizedBox(height: _hudRowGap),
            _carRow(const ValueKey('ghost-replay-ghost-hud'), ghostColor, referenceLabel, ghostFrame),
          ],
        ],
      ),
    );
    return Padding(
      padding: _hudInset,
      child: LayoutBuilder(
        // 넓으면 왼쪽 위 시간 · 오른쪽 위 두 차, 좁으면 왼쪽 위에 위아래로 쌓는다.
        builder: (context, box) => box.maxWidth >= _hudSideBySideMinWidth
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  timing,
                  const SizedBox(width: _hudDotGap),
                  Expanded(
                    child: Align(alignment: Alignment.topRight, child: cars(CrossAxisAlignment.end)),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  timing,
                  const SizedBox(height: _hudRowGap),
                  cars(CrossAxisAlignment.start),
                ],
              ),
      ),
    );
  }

  Widget _box(Widget child) => DecoratedBox(
    decoration: BoxDecoration(color: AppColors.replayHudBackground, borderRadius: BorderRadius.circular(_hudRadius)),
    child: Padding(padding: _hudPadding, child: child),
  );

  Widget _carRow(Key key, Color color, String label, ReplayFrame frame) {
    final keyName = (key as ValueKey<String>).value;
    final speed = units == UnitSystem.imperial ? kphToMph(frame.speedKph) : frame.speedKph;
    return Row(
      key: key,
      mainAxisSize: MainAxisSize.min,
      children: [
        ChartDot(color: color),
        const SizedBox(width: _hudDotGap),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.replayHudMuted),
          ),
        ),
        const SizedBox(width: _hudDotGap),
        Text(
          '${TelemetryChannel.speed.format(speed, units)} · ${gearLabel(frame.gear)}',
          style: const TextStyle(color: AppColors.replayHudText, fontWeight: FontWeight.w600, fontFeatures: _tabular),
        ),
        const SizedBox(width: _hudDotGap),
        _PedalBar(key: ValueKey('$keyName-throttle'), percent: frame.throttle, color: AppColors.success),
        const SizedBox(width: _pedalGap),
        _PedalBar(key: ValueKey('$keyName-brake'), percent: frame.brake, color: AppColors.danger),
      ],
    );
  }

  /// 섹터 비교 표: `S1  이 랩  비교 랩  차이`. 아직 지나지 않은 칸은 `–`, 차이는 빠르면 초록 `-`, 느리면 빨강 `+`.
  Widget _sectorTable() {
    const muted = TextStyle(color: AppColors.replayHudMuted, fontFeatures: _tabular);
    const value = TextStyle(color: AppColors.replayHudText, fontWeight: FontWeight.w600, fontFeatures: _tabular);
    String time(int? ms) => ms == null ? _notYet : formatLapTime(ms);
    return Table(
      key: const ValueKey('ghost-replay-sectors'),
      defaultColumnWidth: const IntrinsicColumnWidth(),
      children: [
        for (final row in sectors)
          TableRow(
            children: [
              Padding(padding: _sectorCellPadding, child: Text('S${row.sector}', style: muted)),
              Padding(padding: _sectorCellPadding, child: Text(time(row.playerMs), style: value, textAlign: TextAlign.end)),
              if (ghost != null)
                Padding(padding: _sectorCellPadding, child: Text(time(row.referenceMs), style: muted, textAlign: TextAlign.end)),
              if (ghost != null) _sectorDelta(row),
            ],
          ),
      ],
    );
  }

  Widget _sectorDelta(ReplaySectorRow row) {
    final playerMs = row.playerMs;
    final referenceMs = row.referenceMs;
    if (playerMs == null || referenceMs == null) {
      return const SizedBox.shrink();
    }
    final delta = (playerMs - referenceMs).toDouble();
    return Padding(
      padding: _sectorCellPadding,
      child: Text(
        formatReplayGap(delta),
        textAlign: TextAlign.end,
        style: TextStyle(
          color: delta < 0 ? AppColors.success : (delta > 0 ? AppColors.danger : AppColors.replayHudMuted),
          fontWeight: FontWeight.w700,
          fontFeatures: _tabular,
        ),
      ),
    );
  }
}

const double _pedalBarWidth = 36;
const double _pedalBarHeight = 6;
const double _pedalGap = 4;
const double _pedalMaxPercent = 100;
const String _notYet = '–';
const EdgeInsets _sectorCellPadding = EdgeInsets.only(right: 10, top: 1, bottom: 1);

/// 페달을 밟은 정도(0~100%) 막대: 어두운 바탕 위 색 채움.
class _PedalBar extends StatelessWidget {
  const _PedalBar({super.key, required this.percent, required this.color});

  final int percent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(_pedalBarHeight / 2),
      child: Container(
        width: _pedalBarWidth,
        height: _pedalBarHeight,
        color: AppColors.replayHudMuted.withValues(alpha: 0.3),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: (percent / _pedalMaxPercent).clamp(0.0, 1.0),
          heightFactor: 1,
          child: ColoredBox(color: color),
        ),
      ),
    );
  }
}
