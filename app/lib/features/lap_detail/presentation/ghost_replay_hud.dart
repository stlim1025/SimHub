import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/util/lap_time.dart';
import '../../auth/domain/user_preferences.dart';
import '../../sessions/presentation/highlights_f1tv_graphics.dart';
import '../../sessions/presentation/tyre_stints_view.dart';
import '../domain/ghost_replay.dart';

/// 계기판 배치: 이 랩은 오른쪽, 비교 랩은 왼쪽. 넓은 화면은 아래 귀퉁이에, 좁은 화면은 차를 가리지 않게
/// 위 귀퉁이(하늘·앞길 자리)에 화면 폭 비율로 줄여 둔다. 넓어도 [_maxWidth]까지만 키운다.
const double _inset = 10;
const double _wideMaxWidthFraction = 0.32;
const double _narrowMaxWidthFraction = 0.4;
const double _narrowWidth = 520;
const double _maxWidth = 230;

// -- 이름판(설계 단위 — 속도계 설계 폭에 맞추고 화면에서는 통째로 줄인다) --------------------------------

/// 이름판: 바탕 불투명도, 안쪽 여백, 줄 사이 간격, 이름판과 속도계 사이 간격, 아래 팀 색 줄 굵기.
const double _plateOpacity = 0.94;
const EdgeInsets _platePadding = EdgeInsets.fromLTRB(16, 12, 16, 12);
const double _rowGap = 10;
const double _dialGap = 10;
const double _accentHeight = 4;

/// 이름 줄: 팀 색 띠(폭·높이)와 이름 사이 간격, 이름 글자, 타이어 표시(크기·고리 굵기·글자).
const double _stripWidth = 6;
const double _stripHeight = 30;
const double _stripGap = 12;
const double _nameFontSize = 26;
const double _tyreBadgeSize = 40;
const double _tyreRingWidth = 4;
const double _tyreFontSize = 19;

/// 시간 줄: 경과 시간·시간 차 글자와 그 사이 간격.
const double _timeFontSize = 38;
const double _gapFontSize = 27;
const double _timeGap = 16;

/// ERS 줄: 번개 아이콘, 충전/사용 막대 높이, kW 글자·칸 폭(자릿수가 바뀌어도 막대가 흔들리지 않게 고정).
const double _boltSize = 26;
const double _boltGap = 8;
const double _flowBarHeight = 8;
const double _flowFontSize = 21;
const double _flowTextWidth = 124;
const double _flowCenterWidth = 2;

/// 섹터 줄: 칸 사이 간격, 이름 글자, 밑줄 굵기, 시간·차이 글자, 줄 사이 간격.
const double _sectorGap = 12;
const double _sectorFontSize = 22;
const double _sectorBarHeight = 6;
const double _sectorTimeFontSize = 20;
const double _sectorRowGap = 6;

const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

