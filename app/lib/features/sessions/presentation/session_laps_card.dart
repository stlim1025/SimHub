import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/util/lap_time.dart';
import '../../../core/widgets/compact_table.dart';
import '../../lap_detail/domain/lap_detail_display.dart';
import '../domain/session_detail_display.dart';
import '../domain/session_display.dart';
import '../domain/session_models.dart';
import 'session_widgets.dart';
import 'tyre_stints_view.dart';

const String _emptyText = '이 세션에는 랩 데이터가 없어요.';
const String _inPitText = 'IN PIT';
const String _invalidTooltip = '무효 랩';

const double _numberWidth = 32;
const double _positionWidth = 72;
const double _tyreWidth = 40;
const double _pitWidth = 64;
const double _tyreCircleSize = 20;
const double _changeGap = 4;
const double _tagRadius = 4;
const double _tagFontSize = 11;
const EdgeInsets _tagPadding = EdgeInsets.symmetric(horizontal: 6, vertical: 2);
const double _tagAlpha = 0.16;

const int _msPerMinute = 60000;
const int _msPerSecond = 1000;

/// 섹터 시간: 1분 미만 `30.123`, 이상 `1:02.345`.
String _sectorText(int? ms) {
  if (ms == null) {
    return kNoValueText;
  }
  return ms < _msPerMinute
      ? '${ms ~/ _msPerSecond}.${(ms % _msPerSecond).toString().padLeft(3, '0')}'
      : formatLapTime(ms);
}

/// Laps 카드(docs/15 §11.3): # · POS.(순위 + 변동) · 타이어 원 · IN PIT · LAP TIME · GAP(내 최고 랩 대비) · SECTOR 1·2·3.
/// 세션 최고 랩·최고 섹터는 보라(`fastestLap`), 무효 랩은 빨강. 저장된 랩이면 행을 눌러 랩 상세로 간다.
/// 600px 미만은 IN PIT·GAP·섹터를 숨긴다.
class SessionLapsCard extends StatelessWidget {
  const SessionLapsCard({super.key, required this.laps});

  final List<SessionLap> laps;

  @override
  Widget build(BuildContext context) {
    if (laps.isEmpty) {
      return const SessionCard(title: 'Laps', child: SessionEmptyText(_emptyText));
    }
    return SessionCard(
      title: 'Laps',
      padded: false,
      child: CompactTable<SessionLap>(
        framed: false,
        rows: laps,
        rowKey: (lap) => ValueKey('session-lap-${lap.lapNumber}'),
        // 저장된 랩이 하나도 없으면(옛 세션) 행을 누를 수 없게 둔다.
        onRowTap: laps.any((lap) => lap.lapId != null)
            ? (lap) {
                final lapId = lap.lapId;
                if (lapId != null) {
                  context.go(lapDetailLocation(lapId));
                }
              }
            : null,
        columns: [
          CompactColumn(label: '#', width: _numberWidth, cell: (lap) => Text('${lap.lapNumber}', style: kTabularStyle)),
          CompactColumn(label: 'Pos.', width: _positionWidth, cell: (lap) => _PositionCell(lap: lap)),
          CompactColumn(
            label: 'Tyre',
            width: _tyreWidth,
            cell: (lap) => switch (lap.visualCompound) {
              final compound? => TyreCompoundCircle(compound: compound, tooltip: compound, size: _tyreCircleSize),
              null => const Text(kNoValueText),
            },
          ),
          CompactColumn(
            label: 'In Pit',
            width: _pitWidth,
            compactHidden: true,
            cell: (lap) => lap.inPit ? const _PitTag() : const SizedBox.shrink(),
          ),
          CompactColumn(label: 'Lap Time', flex: 2, cell: (lap) => _LapTimeCell(lap: lap)),
          CompactColumn(
            label: 'Gap',
            flex: 2,
            compactHidden: true,
            cell: (lap) => Text(lapGapText(lap), style: kTabularStyle),
          ),
          for (var i = 0; i < kSessionSectorCount; i++)
            CompactColumn(
              label: 'Sector ${i + 1}',
              flex: 2,
              compactHidden: true,
              cell: (lap) => _TimeText(
                text: _sectorText(lap.sectorsMs[i]),
                color: lap.bestSectors[i] ? AppColors.fastestLap : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _PositionCell extends StatelessWidget {
  const _PositionCell({required this.lap});

  final SessionLap lap;

  @override
  Widget build(BuildContext context) {
    final position = lap.position;
    if (position == null) {
      return const Text(kNoValueText);
    }
    final change = positionChangeOf(lap.positionChange);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$position', style: kTabularStyle.copyWith(fontWeight: FontWeight.w600)),
        if (change != null && change.trend != PositionTrend.same) ...[
          const SizedBox(width: _changeGap),
          Flexible(child: PositionChangeText(change: lap.positionChange)),
        ],
      ],
    );
  }
}

class _LapTimeCell extends StatelessWidget {
  const _LapTimeCell({required this.lap});

  final SessionLap lap;

  @override
  Widget build(BuildContext context) {
    final time = lap.lapTimeMs;
    final text = time == null ? kNoValueText : formatLapTime(time);
    if (!lap.isValid) {
      return Tooltip(message: _invalidTooltip, child: _TimeText(text: text, color: context.palette.danger));
    }
    return _TimeText(text: text, color: lap.isBestLap ? AppColors.fastestLap : null, bold: lap.isBestLap);
  }
}

class _TimeText extends StatelessWidget {
  const _TimeText({required this.text, this.color, this.bold = false});

  final String text;
  final Color? color;
  final bool bold;

  @override
  Widget build(BuildContext context) => Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: kTabularStyle.copyWith(color: color, fontWeight: bold || color != null ? FontWeight.bold : null),
      );
}

/// 초록 `IN PIT` 꼬리표.
class _PitTag extends StatelessWidget {
  const _PitTag();

  @override
  Widget build(BuildContext context) {
    final color = context.palette.success;
    return Container(
      padding: _tagPadding,
      decoration: BoxDecoration(
        color: color.withValues(alpha: _tagAlpha),
        borderRadius: BorderRadius.circular(_tagRadius),
      ),
      child: Text(
        _inPitText,
        maxLines: 1,
        style: TextStyle(color: color, fontSize: _tagFontSize, fontWeight: FontWeight.bold),
      ),
    );
  }
}
