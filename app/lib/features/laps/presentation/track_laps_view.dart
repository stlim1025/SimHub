import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/layout_constants.dart';
import '../../../core/widgets/button_group.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/pagination_bar.dart';
import '../application/laps_providers.dart';
import '../domain/lap_models.dart';
import 'empty_laps_card.dart';
import 'laps_table.dart';
import 'laps_track_picker.dart';

const String _validOnlyLabel = '유효 랩만';
const String _noValidLapsText = '유효 랩이 없습니다';
const double _sectionGap = 16;
const double _controlSpacing = 12;
const double _controlRunSpacing = 8;

const List<ButtonGroupOption<String>> _sortOptions = [
  (value: kLapSortRecent, label: 'Recent'),
  (value: kLapSortFastest, label: 'Fastest'),
];

/// 한 트랙의 내 랩 화면 본문(D-47, docs/15 §2.1): 제목 = 트랙 메뉴, `Recent | Fastest` + "유효 랩만",
/// TEAM · TIME · MODE · 날씨 · DATE 표 + 페이지 바. `/laps`(마지막 트랙)와 `/laps/tracks/:trackId`가 함께 쓴다.
/// 정렬·필터·페이지는 화면 상태이고, 바꾸면 1페이지로 돌아간다. 트랙이 바뀌면 모두 처음으로.
class TrackLapsView extends ConsumerStatefulWidget {
  const TrackLapsView({super.key, required this.trackId});

  final String trackId;

  @override
  ConsumerState<TrackLapsView> createState() => _TrackLapsViewState();
}

class _TrackLapsViewState extends ConsumerState<TrackLapsView> {
  String _sort = kLapSortRecent;
  bool _validOnly = false;
  int _page = 1;

  TrackLapsQuery get _query =>
      TrackLapsQuery(trackId: widget.trackId, sort: _sort, validOnly: _validOnly, page: _page);

  @override
  void didUpdateWidget(TrackLapsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 같은 화면 인스턴스가 다른 트랙으로 재사용되면 정렬·필터·페이지를 처음으로 돌린다.
    if (oldWidget.trackId != widget.trackId) {
      _sort = kLapSortRecent;
      _validOnly = false;
      _page = 1;
    }
  }

  void _changeSort(String sort) => setState(() {
        _sort = sort;
        _page = 1;
      });

  void _changeValidOnly(bool validOnly) => setState(() {
        _validOnly = validOnly;
        _page = 1;
      });

  void _changePage(int page) => setState(() => _page = page);

  @override
  Widget build(BuildContext context) {
    final laps = ref.watch(trackLapsProvider(_query));

    return ListView(
      padding: kPagePadding,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: LapsTrackPicker(
            trackId: widget.trackId,
            fallbackName: laps.valueOrNull?.laps.firstOrNull?.trackName,
          ),
        ),
        const SizedBox(height: _sectionGap),
        Wrap(
          spacing: _controlSpacing,
          runSpacing: _controlRunSpacing,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ButtonGroup<String>(options: _sortOptions, selected: _sort, onSelected: _changeSort),
            FilterChip(
              label: const Text(_validOnlyLabel),
              selected: _validOnly,
              visualDensity: VisualDensity.compact,
              onSelected: _changeValidOnly,
            ),
          ],
        ),
        const SizedBox(height: _sectionGap),
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
              ? EmptyLapsCard(message: _validOnly ? _noValidLapsText : kNoLapsText)
              : LapsTable(
                  laps: data.laps,
                  footer: PaginationBar(
                    page: data.page,
                    pageSize: data.pageSize,
                    total: data.total,
                    onPageChanged: _changePage,
                  ),
                ),
        ),
      ],
    );
  }
}