/// 고스트 재생 계기판(F1 중계 그래픽 모양 — 하이라이트와 같은 속도계). 이 랩은 오른쪽, 비교 랩이 있으면 같은 계기판을 왼쪽에 둔다.
/// - 이름판: 팀 색 띠·이름(타이어 컴파운드), 이 랩은 그 아래 경과 시간(초록)·비교 랩과의 시간 차, ERS 충전/사용,
///   섹터 S1·S2·S3(지난 섹터는 그 랩 시간·상대 랩과의 차이, 지금 섹터는 흰 밑줄), 아래 팀 색 줄과 사선 띠.
/// - 속도계([BroadcastSpeedometer]): 바깥 고리 속도, 안쪽 고리 스로틀·브레이크, 가운데 속도·RPM·배터리 잔량, 아래 기어.
class GhostReplayHud extends StatelessWidget {
  const GhostReplayHud({
    super.key,
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
    this.tyreCompound,
    this.referenceTyreCompound,
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

  /// 이 랩 타이어(보이는 컴파운드 이름). 모르면 표시하지 않는다.
  final String? tyreCompound;

  /// 비교 랩 타이어(보이는 컴파운드 이름). 모르면 표시하지 않는다.
  final String? referenceTyreCompound;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) {
          final narrow = box.maxWidth < _narrowWidth;
          final fraction = narrow ? _narrowMaxWidthFraction : _wideMaxWidthFraction;
          final ghostFrame = ghost;
          Widget place(Widget child, {required bool right}) => Positioned(
                left: right ? null : _inset,
                right: right ? _inset : null,
                top: narrow ? _inset : null,
                bottom: narrow ? null : _inset,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: math.min(box.maxWidth * fraction, _maxWidth),
                    maxHeight: box.maxHeight - _inset * 2,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: switch ((narrow, right)) {
                      (true, true) => Alignment.topRight,
                      (true, false) => Alignment.topLeft,
                      (false, true) => Alignment.bottomRight,
                      (false, false) => Alignment.bottomLeft,
                    },
                    child: child,
                  ),
                ),
              );
          return Stack(
            children: [
              if (ghostFrame != null)
                place(
                  _dashboard(
                    keyName: 'ghost-replay-ghost-hud',
                    frame: ghostFrame,
                    color: ghostColor,
                    label: referenceLabel,
                    isPlayer: false,
                  ),
                  right: false,
                ),
              place(
                _dashboard(
                  keyName: 'ghost-replay-player-hud',
                  frame: player,
                  color: playerColor,
                  label: thisLapLabel,
                  isPlayer: true,
                ),
                right: true,
              ),
            ],
          );
        },
      );

  /// 계기판 하나: 이름판 아래 속도계. [isPlayer]면 이름판에 경과 시간·시간 차도 넣는다.
  Widget _dashboard({
    required String keyName,
    required ReplayFrame frame,
    required Color color,
    required String label,
    required bool isPlayer,
  }) =>
      SizedBox(
        key: ValueKey(keyName),
        width: kBroadcastSpeedometerSize,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _plate(keyName: keyName, frame: frame, color: color, label: label, isPlayer: isPlayer),
            const SizedBox(height: _dialGap),
            // 랩 트레이스에는 DRS·오버테이크 기록이 없어 표시 칸을 뺀다.
            BroadcastSpeedometer(
              frame: frame,
              units: units,
              showBoost: false,
              keyName: keyName,
              rootKey: ValueKey('$keyName-dial'),
            ),
          ],
        ),
      );

  /// 이름판: 어두운 판 위 이름 줄 · (이 랩) 시간 줄 · ERS 줄 · 섹터 줄, 아래 팀 색 줄과 사선 띠.
  Widget _plate({
    required String keyName,
    required ReplayFrame frame,
    required Color color,
    required String label,
    required bool isPlayer,
  }) {
    final gap = gapMs;
    final compound = isPlayer ? tyreCompound : referenceTyreCompound;
    final flow = frame.ersFlowKw;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ColoredBox(
          color: AppColors.replayF1tvPanel.withValues(alpha: _plateOpacity),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: _platePadding,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(width: _stripWidth, height: _stripHeight, color: color),
                        const SizedBox(width: _stripGap),
                        Expanded(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.replayF1tvName,
                              fontSize: _nameFontSize,
                              fontWeight: FontWeight.w800,
                              fontStyle: FontStyle.italic,
                              height: 1,
                            ),
                          ),
                        ),
                        if (compound != null) _TyreBadge(compound: compound),
                      ],
                    ),
                    if (isPlayer) ...[
                      const SizedBox(height: _rowGap),
                      // 한 줄 — 글꼴이 넓어 칸을 넘으면 줄여 맞춘다.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              formatLapTime(elapsedMs.round()),
                              key: const ValueKey('ghost-replay-elapsed'),
                              style: const TextStyle(
                                color: AppColors.replayDashTime,
                                fontSize: _timeFontSize,
                                fontWeight: FontWeight.w700,
                                fontFeatures: _tabular,
                                height: 1,
                              ),
                            ),
                            if (gap != null) ...[
                              const SizedBox(width: _timeGap),
                              Text(
                                formatReplayGap(gap),
                                key: const ValueKey('ghost-replay-gap'),
                                style: TextStyle(
                                  color: _deltaColor(gap),
                                  fontSize: _gapFontSize,
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: _tabular,
                                  height: 1,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    if (flow != null) ...[
                      const SizedBox(height: _rowGap),
                      Row(
                        children: [
                          const Icon(Icons.bolt, size: _boltSize, color: AppColors.replayF1tvBattery),
                          const SizedBox(width: _boltGap),
                          Expanded(child: _ErsFlowBar(key: ValueKey('$keyName-ers-flow'), fraction: flow / kErsMaxFlowKw)),
                          SizedBox(
                            width: _flowTextWidth,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: _ErsFlowText(textKey: ValueKey('$keyName-ers-flow-text'), flowKw: flow),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (sectors.isNotEmpty) ...[
                      const SizedBox(height: _rowGap),
                      _Sectors(
                        key: ValueKey(isPlayer ? 'ghost-replay-sectors' : 'ghost-replay-ghost-sectors'),
                        rows: sectors,
                        isPlayer: isPlayer,
                      ),
                    ],
                  ],
                ),
              ),
              Container(height: _accentHeight, color: color),
            ],
          ),
        ),
        const BroadcastHatchStrip(),
      ],
    );
  }
}

/// 앞서면 초록, 뒤지면 노랑, 같으면 흐린 색.
Color _deltaColor(double delta) => delta < 0 ? AppColors.replayFaster : (delta > 0 ? AppColors.replaySlower : AppColors.replayHudMuted);

/// 타이어 컴파운드: 컴파운드 색 고리 안 첫 글자(S·M·H·I·W).
class _TyreBadge extends StatelessWidget {
  const _TyreBadge({required this.compound});

