import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/page_padding.dart';
import '../../../core/widgets/button_group.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/page_loading_bar.dart';
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
const double _progressHeight = 2;

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

  /// 마지막으로 받은 표(조건을 바꾸는 동안 보인다).
  MyLaps? _lastData;

  TrackLapsQuery get _query =>
      TrackLapsQuery(trackId: widget.trackId, sort: _sort, validOnly: _validOnly, page: _page);

  @override
  void didUpdateWidget(TrackLapsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 같은 화면 인스턴스가 다른 트랙으로 재사용되면 정렬·필터·페이지를 처음으로 돌린다.
    if (oldWidget.trackId != widget.trackId) {
      _lastData = null;
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
    if (laps.hasValue) {
      _lastData = laps.value;
    }
    // 이번 조건의 결과가 오기 전에는 직전 결과를 보인다(같은 트랙 안에서만 — 트랙이 바뀌면 지운다).
    final shown = laps.valueOrNull ?? (laps.isLoading ? _lastData : null);

    return ListView(
      padding: pagePadding(context),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: LapsTrackPicker(
            trackId: widget.trackId,
            fallbackName: shown?.laps.firstOrNull?.trackName,
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
        // 정렬·필터·페이지를 바꾸는 동안에는 직전 표를 그대로 두고 얇은 진행 막대만 보인다(표가 비어 튀지 않게, 막대는 본문 맨 위).
        SizedBox(height: _progressHeight, child: shown != null && laps.isLoading ? const PageLoadingBar() : null),
        const SizedBox(height: _sectionGap - _progressHeight),
        if (shown != null)
          _lapsBody(shown)
        else
          laps.when(
            loading: () => const PageLoadingBar(),
            error: (e, _) => ErrorRetry(
              error: e,
              fallbackMessage: '랩 기록을 불러오지 못했어요.',
              onRetry: () => ref.invalidate(trackLapsProvider(_query)),
            ),
            data: _lapsBody,
          ),
      ],
    );
  }

  Widget _lapsBody(MyLaps data) => data.total == 0
      ? EmptyLapsCard(message: _validOnly ? _noValidLapsText : kNoLapsText)
      : LapsTable(
          laps: data.laps,
          footer: PaginationBar(
            page: data.page,
            pageSize: data.pageSize,
            total: data.total,
            onPageChanged: _changePage,
          ),
        );
}
