import 'package:flutter/material.dart';

import '../../../core/layout/equal_height.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/track_flag.dart';
import '../domain/setup_models.dart';

/// 콘텐츠 폭이 이 값 이상이면 트랙 칸 3열.
const double kTrackGridThreeColumnWidth = 900;

/// 콘텐츠 폭이 이 값 이상이면 트랙 칸 2열(미만은 1열).
const double kTrackGridTwoColumnWidth = 560;

const int _threeColumns = 3;
const int _twoColumns = 2;
const int _oneColumn = 1;
const double _gap = 12;
const double _tilePadding = 16;
const double _roundWidth = 28;
const double _flagGap = 12;
const double _nameGap = 2;
const double _trailingGap = 8;

/// 콘텐츠 폭 → 트랙 칸 열 수(순수 함수).
int trackGridColumns(double width) => width >= kTrackGridThreeColumnWidth
    ? _threeColumns
    : width >= kTrackGridTwoColumnWidth
        ? _twoColumns
        : _oneColumn;

/// F1Laps Setups·Tracks 목록 모양의 트랙 칸 격자: 라운드 번호 · 국기 · 나라 이름(굵게) · 서킷 이름(흐리게).
/// 캘린더 트랙은 들어온 순서대로 1부터 번호를 붙이고, 역방향·옛 레이아웃 트랙은 번호 없이 뒤에 둔다.
/// 각 칸은 `track-tile-{trackId}` 키를 갖는다.
class TrackGrid extends StatelessWidget {
  const TrackGrid({super.key, required this.tracks, required this.onTap, this.trailingOf});

  final List<SetupTrackSummary> tracks;
  final ValueChanged<SetupTrackSummary> onTap;

  /// 칸 오른쪽 보조 글자(예: 셋업 수). null이면 없다.
  final String? Function(SetupTrackSummary track)? trailingOf;

  @override
  Widget build(BuildContext context) {
    final ordered = [
      ...tracks.where((t) => t.isCalendarRound),
      ...tracks.where((t) => !t.isCalendarRound),
    ];
    var round = 0;
    final tiles = [
      for (final track in ordered)
        _TrackTile(
          track: track,
          round: track.isCalendarRound ? ++round : null,
          trailing: trailingOf?.call(track),
          onTap: () => onTap(track),
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = trackGridColumns(constraints.maxWidth);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var start = 0; start < tiles.length; start += columns) ...[
              if (start > 0) const SizedBox(height: _gap),
              if (columns == _oneColumn)
                tiles[start]
              else
                EqualHeightRow(
                  gap: _gap,
                  children: [
                    for (var i = start; i < start + columns; i++)
                      i < tiles.length ? tiles[i] : const SizedBox.shrink(),
                  ],
                ),
            ],
          ],
        );
      },
    );
  }
}

class _TrackTile extends StatelessWidget {
  _TrackTile({required this.track, required this.round, required this.trailing, required this.onTap})
      : super(key: ValueKey('track-tile-${track.trackId}'));

  final SetupTrackSummary track;
  final int? round;
  final String? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final muted = context.palette.textMuted;
    final circuit = track.circuitName;
    final trailingText = trailing;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(_tilePadding),
          child: Row(
            children: [
              SizedBox(
                width: _roundWidth,
                child: Text(round == null ? '' : '$round', style: textTheme.bodyMedium?.copyWith(color: muted)),
              ),
              TrackFlag(countryCode: track.countryCode),
              const SizedBox(width: _flagGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      track.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    if (circuit != null) ...[
                      const SizedBox(height: _nameGap),
                      Text(
                        circuit,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(color: muted),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailingText != null) ...[
                const SizedBox(width: _trailingGap),
                Text(trailingText, style: textTheme.bodySmall?.copyWith(color: muted)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