  final String compound;

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('ghost-replay-tyre'),
        width: _tyreBadgeSize,
        height: _tyreBadgeSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.replayCarTyre,
          border: Border.all(color: tyreColorOf(compound), width: _tyreRingWidth),
        ),
        child: Text(
          compound.isEmpty ? '' : compound[0].toUpperCase(),
          style: const TextStyle(color: AppColors.replayHudText, fontSize: _tyreFontSize, fontWeight: FontWeight.w800, height: 1),
        ),
      );
}

/// 섹터 S1·S2·S3: 이름, 밑줄(지난 섹터는 차이 색, 지금 섹터는 흰색), 지난 섹터의 그 랩 시간과 상대 랩과의 차이.
class _Sectors extends StatelessWidget {
  const _Sectors({super.key, required this.rows, required this.isPlayer});

  final List<ReplaySectorRow> rows;

  /// 이 랩 계기판이면 이 랩 시간·(이 랩 − 비교 랩), 비교 랩 계기판이면 비교 랩 시간·(비교 랩 − 이 랩).
  final bool isPlayer;

  @override
  Widget build(BuildContext context) {
    final current = rows.indexWhere((r) => (isPlayer ? r.playerMs : r.referenceMs) == null);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(width: _sectorGap),
          Expanded(child: _cell(rows[i], isCurrent: i == current)),
        ],
      ],
    );
  }

  Widget _cell(ReplaySectorRow row, {required bool isCurrent}) {
    final playerMs = isPlayer ? row.playerMs : row.referenceMs;
    final referenceMs = isPlayer ? row.referenceMs : row.playerMs;
    final delta = playerMs != null && referenceMs != null ? (playerMs - referenceMs).toDouble() : null;
    final bar = isCurrent
        ? AppColors.replayHudText
        : (delta != null ? _deltaColor(delta) : (playerMs != null ? AppColors.replayHudMuted : AppColors.replayDashTrack));
    // 시간·차이는 한 줄 — 글꼴이 넓어 칸을 넘으면 줄여 맞춘다.
    Widget line(String text, Color color, FontWeight weight) => FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            text,
            style: TextStyle(color: color, fontSize: _sectorTimeFontSize, fontWeight: weight, fontFeatures: _tabular, height: 1.15),
          ),
        );
    return Column(
      children: [
        Text(
          'S${row.sector}',
          style: TextStyle(
            color: isCurrent || playerMs != null ? AppColors.replayHudText : AppColors.replayHudMuted,
            fontSize: _sectorFontSize,
            fontWeight: FontWeight.w800,
            fontStyle: FontStyle.italic,
            height: 1,
          ),
        ),
        const SizedBox(height: _sectorRowGap),
        Container(height: _sectorBarHeight, color: bar),
        if (playerMs != null) ...[
          const SizedBox(height: _sectorRowGap),
          line(formatLapTime(playerMs), AppColors.replayF1tvSilver, FontWeight.w600),
        ],
        if (delta != null) line(formatReplayGap(delta), _deltaColor(delta), FontWeight.w700),
      ],
    );
  }
}

/// 충전/사용 출력 글자: `+150 kW`(초록) · `−200 kW`(파랑) · `0 kW`.
class _ErsFlowText extends StatelessWidget {
  const _ErsFlowText({this.textKey, required this.flowKw});

  final Key? textKey;
  final double flowKw;

  @override
  Widget build(BuildContext context) {
    final kw = flowKw.round();
    final charging = kw > 0;
    return Text(
      '${charging ? '+' : (kw < 0 ? '−' : '')}${kw.abs()} kW',
      key: textKey,
      style: TextStyle(
        color: charging ? AppColors.replayThrottle : (kw < 0 ? AppColors.replayDeploy : AppColors.replayHudMuted),
        fontSize: _flowFontSize,
        fontWeight: FontWeight.w700,
        fontFeatures: _tabular,
        height: 1,
      ),
    );
  }
}

/// ERS 충전/사용 막대: 가운데에서 오른쪽(초록)으로 차면 충전, 왼쪽(파랑)으로 차면 사용. [fraction]은 −1 ~ 1.
class _ErsFlowBar extends StatelessWidget {
  const _ErsFlowBar({super.key, required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    final amount = fraction.abs().clamp(0.0, 1.0);
    final charging = fraction > 0;
    return Container(
      height: _flowBarHeight,
      color: AppColors.replayDashTrack,
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: FractionallySizedBox(
                widthFactor: charging ? 0 : amount,
                heightFactor: 1,
                child: const ColoredBox(color: AppColors.replayDeploy),
              ),
            ),
          ),
          const SizedBox(width: _flowCenterWidth, height: _flowBarHeight, child: ColoredBox(color: AppColors.replayHudText)),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: charging ? amount : 0,
                heightFactor: 1,
                child: const ColoredBox(color: AppColors.replayThrottle),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
