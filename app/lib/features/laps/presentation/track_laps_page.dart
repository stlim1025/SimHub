import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/layout/layout_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/util/lap_time.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/pagination_bar.dart';
import '../application/laps_providers.dart';
import '../domain/lap_models.dart';
import 'empty_laps_card.dart';

/// 트랙 이름을 알 수 없을 때(로딩 중·조회 실패)의 제목.
const String _fallbackTitle = 'Laps';

/// 값이 없는 섹터 칸의 자리표시.
const String _noSectorText = '-';

/// 표에 보여주는 섹터 열 수(F1 25는 3섹터, S1·S2·S3).
const int _sectorColumnCount = 3;

const double _rowHeight = 44;

const _timeStyle = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

/// 한 트랙의 내 랩 표(docs/11 §7.3). Recent/Fastest 전환 + [kTrackLapsPageSize]개씩 페이지.
class TrackLapsPage extends ConsumerStatefulWidget {
  const TrackLapsPage({super.key, required this.trackId});

  final String trackId;

  @override
  ConsumerState<TrackLapsPage> createState() => _TrackLapsPageState();
}

class _TrackLapsPageState extends ConsumerState<TrackLapsPage> {
  String _sort = kLapSortRecent;
  int _page = 1;

  TrackLapsQuery get _query => TrackLapsQuery(trackId: widget.trackId, sort: _sort, page: _page);

  @override
  void didUpdateWidget(TrackLapsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 같은 화면 인스턴스가 다른 트랙으로 재사용되면 정렬·페이지를 처음으로 돌린다.
    if (oldWidget.trackId != widget.trackId) {
      _sort = kLapSortRecent;
      _page = 1;
    }
  }

  void _changeSort(String sort) => setState(() {
        _sort = sort;
        _page = 1;
      });

  void _changePage(int page) => setState(() => _page = page);

  String _titleOf(MyLaps? laps) {
    final tracks = ref.watch(myTracksProvider).valueOrNull;
    final fromTracks = tracks?.where((t) => t.trackId == widget.trackId).firstOrNull?.trackName;
    return fromTracks ?? laps?.laps.firstOrNull?.trackName ?? _fallbackTitle;
  }

  @override
  Widget build(BuildContext context) {
    final laps = ref.watch(trackLapsProvider(_query));

    return ListView(
      padding: kPagePadding,
      children: [
        _Header(title: _titleOf(laps.valueOrNull), onBack: () => context.go('/laps')),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: kLapSortRecent, label: Text('Recent')),
              ButtonSegment(value: kLapSortFastest, label: Text('Fastest')),
            ],
            selected: {_sort},
            onSelectionChanged: (selection) => _changeSort(selection.first),
          ),
        ),
        const SizedBox(height: 16),
        laps.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => ErrorRetry(
            error: e,
            fallbackMessage: '랩 기록을 불러오지 못했어요.',
            onRetry: () => ref.invalidate(trackLapsProvider(_query)),
          ),
          data: (data) => data.total == 0
              ? const EmptyLapsCard()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _LapsTable(laps: data.laps),
                    const SizedBox(height: 12),
                    PaginationBar(
                      page: data.page,
                      pageSize: data.pageSize,
                      total: data.total,
                      onPageChanged: _changePage,
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: '트랙 목록',
          icon: const Icon(Icons.arrow_back),
          onPressed: onBack,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

class _LapsTable extends StatelessWidget {
  const _LapsTable({required this.laps});

  static final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');

  final List<Lap> laps;

  @override
  Widget build(BuildContext context) {
    final headingStyle = Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.textMuted);

    return Card(
      // 좁은 화면에서는 표를 가로로 스크롤하고, 넓은 화면에서는 카드 폭을 채운다.
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              headingTextStyle: headingStyle,
              headingRowHeight: _rowHeight,
              dataRowMinHeight: _rowHeight,
              dataRowMaxHeight: _rowHeight,
              columns: [
                const DataColumn(label: Text('랩타임')),
                for (var n = 1; n <= _sectorColumnCount; n++) DataColumn(label: Text('S$n')),
                const DataColumn(label: Text('세션 유형')),
                const DataColumn(label: Text('날짜')),
              ],
              rows: [
                for (final lap in laps)
                  DataRow(cells: [
                    DataCell(_LapTimeCell(lap: lap)),
                    for (var n = 1; n <= _sectorColumnCount; n++)
                      DataCell(Text(_sectorText(lap, n), style: _timeStyle)),
                    DataCell(Text(lap.sessionType)),
                    DataCell(Text(_dateFormat.format(lap.setAt.toLocal()))),
                  ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _sectorText(Lap lap, int sectorNumber) {
    final sector = lap.sectors.where((s) => s.sectorNumber == sectorNumber).firstOrNull;
    return sector == null ? _noSectorText : formatLapTime(sector.sectorTimeMs);
  }
}

class _LapTimeCell extends StatelessWidget {
  const _LapTimeCell({required this.lap});

  final Lap lap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          formatLapTime(lap.lapTimeMs),
          style: _timeStyle.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 8),
        if (lap.isValid)
          const Icon(Icons.check, size: 16, color: AppColors.success, semanticLabel: '유효')
        else
          Text('무효', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.danger)),
      ],
    );
  }
}
